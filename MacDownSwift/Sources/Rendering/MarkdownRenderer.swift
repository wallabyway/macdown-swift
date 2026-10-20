import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Converts Markdown to HTML using cmark-gfm.
nonisolated struct MarkdownRenderer: Sendable {
    struct Options: Equatable, Sendable {
        var tables = true
        var strikethrough = true
        var autolink = true
        var taskLists = true
        var footnotes = true
        var smartPunctuation = false
        var hardBreaks = false
        /// Protect `$…$` / `$$…$$` / `\(…\)` / `\[…\]` from Markdown processing so MathJax sees them intact.
        var math = false
        var inlineDollarMath = true

        static func fromDefaults(_ d: UserDefaults = .standard) -> Options {
            Options(
                tables: d.bool(forKey: Pref.mdTables),
                strikethrough: d.bool(forKey: Pref.mdStrikethrough),
                autolink: d.bool(forKey: Pref.mdAutolink),
                taskLists: d.bool(forKey: Pref.mdTaskLists),
                footnotes: d.bool(forKey: Pref.mdFootnotes),
                smartPunctuation: d.bool(forKey: Pref.mdSmartPunctuation),
                hardBreaks: d.bool(forKey: Pref.mdHardBreaks),
                math: d.bool(forKey: Pref.htmlMath),
                inlineDollarMath: d.bool(forKey: Pref.htmlMathInlineDollar)
            )
        }
    }

    var options: Options

    init(options: Options = Options()) {
        self.options = options
        cmark_gfm_core_extensions_ensure_registered()
    }

    /// Renders the Markdown body. `sourcePositions` adds `data-sourcepos` attributes (used for scroll sync).
    func html(from markdown: String, sourcePositions: Bool = true) -> String {
        var source = markdown
        var mathSpans: [String] = []
        if options.math {
            (source, mathSpans) = MathProtector.protect(markdown, inlineDollar: options.inlineDollarMath)
        }

        var flags = CMARK_OPT_UNSAFE | CMARK_OPT_VALIDATE_UTF8
        if sourcePositions { flags |= CMARK_OPT_SOURCEPOS }
        if options.footnotes { flags |= CMARK_OPT_FOOTNOTES }
        if options.smartPunctuation { flags |= CMARK_OPT_SMART }
        if options.hardBreaks { flags |= CMARK_OPT_HARDBREAKS }

        guard let parser = cmark_parser_new(flags) else { return "" }
        defer { cmark_parser_free(parser) }

        var extensions: [String] = []
        if options.tables { extensions.append("table") }
        if options.strikethrough { extensions.append("strikethrough") }
        if options.autolink { extensions.append("autolink") }
        if options.taskLists { extensions.append("tasklist") }
        for name in extensions {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        source.withCString { ptr in
            cmark_parser_feed(parser, ptr, strlen(ptr))
        }
        guard let doc = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(doc) }

        guard let cString = cmark_render_html(doc, flags, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(cString) }
        var html = String(cString: cString)

        if !mathSpans.isEmpty {
            html = MathProtector.restore(html, spans: mathSpans)
        }
        return html
    }
}

/// Swaps math spans for opaque placeholders before Markdown parsing, then restores them (HTML-escaped).
nonisolated enum MathProtector {
    private static func placeholder(_ i: Int) -> String { "MDMATHPH\(i)X" }

    // Order matters: code spans are matched first so they are left untouched.
    private static let inlinePattern: NSRegularExpression = {
        let parts = [
            #"(`+)[\s\S]*?\1"#,                        // 1: code span (kept)
            #"\$\$[\s\S]+?\$\$"#,                       // display $$…$$
            #"\\\[[\s\S]+?\\\]"#,                       // display \[…\]
            #"\\\([\s\S]+?\\\)"#,                       // inline \(…\)
        ]
        return try! NSRegularExpression(pattern: parts.joined(separator: "|"))
    }()

    private static let inlineWithDollar: NSRegularExpression = {
        let parts = [
            #"(`+)[\s\S]*?\1"#,
            #"\$\$[\s\S]+?\$\$"#,
            #"\\\[[\s\S]+?\\\]"#,
            #"\\\([\s\S]+?\\\)"#,
            #"(?<![\\$\w])\$(?![\s$])[^\n$]+?(?<![\s\\])\$(?![\w$])"#, // inline $…$
        ]
        return try! NSRegularExpression(pattern: parts.joined(separator: "|"))
    }()

    static func protect(_ text: String, inlineDollar: Bool) -> (String, [String]) {
        var spans: [String] = []
        let regex = inlineDollar ? inlineWithDollar : inlinePattern
        var output = ""
        var chunk = ""
        var fence: String? = nil

        func flushChunk() {
            guard !chunk.isEmpty else { return }
            let ns = chunk as NSString
            var result = ""
            var last = 0
            for m in regex.matches(in: chunk, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let matched = ns.substring(with: m.range)
                if m.range(at: 1).location != NSNotFound {
                    result += matched // code span
                } else {
                    result += placeholder(spans.count)
                    spans.append(matched)
                }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            output += result
            chunk = ""
        }

        // Walk line by line so fenced code blocks are never touched.
        let lines = text.components(separatedBy: "\n")
        for (idx, line) in lines.enumerated() {
            let nl = idx < lines.count - 1 ? "\n" : ""
            let trimmed = line.drop(while: { $0 == " " })
            if let f = fence {
                output += line + nl
                if trimmed.hasPrefix(f) && trimmed.trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == f.first }) {
                    fence = nil
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushChunk()
                let ch = trimmed.first!
                fence = String(trimmed.prefix(while: { $0 == ch }))
                output += line + nl
                continue
            }
            chunk += line + nl
        }
        flushChunk()
        return (output, spans)
    }

    static func restore(_ html: String, spans: [String]) -> String {
        var result = html
        for i in spans.indices {
            result = result.replacingOccurrences(of: placeholder(i), with: escapeHTML(spans[i]))
        }
        return result
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
