// Claude plan limits around the notch, for MacBooks that have one instead of a Touch Bar.
// The notch itself has no pixels, so the short label sits in black "ears" on either side
// of it; hovering drops the full line below, a click grows it into the details (details.swift).
import AppKit

final class TopPanel: NSPanel {
    // AppKit would otherwise push the window down out of the menu bar.
    override func constrainFrameRect(_ r: NSRect, to s: NSScreen?) -> NSRect { r }
    // Borderless panels refuse keyboard focus by default; the answer fields need it on click.
    override var canBecomeKey: Bool { true }
}

final class Notch: NSView {
    private let left = NSTextField(labelWithString: "")
    private let right = NSTextField(labelWithString: "")
    private let full = NSTextField(labelWithString: "")
    private let panel = TopPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
    private let always: Bool
    private let onClick: () -> Void
    private var hovering = false
    private let spark = NSTextField(labelWithString: "✳︎")
    private var usage: Usage?
    private var sessions: [Session] = []
    private var asking = 0
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    // While the details hang below, the ears are their top edge: square bottom, no hover line.
    var expanded = false { didSet { place() } }
    var frameOnScreen: NSRect? { panel.isVisible ? panel.frame : nil }

    init(always: Bool, onClick: @escaping () -> Void) {
        self.always = always
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 10
        [spark, left, right, full].forEach(addSubview)
        spark.font = .systemFont(ofSize: 13, weight: .bold)
        spark.wantsLayer = true
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
        render()
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(usage: Usage) { self.usage = usage; render() }
    func update(sessions: [Session], asking: Int) { self.sessions = sessions; self.asking = asking; render() }

    // Left of the notch: the session that most needs a look (waiting, else the latest working
    // one) with how long it has been at it, or the 5-hour limit when nothing is running.
    // Right: the limits, each in its level's colour, and how many sessions wait on you.
    private func render() {
        let line = usage?.line ?? []
        let stale = usage?.stale ?? false
        let focus = sessions.first { $0.waiting } ?? sessions.first { $0.busy }
        let waiting = max(asking, sessions.filter(\.waiting).count)
        let l = NSMutableAttributedString()
        if let s = focus {
            let name = s.name.count > 18 ? s.name.prefix(17) + "…" : s.name
            l.append(NSAttributedString(string: name, attributes: [.foregroundColor: NSColor.white, .font: font]))
            l.append(NSAttributedString(string: " \(s.waiting ? "waiting" : s.elapsed)", attributes: [
                .foregroundColor: s.waiting ? NSColor.systemOrange : .dim, .font: font]))
        } else {
            l.append(colored(line.prefix(1).map { ($0.short, $0.level) }, sep: "", stale: false, font: font))
            if line.isEmpty { l.append(NSAttributedString(string: usage == nil ? "…" : "?", attributes: [.foregroundColor: NSColor.white, .font: font])) }
        }
        left.attributedStringValue = l
        let r = NSMutableAttributedString(attributedString:
            colored((focus == nil ? line.dropFirst() : line[...]).map { ($0.short, $0.level) }, sep: " · ", stale: stale, font: font))
        if waiting > 0 {
            r.append(NSAttributedString(string: "  ● \(waiting)", attributes: [.foregroundColor: NSColor.systemOrange, .font: font]))
        }
        right.attributedStringValue = r
        spark.textColor = focus?.waiting == true || asking > 0 ? .systemOrange : .claude
        pulse(focus?.busy == true && asking == 0)
        full.attributedStringValue = usage.map { u in
            u.rows.isEmpty ? NSAttributedString(string: "Limits unavailable — retrying in a few minutes",
                                                attributes: [.foregroundColor: NSColor.white, .font: font])
                : colored(u.line.map { ($0.long, $0.level) }, sep: "  │  ", stale: u.stale, font: font)
        } ?? NSAttributedString(string: "loading…", attributes: [.foregroundColor: NSColor.white, .font: font])
        [spark, left, right, full].forEach { $0.sizeToFit() }
        place()
    }

    // The spark breathes while Claude is working.
    private func pulse(_ on: Bool) {
        guard let layer = spark.layer, on != (layer.animation(forKey: "pulse") != nil) else { return }
        guard on else { layer.removeAnimation(forKey: "pulse"); return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1
        a.toValue = 0.25
        a.duration = 0.9
        a.autoreverses = true
        a.repeatCount = .infinity
        layer.add(a, forKey: "pulse")
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
        let dropping = hovering && !expanded
        let sparkW = spark.frame.width + 3
        var minX = cx - notchW / 2 - sparkW - left.frame.width - 2 * pad
        var maxX = cx + notchW / 2 + right.frame.width + 2 * pad
        var h = notchH
        if dropping {
            minX = min(minX, cx - full.frame.width / 2 - pad)
            maxX = max(maxX, cx + full.frame.width / 2 + pad)
            h += drop
        }
        layer?.maskedCorners = expanded ? [] : [.layerMinXMinYCorner, .layerMaxXMinYCorner] // the bottom two
        let earY = h - notchH + (notchH - left.frame.height) / 2
        left.setFrameOrigin(NSPoint(x: cx - notchW / 2 - pad - left.frame.width - minX, y: earY))
        spark.setFrameOrigin(NSPoint(x: left.frame.minX - sparkW, y: earY + (left.frame.height - spark.frame.height) / 2))
        right.setFrameOrigin(NSPoint(x: cx + notchW / 2 + pad - minX, y: earY))
        full.setFrameOrigin(NSPoint(x: cx - full.frame.width / 2 - minX, y: (drop - full.frame.height) / 2 + 2))
        full.isHidden = !dropping
        panel.setFrame(NSRect(x: minX, y: screen.frame.maxY - h, width: maxX - minX, height: h), display: true)
        panel.orderFrontRegardless()
    }

    override func mouseEntered(with e: NSEvent) { hovering = true; place() }
    override func mouseExited(with e: NSEvent) { hovering = false; place() }
    override func mouseDown(with e: NSEvent) { onClick() }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
}
