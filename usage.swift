// What ccusage-line.sh reports (its third line), and the Claude Code sessions running on this Mac.
import AppKit

struct Usage: Decodable {
    struct Row: Decodable {
        let title, short, long, sub: String
        let pct: Double
        let level: Int // 0 fine, 1 getting close, 2 nearly out
        let resetsAt: Double? // limits have one; extras do not
        let inLine: Bool
    }
    let stale: Bool
    let fetched: Double
    let rows: [Row]
    var line: [Row] { rows.filter(\.inLine) }
}

extension NSColor {
    static let claude = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
    static let dim = NSColor(white: 1, alpha: 0.55)
    static func level(_ l: Int) -> NSColor { l >= 2 ? .systemRed : l == 1 ? .systemOrange : .white }
}

// The texts joined by sep, each in its level's colour, "(stale)" dimmed at the end.
func colored(_ parts: [(String, Int)], sep: String, stale: Bool, font: NSFont) -> NSAttributedString {
    let s = NSMutableAttributedString()
    for (i, (text, level)) in parts.enumerated() {
        if i > 0 { s.append(NSAttributedString(string: sep, attributes: [.foregroundColor: NSColor.dim, .font: font])) }
        s.append(NSAttributedString(string: text, attributes: [.foregroundColor: NSColor.level(level), .font: font]))
    }
    if stale { s.append(NSAttributedString(string: " (stale)", attributes: [.foregroundColor: NSColor.dim, .font: font])) }
    return s
}

// "in 2h 48m", "in 3d 4h": how long until a reset.
func until(_ t: Double) -> String {
    let m = max(0, Int((t - Date().timeIntervalSince1970) / 60))
    return m >= 1440 ? "in \(m / 1440)d \(m % 1440 / 60)h" : m >= 60 ? "in \(m / 60)h \(m % 60)m" : "in \(m)m"
}

// Claude Code keeps one file per running process in ~/.claude/sessions, status included.
// Not a documented format: anything missing just drops that session from the list.
struct Session {
    let name, status, detail: String
    let updated: Double
    var waiting: Bool { status == "waiting" }
    var busy: Bool { status == "busy" }
}

func claudeSessions() -> [Session] {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
    let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    let sessions: [Session] = files.filter { $0.pathExtension == "json" }.compactMap { url in
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = s["pid"] as? Int32, s["spare"] as? Bool != true,
              kill(pid, 0) == 0 || errno == EPERM // a crashed session leaves its file behind
        else { return nil }
        let place = ((s["cwd"] as? String) ?? "").split(separator: "/").last.map(String.init) ?? ""
        return Session(name: s["name"] as? String ?? place, status: s["status"] as? String ?? "idle",
                       detail: s["waitingFor"] as? String ?? place, updated: s["updatedAt"] as? Double ?? 0)
    }
    // The ones that need you first, then the ones working, newest first.
    let rank = { (s: Session) in s.waiting ? 0 : s.busy ? 1 : 2 }
    return sessions.sorted { (rank($0), -$0.updated) < (rank($1), -$1.updated) }
}
