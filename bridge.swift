// Claude Code asks this app instead of the terminal, through a PermissionRequest hook that runs
// this same binary as `CCUsageBar --hook` (install-hook.sh adds it to ~/.claude/settings.json).
// The hook relays its stdin to the app over a Unix socket and prints the app's reply. No app,
// or the app says "terminal": the hook prints nothing and Claude Code asks in the terminal.
import Foundation

let socketPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Caches/ccusagebar.sock").path

private func unixAddress() -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { dst in
        let src = Array(socketPath.utf8.prefix(dst.count - 1))
        dst.copyBytes(from: src)
    }
    return addr
}

private func withAddress<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
    var addr = unixAddress()
    return withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
}

private func writeAll(_ fd: Int32, _ data: Data) {
    data.withUnsafeBytes { buf in
        var off = 0
        while off < buf.count {
            let n = write(fd, buf.baseAddress! + off, buf.count - off)
            if n <= 0 { return }
            off += n
        }
    }
}

// The hook side: stdin to the app, the app's answer to stdout.
func runHook() -> Never {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    // One line on the socket, whatever the input's formatting.
    guard let obj = try? JSONSerialization.jsonObject(with: input),
          var line = try? JSONSerialization.data(withJSONObject: obj) else { exit(0) }
    line.append(0x0A)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0, withAddress({ connect(fd, $0, $1) }) == 0 else { exit(0) }
    writeAll(fd, line)
    var reply = Data(), buf = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { break }
        reply.append(buf, count: n)
    }
    FileHandle.standardOutput.write(reply)
    exit(0)
}

// A permission prompt (or question, or plan) held open until answered here or given back.
final class Request {
    let id = UUID()
    let input: [String: Any]
    fileprivate let fd: Int32
    fileprivate var source: DispatchSourceRead?
    var tool: String { input["tool_name"] as? String ?? "?" }
    var args: [String: Any] { input["tool_input"] as? [String: Any] ?? [:] }
    var sessionID: String { input["session_id"] as? String ?? "" }
    var cwd: String { input["cwd"] as? String ?? "" }
    init(input: [String: Any], fd: Int32) { self.input = input; self.fd = fd }
}

final class Bridge {
    private(set) var pending: [Request] = []
    var onChange: () -> Void = {}
    private var listener: DispatchSourceRead?

    func start() {
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, withAddress({ bind(fd, $0, $1) }) == 0, listen(fd, 16) == 0 else { return }
        chmod(socketPath, 0o600) // only this user's hooks
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        src.setEventHandler { [weak self] in
            let c = accept(fd, nil, nil)
            if c >= 0 { self?.receive(c) }
        }
        src.resume()
        listener = src
    }

    // Reads the request line, then keeps watching: the hook going away (Esc in the session,
    // the hook timing out) closes the socket, and the request is dropped.
    private func receive(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var buffer = Data(), request: Request?
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        src.setEventHandler { [weak self] in
            var buf = [UInt8](repeating: 0, count: 65536)
            let n = read(fd, &buf, buf.count)
            guard n > 0 else {
                if let r = request { self?.drop(r) } else { src.cancel() }
                return
            }
            guard request == nil else { return }
            buffer.append(buf, count: n)
            guard buffer.contains(0x0A) else { return }
            guard let obj = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any] else { src.cancel(); return }
            let r = Request(input: obj, fd: fd)
            r.source = src
            request = r
            self?.pending.append(r)
            self?.onChange()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
    }

    private func drop(_ r: Request) {
        r.source?.cancel()
        r.source = nil
        pending.removeAll { $0 === r }
        onChange()
    }

    // decision: {"behavior": "allow", "updatedInput": …} or {"behavior": "deny", "message": …};
    // nil hands the prompt back to the terminal.
    func answer(_ r: Request, _ decision: [String: Any]?) {
        if let decision, let out = try? JSONSerialization.data(withJSONObject: ["hookSpecificOutput": [
            "hookEventName": "PermissionRequest", "decision": decision]]) {
            writeAll(r.fd, out)
        }
        drop(r)
    }
}
