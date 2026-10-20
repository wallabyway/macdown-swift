import AppKit

/// Regex-based Markdown syntax highlighter for the editor. Element names match MacDown's `.style` theme keys.
final class MarkdownHighlighter {
    var theme: EditorTheme { didSet { invalidate() } }
    var font: NSFont { didSet { invalidate() } }
    var lineSpacing: CGFloat { didSet { invalidate() } }

    private(set) var baseAttributes: [NSAttributedString.Key: Any] = [:]

    init(theme: EditorTheme, font: NSFont, lineSpacing: CGFloat) {
        self.theme = theme
        self.font = font
        self.lineSpacing = lineSpacing
        invalidate()
    }

    private func invalidate() {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        baseAttributes = [
            .font: font,
            .foregroundColor: theme.foreground,
            .paragraphStyle: para,
        ]
    }

    // MARK: Rules

    private struct Rule {
        let regex: NSRegularExpression
        let element: (NSTextCheckingResult, NSString) -> String?
        let group: Int
        let replace: Bool
    }

    private static func re(_ p: String, _ o: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: o)
    }

    private static func fixed(_ name: String) -> (NSTextCheckingResult, NSString) -> String? { { _, _ in name } }

    private static let rules: [Rule] = [
        Rule(regex: re(#"^ {0,3}([-*_])([ \t]*\1){2,}[ \t]*$"#), element: fixed("HRULE"), group: 0, replace: false),
        Rule(regex: re(#"^ {0,3}>.*$"#), element: fixed("BLOCKQUOTE"), group: 0, replace: false),
        Rule(regex: re(#"^ {0,3}(#{1,6})(?:[ \t]+.*)?$"#), element: { m, s in "H\(m.range(at: 1).length)" }, group: 0, replace: false),
        Rule(regex: re(#"^(?! {0,3}(?:[-*+>]|\d+[.)])[ \t])(?=\S)[^\n]+\n {0,3}(=+|-+)[ \t]*$"#),
             element: { m, s in s.substring(with: m.range(at: 1)).hasPrefix("=") ? "H1" : "H2" }, group: 0, replace: false),
        Rule(regex: re(#"^[ \t]*([-*+])(?=[ \t])"#), element: fixed("LIST_BULLET"), group: 1, replace: false),
        Rule(regex: re(#"^[ \t]*(\d{1,9}[.)])(?=[ \t])"#), element: fixed("LIST_ENUMERATOR"), group: 1, replace: false),
        Rule(regex: re(#"^[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\])(?=[ \t])"#), element: fixed("LIST_BULLET"), group: 1, replace: false),
        Rule(regex: re(#"^ {0,3}\[[^\]\n]+\]:[ \t]*\S.*$"#), element: fixed("REFERENCE"), group: 0, replace: false),
        Rule(regex: re(#"(\*\*|__)(?=\S)[^\n]+?(?<=\S)\1"#), element: fixed("STRONG"), group: 0, replace: false),
        Rule(regex: re(#"(?<![*\w\\])\*(?=[^\s*])[^\n*]+?(?<=[^\s\\])\*(?!\*)"#), element: fixed("EMPH"), group: 0, replace: false),
        Rule(regex: re(#"(?<![_\w\\])_(?=[^\s_])[^\n_]+?(?<=\S)_(?![_\w])"#), element: fixed("EMPH"), group: 0, replace: false),
        Rule(regex: re(#"~~(?=\S)[^\n]+?(?<=\S)~~"#), element: fixed("STRIKE"), group: 0, replace: false),
        Rule(regex: re(#"<(?:https?|ftp|mailto):[^>\s]+>|\b(?:https?://|www\.)[^\s<>()]+[^\s<>().,;:!?'"*_]"#), element: fixed("AUTO_LINK_URL"), group: 0, replace: false),
        Rule(regex: re(#"<?\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b>?"#), element: fixed("AUTO_LINK_EMAIL"), group: 0, replace: false),
        Rule(regex: re(#"(?<!!)\[[^\]\n]+\](?:\([^)\n]*\)|\[[^\]\n]*\])"#), element: fixed("LINK"), group: 0, replace: false),
        Rule(regex: re(#"!\[[^\]\n]*\](?:\([^)\n]*\)|\[[^\]\n]*\])"#), element: fixed("IMAGE"), group: 0, replace: false),
        Rule(regex: re(#"&(?:#\d+|#[xX][0-9a-fA-F]+|[A-Za-z][A-Za-z0-9]*);"#), element: fixed("HTML_ENTITY"), group: 0, replace: false),
        Rule(regex: re(#"(?<!`)(`+)(?!`)[^\n]+?(?<!`)\1(?!`)"#), element: fixed("CODE"), group: 0, replace: true),
        Rule(regex: re(#"<!--[\s\S]*?-->"#, []), element: fixed("COMMENT"), group: 0, replace: true),
    ]

    // MARK: Highlighting

    func highlight(_ storage: NSTextStorage) {
        let string = storage.string as NSString
        let full = NSRange(location: 0, length: string.length)
        let fences = fencedRanges(in: string)

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)

        for rule in Self.rules {
            rule.regex.enumerateMatches(in: storage.string, range: full) { m, _, _ in
                guard let m else { return }
                let range = m.range(at: rule.group)
                guard range.location != NSNotFound, range.length > 0 else { return }
                if fences.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { return }
                if let el = rule.element(m, string) { apply(el, to: range, in: storage, replace: rule.replace) }
            }
        }
        for range in fences { apply("VERBATIM", to: range, in: storage, replace: true) }
        storage.endEditing()
    }

    /// Ranges of fenced code blocks (``` or ~~~), including the fence lines.
    private func fencedRanges(in string: NSString) -> [NSRange] {
        var result: [NSRange] = []
        var openStart: Int?
        var fenceChar: Character = "`"
        var fenceLen = 0
        var location = 0
        let length = string.length
        while location < length {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            let line = string.substring(with: lineRange)
            let trimmed = line.drop(while: { $0 == " " })
            let leading = line.count - trimmed.count
            if leading <= 3, let first = trimmed.first, first == "`" || first == "~" {
                let run = trimmed.prefix(while: { $0 == first }).count
                if run >= 3 {
                    if openStart == nil {
                        if first == "~" || !trimmed.dropFirst(run).contains("`") {
                            openStart = lineRange.location
                            fenceChar = first
                            fenceLen = run
                        }
                    } else if first == fenceChar, run >= fenceLen,
                              trimmed.dropFirst(run).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        result.append(NSRange(location: openStart!, length: NSMaxRange(lineRange) - openStart!))
                        openStart = nil
                    }
                }
            }
            location = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
        }
        if let start = openStart { result.append(NSRange(location: start, length: length - start)) }
        return result
    }

    private func apply(_ element: String, to range: NSRange, in storage: NSTextStorage, replace: Bool) {
        if replace { storage.setAttributes(baseAttributes, range: range) }
        if element == "STRIKE" {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            return
        }
        guard let style = theme.styles[element] else { return }
        if let fg = style.foreground { storage.addAttribute(.foregroundColor, value: fg, range: range) }
        if let bg = style.background { storage.addAttribute(.backgroundColor, value: bg, range: range) }
        if style.bold || style.italic || style.fontSize != nil {
            let fm = NSFontManager.shared
            storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                var f = (value as? NSFont) ?? font
                if let size = style.fontSize { f = fm.convert(f, toSize: size) }
                if style.bold { f = fm.convert(f, toHaveTrait: .boldFontMask) }
                if style.italic { f = fm.convert(f, toHaveTrait: .italicFontMask) }
                storage.addAttribute(.font, value: f, range: sub)
            }
        }
    }
}
