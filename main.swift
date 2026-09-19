// ccusage in the Touch Bar's Control Strip. Tap for the full line, tap again to hide.
// Uses the same private DFRFoundation/NSTouchBar calls MTMR and Pock rely on.
import AppKit

let script = Bundle.main.path(forResource: "ccusage-line", ofType: "sh")!
let stripID = NSTouchBarItem.Identifier("com.hikvineh.ccusagebar.strip")
let fullID = NSTouchBarItem.Identifier("com.hikvineh.ccusagebar.full")

typealias PresenceFn = @convention(c) (NSString, Bool) -> Void
let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)
let setPresence = unsafeBitCast(dlsym(dfr, "DFRElementSetControlStripPresenceForIdentifier"), to: PresenceFn.self)

final class App: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    let stripButton = NSButton(title: "✦ …", target: nil, action: nil)
    let fullButton = NSButton(title: "✦ loading…", target: nil, action: nil)
    lazy var modal: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [fullID]
        return bar
    }()
    var showingFull = false

    func applicationDidFinishLaunching(_ n: Notification) {
        stripButton.target = self; stripButton.action = #selector(toggle)
        fullButton.target = self; fullButton.action = #selector(toggle)
        fullButton.isBordered = false
        stripButton.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        stripButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true

        let item = NSCustomTouchBarItem(identifier: stripID)
        item.view = stripButton
        NSTouchBarItem.perform(NSSelectorFromString("addSystemTrayItem:"), with: item)
        setPresence(stripID.rawValue as NSString, true)

        refresh()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func touchBar(_ bar: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: id)
        item.view = fullButton
        return item
    }

    @objc func toggle() {
        showingFull.toggle()
        if showingFull {
            NSTouchBar.perform(NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:"),
                               with: modal, with: stripID.rawValue)
        } else {
            NSTouchBar.perform(NSSelectorFromString("minimizeSystemModalTouchBar:"), with: modal)
        }
        refresh()
    }

    func refresh() {
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: script)
            let pipe = Pipe()
            p.standardOutput = pipe
            try? p.run()
            p.waitUntilExit()
            let line = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }
            // "✦ $127 today · $51 block · 2h14m" -> "✦$127" in the strip
            let short = line.components(separatedBy: " today").first?.replacingOccurrences(of: " ", with: "") ?? line
            DispatchQueue.main.async {
                self.stripButton.title = short
                self.fullButton.title = line
            }
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
