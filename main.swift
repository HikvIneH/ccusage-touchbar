// Claude plan limits across the Touch Bar, always shown; around the notch on Macs that have one (notch.swift).
// Uses the same private DFRFoundation/NSTouchBar calls MTMR and Pock rely on.
import AppKit

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
    lazy var notch = mode == "touchbar" ? nil : Notch(always: mode == "notch") { [weak self] in self?.refresh() }

    func applicationDidFinishLaunching(_ n: Notification) {
        refresh()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        notch?.place()
        guard useTouchBar else { return }

        stripButton.target = self; stripButton.action = #selector(show)
        fullButton.target = self; fullButton.action = #selector(refresh)
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
            // Line 1 is the short label (the notch's ears); line 2 is the full line.
            let lines = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(separator: "\n").map(String.init)
            guard lines.count >= 2 else { return }
            DispatchQueue.main.async {
                // A Claude-coloured spark in front; a Unicode glyph, not Anthropic's logo file.
                let title = NSMutableAttributedString(string: "✳︎  ", attributes: [
                    .foregroundColor: NSColor.claude,
                    .font: NSFont.systemFont(ofSize: 17, weight: .bold)])
                title.append(NSAttributedString(string: lines[1], attributes: [
                    .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 15)]))
                self.fullButton.attributedTitle = title
                self.fullWidth.constant = ceil(title.size().width) + 16
                self.notch?.update(short: lines[0], full: lines[1])
            }
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
