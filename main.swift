// Claude plan limits across the Touch Bar, always shown, with our own Esc key
// (the system one is hidden while a system-modal Touch Bar is up).
// Uses the same private DFRFoundation/NSTouchBar calls MTMR and Pock rely on.
import AppKit

let script = Bundle.main.path(forResource: "ccusage-line", ofType: "sh")!
let stripID = NSTouchBarItem.Identifier("com.hikvineh.ccusagebar.strip")
let escID = NSTouchBarItem.Identifier("com.hikvineh.ccusagebar.esc")
let fullID = NSTouchBarItem.Identifier("com.hikvineh.ccusagebar.full")

let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)
let setPresence = unsafeBitCast(dlsym(dfr, "DFRElementSetControlStripPresenceForIdentifier"),
                                to: (@convention(c) (NSString, Bool) -> Void).self)
let showCloseBox = unsafeBitCast(dlsym(dfr, "DFRSystemModalShowsCloseBoxWhenFrontMost"),
                                 to: (@convention(c) (Bool) -> Void).self)

final class App: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    let stripButton = NSButton(title: "✦", target: nil, action: nil)
    let escButton = NSButton(title: "esc", target: nil, action: nil)
    let fullButton = NSButton(title: "loading…", target: nil, action: nil)
    lazy var modal: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [escID, fullID]
        return bar
    }()

    func applicationDidFinishLaunching(_ n: Notification) {
        // Posting Esc needs Accessibility; this asks once.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

        stripButton.target = self; stripButton.action = #selector(show)
        escButton.target = self; escButton.action = #selector(escape)
        fullButton.target = self; fullButton.action = #selector(refresh)
        fullButton.isBordered = false
        (fullButton.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        fullButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        escButton.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let item = NSCustomTouchBarItem(identifier: stripID)
        item.view = stripButton
        NSTouchBarItem.perform(NSSelectorFromString("addSystemTrayItem:"), with: item)
        setPresence(stripID.rawValue as NSString, true)

        show()
        refresh()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        // Bring it back if an app switch or anything else took it down.
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(show),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func touchBar(_ bar: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard id == escID || id == fullID else { return nil }
        let item = NSCustomTouchBarItem(identifier: id)
        item.view = id == escID ? escButton : fullButton
        return item
    }

    @objc func show() {
        // placement 0 keeps the Control Strip (brightness, volume); perform(_:with:with:) can't pass the Int.
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        let imp = method_getImplementation(class_getClassMethod(NSTouchBar.self, sel)!)
        typealias Present = @convention(c) (AnyClass, Selector, NSTouchBar, Int, NSString) -> Void
        unsafeBitCast(imp, to: Present.self)(NSTouchBar.self, sel, modal, 0, stripID.rawValue as NSString)
        showCloseBox(false)
    }

    @objc func escape() {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
        }
    }

    @objc func refresh() {
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: script)
            let pipe = Pipe()
            p.standardOutput = pipe
            try? p.run()
            p.waitUntilExit()
            // Line 2 is the full line; line 1 (the short label) is unused while always expanded.
            let lines = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(separator: "\n").map(String.init)
            guard lines.count >= 2 else { return }
            DispatchQueue.main.async { self.fullButton.title = lines[1] }
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
