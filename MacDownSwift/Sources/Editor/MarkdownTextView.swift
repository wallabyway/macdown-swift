import AppKit

/// NSTextView with Markdown-aware editing: list continuation, auto-pairing, formatting toggles.
final class MarkdownTextView: NSTextView {
    var autoPair = true
    var continueLists = true
    var insertSpacesForTab = true
    var tabWidth = 4
    /// Maximum text column width in points (0 = unlimited). Applied as horizontal inset.
    var widthLimit: CGFloat = 0 { didSet { updateInsets() } }
    var horizontalInset: CGFloat = 16 { didSet { updateInsets() } }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    private func updateInsets() {
        var h = horizontalInset
        if widthLimit > 0 { h = max(h, (bounds.width - widthLimit) / 2) }
        let inset = NSSize(width: h, height: 16)
        if textContainerInset != inset { textContainerInset = inset }
    }

    private var nsString: NSString { string as NSString }

    // MARK: Low-level edit helper (undoable)

    private func replace(_ range: NSRange, with text: String, select: NSRange? = nil) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(select ?? NSRange(location: range.location + (text as NSString).length, length: 0))
    }

    // MARK: Typing behaviour

    private static let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "`": "`", "<": ">"]
    private static let wrapOnly: Set<String> = ["*", "_", "~"]

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard autoPair, let s = (string as? String) ?? (string as? NSAttributedString)?.string, s.count == 1,
              replacementRange.location == NSNotFound, !hasMarkedText() else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let sel = selectedRange()

        // Wrap selection with pair / emphasis markers.
        if sel.length > 0, let close = Self.pairs[s] ?? (Self.wrapOnly.contains(s) ? s : nil) {
            let inner = nsString.substring(with: sel)
            replace(sel, with: s + inner + close, select: NSRange(location: sel.location + 1, length: sel.length))
            return
        }

        // Overtype a closing character that we likely inserted.
        if sel.length == 0, Self.pairs.values.contains(s), sel.location < nsString.length,
           nsString.substring(with: NSRange(location: sel.location, length: 1)) == s {
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            return
        }

        if sel.length == 0, let close = Self.pairs[s], s != "<" {
            let nextChar = sel.location < nsString.length ? nsString.character(at: sel.location) : 0x20
            let prevChar = sel.location > 0 ? nsString.character(at: sel.location - 1) : 0x20
            let nextIsSpace = nextChar == 0x20 || nextChar == 0x0A || nextChar == 0x09 || Self.pairs.values.contains(String(utf16CodeUnits: [nextChar], count: 1))
            let symmetric = close == s
            let prevIsWord = CharacterSet.alphanumerics.contains(UnicodeScalar(prevChar) ?? " ")
            if nextIsSpace && !(symmetric && prevIsWord) {
                replace(sel, with: s + close, select: NSRange(location: sel.location + 1, length: 0))
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if autoPair, sel.length == 0, sel.location > 0, sel.location < nsString.length {
            let prev = nsString.substring(with: NSRange(location: sel.location - 1, length: 1))
            let next = nsString.substring(with: NSRange(location: sel.location, length: 1))
            if let close = Self.pairs[prev], close == next {
                replace(NSRange(location: sel.location - 1, length: 2), with: "")
                return
            }
        }
        super.deleteBackward(sender)
    }

    private static let listRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*+])|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?"#)
    private static let quoteRegex = try! NSRegularExpression(pattern: #"^([ \t]*(?:>[ \t]?)+)"#)

    override func insertNewline(_ sender: Any?) {
        guard continueLists, selectedRange().length == 0 else { return super.insertNewline(sender) }
        let caret = selectedRange().location
        let lineRange = nsString.lineRange(for: NSRange(location: caret, length: 0))
        let lineStart = lineRange.location
        let lineToCaret = nsString.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        let ns = lineToCaret as NSString

        if let m = Self.listRegex.firstMatch(in: lineToCaret, range: NSRange(location: 0, length: ns.length)) {
            let rest = ns.substring(from: m.range.length).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty {
                // Empty item: end the list.
                replace(NSRange(location: lineStart, length: caret - lineStart), with: "")
                return
            }
            let indent = ns.substring(with: m.range(at: 1))
            let gap = ns.substring(with: m.range(at: 5))
            var marker: String
            if m.range(at: 2).location != NSNotFound {
                marker = ns.substring(with: m.range(at: 2))
            } else {
                let n = Int(ns.substring(with: m.range(at: 3))) ?? 0
                marker = "\(n + 1)" + ns.substring(with: m.range(at: 4))
            }
            let task = m.range(at: 6).location != NSNotFound ? "[ ] " : ""
            replace(NSRange(location: caret, length: 0), with: "\n" + indent + marker + gap + task)
            return
        }
        if let m = Self.quoteRegex.firstMatch(in: lineToCaret, range: NSRange(location: 0, length: ns.length)) {
            let prefix = ns.substring(with: m.range(at: 1))
            if ns.substring(from: m.range.length).trimmingCharacters(in: .whitespaces).isEmpty {
                replace(NSRange(location: lineStart, length: caret - lineStart), with: "")
                return
            }
            replace(NSRange(location: caret, length: 0), with: "\n" + prefix)
            return
        }
        // Keep indentation.
        let indent = String(lineToCaret.prefix(while: { $0 == " " || $0 == "\t" }))
        if !indent.isEmpty && indent.count < lineToCaret.count {
            replace(NSRange(location: caret, length: 0), with: "\n" + indent)
            return
        }
        super.insertNewline(sender)
    }

    private var indentUnit: String { insertSpacesForTab ? String(repeating: " ", count: max(1, tabWidth)) : "\t" }

    override func insertTab(_ sender: Any?) {
        let sel = selectedRange()
        let lineRange = nsString.lineRange(for: sel)
        let isListLine = Self.listRegex.firstMatch(in: nsString.substring(with: lineRange), range: NSRange(location: 0, length: lineRange.length)) != nil
        if sel.length > 0 && nsString.substring(with: sel).contains("\n") || isListLine {
            shiftRight(sender)
            return
        }
        if insertSpacesForTab { insertText(indentUnit, replacementRange: NSRange(location: NSNotFound, length: 0)) }
        else { super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) { shiftLeft(sender) }

    // MARK: Line operations

    private func transformLines(_ transform: (String) -> String) {
        let sel = selectedRange()
        var lineRange = nsString.lineRange(for: sel)
        // Don't include the trailing newline in what we transform.
        let original = nsString.substring(with: lineRange)
        let hasTrailingNewline = original.hasSuffix("\n")
        if hasTrailingNewline { lineRange.length -= 1 }
        let lines = nsString.substring(with: lineRange).components(separatedBy: "\n")
        let newText = lines.map(transform).joined(separator: "\n")
        replace(lineRange, with: newText, select: NSRange(location: lineRange.location, length: (newText as NSString).length))
    }

    @objc func shiftRight(_ sender: Any?) {
        let unit = indentUnit
        transformLines { $0.isEmpty ? $0 : unit + $0 }
    }

    @objc func shiftLeft(_ sender: Any?) {
        let width = max(1, tabWidth)
        transformLines { line in
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let spaces = line.prefix(while: { $0 == " " }).count
            return String(line.dropFirst(min(spaces, width)))
        }
    }

    private static let headingPrefix = try! NSRegularExpression(pattern: #"^#{1,6}[ \t]+"#)
    private static let anyListPrefix = try! NSRegularExpression(pattern: #"^([ \t]*)(?:[-*+]|\d{1,9}[.)])[ \t]+"#)

    private func setHeading(_ level: Int) {
        transformLines { line in
            let ns = line as NSString
            var body = line
            if let m = Self.headingPrefix.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let existing = ns.substring(with: m.range).filter { $0 == "#" }.count
                body = ns.substring(from: m.range.length)
                if existing == level { return body }
            }
            return level == 0 ? body : String(repeating: "#", count: level) + " " + body
        }
    }

    @objc func heading1(_ sender: Any?) { setHeading(1) }
    @objc func heading2(_ sender: Any?) { setHeading(2) }
    @objc func heading3(_ sender: Any?) { setHeading(3) }
    @objc func heading4(_ sender: Any?) { setHeading(4) }
    @objc func heading5(_ sender: Any?) { setHeading(5) }
    @objc func heading6(_ sender: Any?) { setHeading(6) }
    @objc func headingNone(_ sender: Any?) { setHeading(0) }

    private func togglePrefix(_ prefix: String, matching regex: NSRegularExpression, numbered: Bool = false) {
        let sel = selectedRange()
        let lines = nsString.substring(with: nsString.lineRange(for: sel)).components(separatedBy: "\n").filter { !$0.isEmpty }
        let allHave = !lines.isEmpty && lines.allSatisfy { regex.firstMatch(in: $0, range: NSRange(location: 0, length: ($0 as NSString).length)) != nil }
        var n = 0
        transformLines { line in
            guard !line.isEmpty else { return line }
            let ns = line as NSString
            let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
            if allHave, let match { return ns.substring(from: match.range.length) }
            var body = line
            if let m = Self.anyListPrefix.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                body = ns.substring(from: m.range.length)
            }
            n += 1
            return (numbered ? "\(n). " : prefix) + body
        }
    }

    private static let bulletPrefix = try! NSRegularExpression(pattern: #"^[-*+][ \t]+"#)
    private static let numberPrefix = try! NSRegularExpression(pattern: #"^\d{1,9}[.)][ \t]+"#)
    private static let quotePrefix = try! NSRegularExpression(pattern: #"^>[ \t]?"#)

    @objc func toggleUnorderedList(_ sender: Any?) { togglePrefix("- ", matching: Self.bulletPrefix) }
    @objc func toggleOrderedList(_ sender: Any?) { togglePrefix("", matching: Self.numberPrefix, numbered: true) }
    @objc func toggleBlockquote(_ sender: Any?) { togglePrefix("> ", matching: Self.quotePrefix) }

    // MARK: Inline formatting

    private func toggleWrap(_ marker: String) {
        let sel = selectedRange()
        let m = (marker as NSString).length
        // Already wrapped (markers just outside the selection)?
        if sel.location >= m, NSMaxRange(sel) + m <= nsString.length,
           nsString.substring(with: NSRange(location: sel.location - m, length: m)) == marker,
           nsString.substring(with: NSRange(location: NSMaxRange(sel), length: m)) == marker {
            let inner = nsString.substring(with: sel)
            replace(NSRange(location: sel.location - m, length: sel.length + 2 * m), with: inner,
                    select: NSRange(location: sel.location - m, length: sel.length))
            return
        }
        let inner = nsString.substring(with: sel)
        // Selection itself includes the markers?
        if inner.count >= 2 * marker.count, inner.hasPrefix(marker), inner.hasSuffix(marker) {
            let stripped = String(inner.dropFirst(marker.count).dropLast(marker.count))
            replace(sel, with: stripped, select: NSRange(location: sel.location, length: (stripped as NSString).length))
            return
        }
        replace(sel, with: marker + inner + marker, select: NSRange(location: sel.location + m, length: sel.length))
    }

    @objc func toggleStrong(_ sender: Any?) { toggleWrap("**") }
    @objc func toggleEmphasis(_ sender: Any?) { toggleWrap("*") }
    @objc func toggleInlineCode(_ sender: Any?) { toggleWrap("`") }
    @objc func toggleStrikethrough(_ sender: Any?) { toggleWrap("~~") }
    @objc func toggleHighlight(_ sender: Any?) { toggleWrap("==") }

    @objc func insertLink(_ sender: Any?) { insertLinkLike(prefix: "") }
    @objc func insertImage(_ sender: Any?) { insertLinkLike(prefix: "!") }

    private func insertLinkLike(prefix: String) {
        let sel = selectedRange()
        let inner = nsString.substring(with: sel)
        let pasteboardURL = NSPasteboard.general.string(forType: .string).flatMap { s -> String? in
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t.hasPrefix("http://") || t.hasPrefix("https://")) && !t.contains(" ") ? t : nil
        }
        if inner.hasPrefix("http://") || inner.hasPrefix("https://") {
            let text = "\(prefix)[](\(inner))"
            replace(sel, with: text, select: NSRange(location: sel.location + prefix.count + 1, length: 0))
        } else {
            let url = pasteboardURL ?? "url"
            let text = "\(prefix)[\(inner)](\(url))"
            let urlStart = sel.location + (prefix as NSString).length + 2 + (inner as NSString).length
            let select = inner.isEmpty
                ? NSRange(location: sel.location + (prefix as NSString).length + 1, length: 0)
                : NSRange(location: urlStart, length: (url as NSString).length)
            replace(sel, with: text, select: select)
        }
    }

    @objc func insertCodeBlock(_ sender: Any?) {
        let sel = selectedRange()
        let inner = nsString.substring(with: sel)
        let text = "```\n" + inner + (inner.hasSuffix("\n") || inner.isEmpty ? "" : "\n") + "```\n"
        replace(sel, with: text, select: NSRange(location: sel.location + 3, length: 0))
    }

    @objc func insertHorizontalRule(_ sender: Any?) {
        replace(selectedRange(), with: "\n---\n")
    }

    // MARK: Paste: plain text only

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
}
