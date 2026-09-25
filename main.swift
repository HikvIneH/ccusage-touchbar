// Claude plan limits across the Touch Bar, always shown; around the notch on Macs that have one (notch.swift).
// A tap or click opens the details (details.swift); crossing a threshold notifies (alerts.swift);
// Claude Code prompts arrive through bridge.swift and are answered in the details (prompt.swift).
// Uses the same private DFRFoundation/NSTouchBar calls MTMR and Pock rely on.
import AppKit

// Run by Claude Code's PermissionRequest hook: relay to the running app and exit (bridge.swift).
if CommandLine.arguments.dropFirst().first == "--hook" { runHook() }

let script = Bundle.main.path(forResource: "ccusage-line", ofType: "sh")!
let stripID = NSTouchBarItem.Identifier("com.hikvineh.ccusagebar.strip")
let fullID = NSTouchBarItem.Identifier("com.hikvineh.ccusagebar.full")

let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)
// Optional: a Mac without a Touch Bar may not have these.
let setPresence = dlsym(dfr, "DFRElementSetControlStripPresenceForIdentifier")
    .map { unsafeBitCast($0, to: (@convention(c) (NSString, Bool) -> Void).self) }
let showCloseBox = dlsym(dfr, "DFRSystemModalShowsCloseBoxWhenFrontMost")
    .map { unsafeBitCast($0, to: (@convention(c) (Bool) -> Void).self) }

// Which to show: "touchbar", "notch", or unset for whichever this Mac has.
//   defaults write com.hikvineh.ccusagebar mode notch
let mode = UserDefaults.standard.string(forKey: "mode") ?? "auto"
// No API says whether there is a Touch Bar, but the Macs that had one are a closed list.
let touchBarMacs: Set = ["MacBookPro13,2", "MacBookPro13,3", "MacBookPro14,2", "MacBookPro14,3",
    "MacBookPro15,1", "MacBookPro15,2", "MacBookPro15,3", "MacBookPro15,4", "MacBookPro16,1",
    "MacBookPro16,2", "MacBookPro16,3", "MacBookPro16,4", "MacBookPro17,1", "Mac14,7"]
let model: String = {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var buf = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.model", &buf, &size, nil, 0)
    return String(cString: buf)
}()
let useTouchBar = mode == "touchbar" || (mode == "auto" && touchBarMacs.contains(model))

final class App: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    let stripButton = NSButton(title: "✦", target: nil, action: nil)
    let fullButton = NSButton(title: "loading…", target: nil, action: nil)
    // The Touch Bar sizes an item once, so the width tracks the text explicitly.
    lazy var fullWidth = fullButton.widthAnchor.constraint(equalToConstant: 120)
    lazy var modal: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [fullID]
        return bar
    }()
    // Asked for by name, the notch line is drawn even on a screen without a notch.
    lazy var notch = mode == "touchbar" ? nil : Notch(always: mode == "notch") { [weak self] in self?.toggleDetails() }
    lazy var details = Details(onRefresh: { [weak self] in self?.refresh() },
                               onHide: { [weak self] in self?.notch?.expanded = false },
                               onAnswer: { [weak self] r, d in self?.bridge.answer(r, d) })
    let alerts = Alerts()
    let bridge = Bridge()
    var sessions: [Session] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        refresh()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        // Sessions are local files, so they can be read far more often than the usage API.
        pollSessions()
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.pollSessions() }
        notch?.place()
        bridge.onChange = { [weak self] in self?.requestsChanged() }
        bridge.start()
        guard useTouchBar else { return }

        stripButton.target = self; stripButton.action = #selector(show)
        fullButton.target = self; fullButton.action = #selector(toggleDetails)
        fullButton.isBordered = false
        (fullButton.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        fullWidth.isActive = true

        let item = NSCustomTouchBarItem(identifier: stripID)
        item.view = stripButton
        let addTray = NSSelectorFromString("addSystemTrayItem:")
        if NSTouchBarItem.responds(to: addTray) { NSTouchBarItem.perform(addTray, with: item) }
        setPresence?(stripID.rawValue as NSString, true)

        show()
        // Bring it back if an app switch or anything else took it down.
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(show),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func touchBar(_ bar: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard id == fullID else { return nil }
        let item = NSCustomTouchBarItem(identifier: id)
        item.view = fullButton
        return item
    }

    @objc func show() {
        // placement 0 keeps the Control Strip (brightness, volume); perform(_:with:with:) can't pass the Int.
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        guard let method = class_getClassMethod(NSTouchBar.self, sel) else { return }
        let imp = method_getImplementation(method)
        typealias Present = @convention(c) (AnyClass, Selector, NSTouchBar, Int, NSString) -> Void
        unsafeBitCast(imp, to: Present.self)(NSTouchBar.self, sel, modal, 0, stripID.rawValue as NSString)
        showCloseBox?(false)
    }

    @objc func refresh() {
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: script)
            let pipe = Pipe()
            p.standardOutput = pipe
            try? p.run()
            p.waitUntilExit()
            // Lines 1 and 2 are for people running the script; line 3 is the JSON to draw from.
            let lines = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(separator: "\n").map(String.init)
            guard lines.count >= 3, let usage = try? JSONDecoder().decode(Usage.self, from: Data(lines[2].utf8))
            else { return }
            DispatchQueue.main.async {
                // A Claude-coloured spark in front; a Unicode glyph, not Anthropic's logo file.
                let title = NSMutableAttributedString(string: "✳︎  ", attributes: [
                    .foregroundColor: NSColor.claude,
                    .font: NSFont.systemFont(ofSize: 17, weight: .bold)])
                let font = NSFont.systemFont(ofSize: 15)
                title.append(usage.rows.isEmpty
                    ? NSAttributedString(string: lines[1], attributes: [.foregroundColor: NSColor.white, .font: font])
                    : colored(usage.line.map { ($0.long, $0.level) }, sep: "  │  ", stale: usage.stale, font: font))
                self.fullButton.attributedTitle = title
                self.fullWidth.constant = ceil(title.size().width) + 16
                self.notch?.update(usage: usage)
                self.details.update(usage: usage)
                self.alerts.check(usage)
            }
        }
    }

    func pollSessions() {
        sessions = claudeSessions()
        notch?.update(sessions: sessions, asking: bridge.pending.count)
        details.update(sessions: sessions)
    }

    // A new prompt opens the details on it, with a sound; answering the last one puts them away.
    private var shownRequests = 0
    func requestsChanged() {
        let count = bridge.pending.count
        notch?.update(sessions: sessions, asking: count)
        details.update(requests: bridge.pending)
        if count > shownRequests {
            NSSound(named: "Tink")?.play()
            if !details.isShown { toggleDetails() }
        } else if count == 0, details.isShown {
            toggleDetails()
        }
        shownRequests = count
    }

    // Grows out of the notch when there is one showing; otherwise hangs from the menu bar.
    @objc func toggleDetails() {
        details.toggle(below: notch?.frameOnScreen)
        notch?.expanded = details.isShown
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
