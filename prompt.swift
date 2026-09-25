// What a held-open request looks like in the details: a tool to allow or deny, questions to
// answer, or a plan to approve. Built once per request, so a half-typed answer survives the
// panel redrawing around it.
import AppKit

private let mono = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

private func text(_ s: String, _ color: NSColor = .white, font: NSFont = .systemFont(ofSize: 12), lines: Int = 1) -> NSTextField {
    let l = NSTextField(wrappingLabelWithString: s)
    l.textColor = color
    l.font = font
    l.maximumNumberOfLines = lines
    l.lineBreakMode = .byTruncatingTail
    l.isSelectable = false
    return l
}

private func button(_ title: String, _ color: NSColor, _ action: @escaping () -> Void) -> NSButton {
    let b = ActionButton(title: title, action: action)
    b.bezelStyle = .rounded
    b.bezelColor = color
    b.controlSize = .large
    return b
}

final class ActionButton: NSButton {
    private var run: () -> Void = {}
    convenience init(title: String, action: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        run = action
        target = self
        self.action = #selector(fire)
    }
    @objc private func fire() { run() }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
}

// A text field that runs a closure on Enter.
final class ActionField: NSTextField {
    var run: () -> Void = {}
    convenience init() {
        self.init(frame: .zero)
        target = self
        action = #selector(fire)
    }
    @objc private func fire() { run() }
}

// A few lines of what the tool is about to do.
private func preview(_ r: Request) -> [NSView] {
    let a = r.args
    let path = { (p: String) in p.hasPrefix(r.cwd + "/") ? String(p.dropFirst(r.cwd.count + 1)) : p }
    func code(_ s: String, _ color: NSColor = .white, lines: Int = 8) -> NSTextField {
        let l = text(s, color, font: mono, lines: lines)
        l.wantsLayer = true
        l.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        l.layer?.cornerRadius = 4
        return l
    }
    switch r.tool {
    case "Bash":
        return [code(a["command"] as? String ?? ""), text(a["description"] as? String ?? "", .dim, font: .systemFont(ofSize: 11))]
    case "Edit", "MultiEdit":
        let edits = (a["edits"] as? [[String: Any]]) ?? [a]
        let diff = edits.prefix(2).flatMap { e in
            (e["old_string"] as? String ?? "").split(separator: "\n", omittingEmptySubsequences: false).prefix(3).map { "- \($0)" } +
            (e["new_string"] as? String ?? "").split(separator: "\n", omittingEmptySubsequences: false).prefix(3).map { "+ \($0)" }
        }
        let body = NSMutableAttributedString()
        for (i, l) in diff.enumerated() {
            body.append(NSAttributedString(string: (i > 0 ? "\n" : "") + l, attributes: [
                .font: mono, .foregroundColor: l.hasPrefix("-") ? NSColor.systemRed : .systemGreen]))
        }
        let d = code("")
        d.attributedStringValue = body
        return [text(path(a["file_path"] as? String ?? ""), .dim, font: mono), d]
    case "Write":
        return [text(path(a["file_path"] as? String ?? ""), .dim, font: mono), code(a["content"] as? String ?? "", lines: 6)]
    case "WebFetch":
        return [text(a["url"] as? String ?? "", .dim, font: mono, lines: 2)]
    case "WebSearch":
        return [text(a["query"] as? String ?? "", .dim, lines: 2)]
    default:
        let json = (try? JSONSerialization.data(withJSONObject: a, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return [code(json, .dim, lines: 5)]
    }
}

// "mcp__github__create_issue" → "github · create_issue"
private func toolName(_ t: String) -> String {
    t.hasPrefix("mcp__") ? t.dropFirst(5).replacingOccurrences(of: "__", with: " · ") : t
}

func requestCard(_ r: Request, session: String, width: CGFloat, answer: @escaping ([String: Any]?) -> Void) -> NSView {
    let card = NSStackView()
    card.orientation = .vertical
    card.alignment = .leading
    card.spacing = 8
    func add(_ v: NSView) {
        card.addArrangedSubview(v)
        v.widthAnchor.constraint(equalToConstant: width).isActive = true
    }
    func buttons(_ bs: [NSButton]) -> NSStackView {
        let row = NSStackView(views: [NSView()] + bs)
        row.distribution = .fill
        return row
    }
    let terminal = button("Terminal", .clear) { answer(nil) }

    switch r.tool {
    case "AskUserQuestion":
        add(text("\(session) asks", .systemOrange, font: .systemFont(ofSize: 12, weight: .semibold)))
        let questions = r.args["questions"] as? [[String: Any]] ?? []
        var answers: [String: String] = [:]
        var chosen: [String: Set<String>] = [:]
        // One pick per question; the last pick sends them all.
        let send = {
            guard answers.count == questions.count else { return }
            var input = r.args
            input["answers"] = answers
            answer(["behavior": "allow", "updatedInput": input])
        }
        for q in questions {
            let question = q["question"] as? String ?? ""
            let multi = q["multiSelect"] as? Bool ?? false
            add(text(question, font: .systemFont(ofSize: 13, weight: .medium), lines: 4))
            for o in q["options"] as? [[String: Any]] ?? [] {
                let label = o["label"] as? String ?? ""
                let b: NSButton
                if multi {
                    b = ActionButton(title: label) {
                        var set = chosen[question] ?? []
                        if set.contains(label) { set.remove(label) } else { set.insert(label) }
                        chosen[question] = set
                    }
                    b.setButtonType(.switch)
                    b.attributedTitle = NSAttributedString(string: label, attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12)])
                } else {
                    b = button(label, .controlAccentColor) { answers[question] = label; send() }
                }
                add(b)
                if let d = o["description"] as? String, !d.isEmpty { add(text(d, .dim, font: .systemFont(ofSize: 11), lines: 2)) }
            }
            // Free text, for when none of the options fit.
            let other = ActionField()
            other.placeholderString = multi ? "Other (optional), then Enter" : "Other… then Enter"
            other.run = { [unowned other] in
                let typed = other.stringValue.trimmingCharacters(in: .whitespaces)
                let picked = (chosen[question] ?? []).sorted() + (typed.isEmpty ? [] : [typed])
                guard !picked.isEmpty else { return }
                answers[question] = picked.joined(separator: ", ")
                send()
            }
            add(other)
            if multi { add(buttons([button("Done", .controlAccentColor) { other.run() }])) }
        }
        add(buttons([terminal]))

    case "ExitPlanMode":
        add(text("\(session) has a plan", .systemOrange, font: .systemFont(ofSize: 12, weight: .semibold)))
        // Measured at the card's width, then scrolled past 320 points.
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        view.isEditable = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textStorage?.setAttributedString(markdown(r.args["plan"] as? String ?? ""))
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let full = ceil(view.layoutManager?.usedRect(for: view.textContainer!).height ?? 100)
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.frame.size.height = full
        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.hasVerticalScroller = full > 320
        scroll.drawsBackground = false
        scroll.heightAnchor.constraint(equalToConstant: min(320, full)).isActive = true
        add(scroll)
        let feedback = NSTextField()
        feedback.placeholderString = "What to change (for Keep planning)"
        add(feedback)
        add(buttons([terminal,
                     button("Keep planning", .clear) {
                         let why = feedback.stringValue.trimmingCharacters(in: .whitespaces)
                         answer(["behavior": "deny", "message": why.isEmpty ? "Keep planning; don't start yet." : why])
                     },
                     button("Approve", .controlAccentColor) { answer(["behavior": "allow"]) }]))

    default:
        let head = NSMutableAttributedString(string: session, attributes: [.foregroundColor: NSColor.systemOrange, .font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
        head.append(NSAttributedString(string: " wants \(toolName(r.tool))", attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12, weight: .semibold)]))
        let h = text("")
        h.attributedStringValue = head
        add(h)
        preview(r).forEach(add)
        add(buttons([terminal,
                     button("Deny", .clear) { answer(["behavior": "deny", "message": "Denied from ccusagebar."]) },
                     button("Allow", .controlAccentColor) { answer(["behavior": "allow"]) }]))
    }
    return card
}

// Enough Markdown for a plan: headings, lists, code blocks, **bold** and `code`.
func markdown(_ s: String) -> NSAttributedString {
    let out = NSMutableAttributedString()
    let body = NSFont.systemFont(ofSize: 12)
    var fenced = false
    for raw in s.components(separatedBy: "\n") {
        var line = raw, font = body, color = NSColor.white
        if line.hasPrefix("```") { fenced.toggle(); continue }
        if fenced {
            out.append(NSAttributedString(string: line + "\n", attributes: [.font: mono, .foregroundColor: NSColor(white: 0.85, alpha: 1)]))
            continue
        }
        if let m = line.range(of: "^#{1,6} ", options: .regularExpression) {
            let level = line.distance(from: m.lowerBound, to: m.upperBound) - 1
            font = .systemFont(ofSize: level == 1 ? 15 : level == 2 ? 14 : 13, weight: .bold)
            line = String(line[m.upperBound...])
        } else if let m = line.range(of: "^\\s*([-*]|\\d+\\.) ", options: .regularExpression) {
            let indent = String(repeating: "  ", count: line.prefix(while: { $0 == " " }).count / 2)
            let marker = line[m].trimmingCharacters(in: .whitespaces)
            line = indent + (marker.first?.isNumber == true ? marker + " " : "• ") + line[m.upperBound...]
        } else if line.hasPrefix("> ") {
            color = .dim
            line = "▎ " + line.dropFirst(2)
        }
        out.append(inline(line + "\n", font: font, color: color))
    }
    return out
}

private func inline(_ s: String, font: NSFont, color: NSColor) -> NSAttributedString {
    let out = NSMutableAttributedString()
    // Split on **bold** and `code`, keeping the markers' contents.
    let pattern = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*|`([^`]+)`")
    let ns = s as NSString
    var last = 0
    for m in pattern.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
        out.append(NSAttributedString(string: ns.substring(with: NSRange(location: last, length: m.range.location - last)),
                                      attributes: [.font: font, .foregroundColor: color]))
        if m.range(at: 1).location != NSNotFound {
            out.append(NSAttributedString(string: ns.substring(with: m.range(at: 1)), attributes: [
                .font: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), .foregroundColor: color]))
        } else {
            out.append(NSAttributedString(string: ns.substring(with: m.range(at: 2)), attributes: [
                .font: mono, .foregroundColor: NSColor.claude]))
        }
        last = m.range.location + m.range.length
    }
    out.append(NSAttributedString(string: ns.substring(from: last), attributes: [.font: font, .foregroundColor: color]))
    return out
}
