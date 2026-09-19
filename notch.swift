// Claude plan limits around the notch, for MacBooks that have one instead of a Touch Bar.
// The notch itself has no pixels, so the short label sits in black "ears" on either side
// of it; hovering drops the full line below, a click refreshes.
import AppKit

extension NSColor {
    static let claude = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
}

private final class NotchPanel: NSPanel {
    // AppKit would otherwise push the window down out of the menu bar.
    override func constrainFrameRect(_ r: NSRect, to s: NSScreen?) -> NSRect { r }
}

final class Notch: NSView {
    private let left = NSTextField(labelWithString: "")
    private let right = NSTextField(labelWithString: "")
    private let full = NSTextField(labelWithString: "")
    private let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
    private let always: Bool
    private let onClick: () -> Void
    private var hovering = false
    private let text: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.white, .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]

    init(always: Bool, onClick: @escaping () -> Void) {
        self.always = always
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 10
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // the bottom two
        [left, right, full].forEach(addSubview)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
        panel.contentView = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar // above the menu bar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // The notch screen comes and goes with the lid and external displays.
        NotificationCenter.default.addObserver(self, selector: #selector(place),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        update(short: "…", full: "loading…")
    }
    required init?(coder: NSCoder) { fatalError() }

    // short is "5h 41% · wk 11% · F 14%": the session goes left of the notch, the rest right.
    func update(short: String, full line: String) {
        let parts = short.components(separatedBy: " · ")
        let l = NSMutableAttributedString(string: "✳︎ ", attributes: [
            .foregroundColor: NSColor.claude, .font: NSFont.systemFont(ofSize: 13, weight: .bold)])
        l.append(NSAttributedString(string: parts[0], attributes: text))
        left.attributedStringValue = l
        right.attributedStringValue = NSAttributedString(string: parts.dropFirst().joined(separator: " · "), attributes: text)
        full.attributedStringValue = NSAttributedString(string: line, attributes: text)
        [left, right, full].forEach { $0.sizeToFit() }
        place()
    }

    @objc func place() {
        // Without a notch there is nothing to show, unless asked to always: then mid menu bar.
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? (always ? NSScreen.main : nil)
        else { panel.orderOut(nil); return }
        // The notch is what the two menu bar areas beside it leave over.
        var notchW: CGFloat = 180, notchH = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchW = screen.frame.width - l.width - r.width
            notchH = screen.safeAreaInsets.top
        }
        let pad: CGFloat = 10, drop: CGFloat = 26, cx = screen.frame.midX
        var minX = cx - notchW / 2 - left.frame.width - 2 * pad
        var maxX = cx + notchW / 2 + right.frame.width + 2 * pad
        var h = notchH
        if hovering {
            minX = min(minX, cx - full.frame.width / 2 - pad)
            maxX = max(maxX, cx + full.frame.width / 2 + pad)
            h += drop
        }
        let earY = h - notchH + (notchH - left.frame.height) / 2
        left.setFrameOrigin(NSPoint(x: cx - notchW / 2 - pad - left.frame.width - minX, y: earY))
        right.setFrameOrigin(NSPoint(x: cx + notchW / 2 + pad - minX, y: earY))
        full.setFrameOrigin(NSPoint(x: cx - full.frame.width / 2 - minX, y: (drop - full.frame.height) / 2 + 2))
        full.isHidden = !hovering
        panel.setFrame(NSRect(x: minX, y: screen.frame.maxY - h, width: maxX - minX, height: h), display: true)
        panel.orderFrontRegardless()
    }

    override func mouseEntered(with e: NSEvent) { hovering = true; place() }
    override func mouseExited(with e: NSEvent) { hovering = false; place() }
    override func mouseDown(with e: NSEvent) { onClick() }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
}
