// The expanded view: every limit with a bar and a countdown, extra usage and credits, and the
// Claude Code sessions running now. Hangs from the notch (as the notch grown down) or, without
// one, from the middle of the menu bar. Opened by a click on the notch or a tap on the Touch Bar.
import AppKit

private final class Bar: NSView {
    var pct = 0.0, color = NSColor.white
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 5) }
    override func draw(_ r: NSRect) {
        NSColor(white: 1, alpha: 0.15).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 2.5, yRadius: 2.5).fill()
        color.setFill()
        let w = max(bounds.height, bounds.width * min(pct, 100) / 100)
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height), xRadius: 2.5, yRadius: 2.5).fill()
    }
}

final class Details: NSView {
    private let panel = TopPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
    private let stack = NSStackView()
    private let onRefresh: () -> Void
    private let onHide: () -> Void
    private var usage: Usage?
    private var sessions: [Session] = []
    private var anchor: NSRect?
    private var outside: Any?
    private(set) var isShown = false

    init(onRefresh: @escaping () -> Void, onHide: @escaping () -> Void) {
        self.onRefresh = onRefresh
        self.onHide = onHide
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 14
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // the bottom two
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                                     stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     stack.topAnchor.constraint(equalTo: topAnchor)])
        panel.contentView = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(usage: Usage) { self.usage = usage; if isShown { render() } }
    func update(sessions: [Session]) { self.sessions = sessions; if isShown { render() } }

    // below: the notch's ears, to grow out of; nil hangs it from the menu bar of the main screen.
    func toggle(below: NSRect? = nil) { isShown ? hide() : show(below: below) }

    func show(below: NSRect?) {
        anchor = below
        isShown = true
        render()
        // A click anywhere else puts it away. Mouse monitors need no Accessibility permission.
        outside = outside ?? NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        panel.orderOut(nil)
        outside.map(NSEvent.removeMonitor)
        outside = nil
        onHide()
    }

    private func label(_ s: String, _ color: NSColor = .white, size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.textColor = color
        l.font = .monospacedDigitSystemFont(ofSize: size, weight: weight)
        l.lineBreakMode = .byTruncatingTail
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    private func row(_ left: NSView, _ right: NSView) -> NSStackView {
        let r = NSStackView(views: [left, NSView(), right])
        r.distribution = .fill
        right.setContentCompressionResistancePriority(.required, for: .horizontal)
        return r
    }

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let width: CGFloat = max(340, anchor?.width ?? 0)
        func add(_ v: NSView, gap: CGFloat? = nil) {
            stack.addArrangedSubview(v)
            v.widthAnchor.constraint(equalToConstant: width - 32).isActive = true
            if let gap { stack.setCustomSpacing(gap, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2]) }
        }

        let head = NSMutableAttributedString(string: "✳︎  ", attributes: [
            .foregroundColor: NSColor.claude, .font: NSFont.systemFont(ofSize: 13, weight: .bold)])
        head.append(NSAttributedString(string: "Plan usage", attributes: [
            .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)]))
        let title = NSTextField(labelWithAttributedString: head)
        let refresh = NSButton(title: "", target: self, action: #selector(refreshNow))
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refresh.isBordered = false
        refresh.contentTintColor = .dim
        var when = "loading…"
        if let u = usage, u.fetched > 0 {
            let ago = Int(Date().timeIntervalSince1970 - u.fetched) / 60
            when = (u.stale ? "stale · " : "") + (ago < 1 ? "just now" : "\(ago)m ago")
        }
        let right = NSStackView(views: [label(when, .dim, size: 11), refresh])
        add(row(title, right))

        for r in usage?.rows ?? [] {
            let pct = label("\(Int(r.pct))%", .level(r.level), weight: .semibold)
            add(row(label(r.title, weight: .medium), pct), gap: 10)
            let bar = Bar()
            bar.pct = r.pct
            bar.color = r.level == 0 ? NSColor(white: 0.85, alpha: 1) : .level(r.level)
            add(bar)
            add(label(r.sub + (r.resetsAt.map { " · " + until($0) } ?? ""), .dim, size: 11))
        }
        if usage?.rows.isEmpty == true { add(label("Limits unavailable — retrying in a few minutes", .dim)) }

        let waiting = sessions.filter(\.waiting).count, busy = sessions.filter(\.busy).count
        let summary = [busy > 0 ? "\(busy) working" : nil, waiting > 0 ? "\(waiting) waiting" : nil,
                       "\(sessions.count - busy - waiting) idle"].compactMap { $0 }.joined(separator: " · ")
        add(row(label("Claude Code", weight: .semibold), label(sessions.isEmpty ? "none running" : summary, .dim, size: 11)),
            gap: 14)
        // Idle ones are only counted: the list is for what is moving or stuck.
        let active = sessions.filter { $0.waiting || $0.busy }
        for s in active.prefix(6) {
            let dot = label("●", s.waiting ? .systemOrange : .claude, size: 10)
            dot.setContentCompressionResistancePriority(.required, for: .horizontal)
            let name = NSStackView(views: [dot, label(s.name)])
            name.spacing = 6
            add(row(name, label(s.waiting ? "waiting: \(s.detail)" : s.detail, s.waiting ? .systemOrange : .dim, size: 11)))
        }
        if active.count > 6 { add(label("and \(active.count - 6) more", .dim, size: 11)) }

        layoutSubtreeIfNeeded()
        place(width: width, height: stack.fittingSize.height)
    }

    private func place(width: CGFloat, height: CGFloat) {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        let top = anchor?.minY ?? screen.frame.maxY - menuBar, mid = anchor?.midX ?? screen.frame.midX
        panel.setFrame(NSRect(x: mid - width / 2, y: top - height, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    @objc private func refreshNow() { onRefresh() }
}
