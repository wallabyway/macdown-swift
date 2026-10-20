import Foundation

/// Settings that affect the preview page shell (anything requiring a full reload when changed).
struct PreviewSettings: Equatable {
    var style: String
    var syntaxHighlighting: Bool
    var prismTheme: String
    var lineNumbers: Bool
    var math: Bool
    var inlineDollarMath: Bool
    var diagrams: Bool
    var peleLook: String = "white"
    var peleAnimate: String = "intro"
    var peleWebFonts: Bool = true
    var icons: Bool = true
    var diagramPadding: Int = 28

    /// The "Pele" stylesheet makes the page wear the diagram look.
    var pageLook: Bool { style == "Pele" }
    var needsPele: Bool { usesPele || icons || pageLook }
    var needsLookFonts: Bool { peleWebFonts && ((usesPele && peleLook != "none") || pageLook) }

    var usesPele: Bool { diagrams }

    static func fromDefaults(_ d: UserDefaults = .standard) -> PreviewSettings {
        PreviewSettings(
            style: d.string(forKey: Pref.htmlStyle) ?? "GitHub2",
            syntaxHighlighting: d.bool(forKey: Pref.htmlSyntaxHighlighting),
            prismTheme: d.string(forKey: Pref.htmlPrismTheme) ?? "prism",
            lineNumbers: d.bool(forKey: Pref.htmlLineNumbers),
            math: d.bool(forKey: Pref.htmlMath),
            inlineDollarMath: d.bool(forKey: Pref.htmlMathInlineDollar),
            diagrams: d.bool(forKey: Pref.htmlDiagrams),
            peleLook: d.string(forKey: Pref.peleLook) ?? "white",
            peleAnimate: d.string(forKey: Pref.peleAnimate) ?? "intro",
            peleWebFonts: d.bool(forKey: Pref.peleWebFonts),
            icons: d.bool(forKey: Pref.htmlIcons),
            diagramPadding: d.integer(forKey: Pref.diagramPadding)
        )
    }

    var isDarkStyle: Bool { style.localizedCaseInsensitiveContains("dark") }
}

/// Builds full HTML documents around rendered Markdown.
enum HTMLPage {
    private static var web: URL { ResourceLocator.webDirectory }

    private static func styleURL(_ s: PreviewSettings) -> URL? {
        ResourceLocator.url(named: s.style, in: "Styles", ext: "css")
    }

    private static func prismThemeURL(_ s: PreviewSettings) -> URL {
        web.appendingPathComponent("prism/themes/\(s.prismTheme).min.css")
    }

    private static var extraCSS: String {
        """
        :where(.pele-diagram) { text-align: center; margin: 1.25em 0 1em; padding: 4px 0 6px; } /* zero specificity: a stylesheet's own spacing wins */
        .pele-diagram svg { max-width: 100%; height: auto; }
        .diagram-error { color: #c33; white-space: pre-wrap; text-align: left; }
        li:has(> input[type=checkbox]:first-child) { list-style-type: none; }
        li > input[type=checkbox]:first-child { margin: 0 0.4em 0.2em -1.3em; vertical-align: middle; }
        mjx-container[display="true"] { overflow-x: auto; overflow-y: hidden; }
        img { max-width: 100%; }
        :where(table) { margin-left: auto; margin-right: auto; }
        .md-icon { display: inline-block; vertical-align: -0.2em; }
        """
    }

    /// Same as `pele.LOOK_FONTS_URL`; the looks' intended web fonts. Falls back to system fonts offline.
    static let peleFontsURL =
        "https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;500;700&family=Roboto+Mono:wght@400;700" +
        "&family=Inter:wght@400;500;600;700&family=Space+Grotesk:wght@500;700&family=IBM+Plex+Sans:wght@400;500;600" +
        "&family=IBM+Plex+Mono:wght@400;600&family=Fraunces:ital,opsz,wght@0,9..144,600;1,9..144,500" +
        "&family=JetBrains+Mono:wght@400;700&family=Nunito:wght@500;700;800&family=Fredoka:wght@500;600" +
        "&family=Orbitron:wght@600;800&display=swap"

    private static func mathJaxConfig(_ s: PreviewSettings) -> String {
        var inline = #"['\\(', '\\)']"#
        if s.inlineDollarMath { inline += #", ['$', '$']"# }
        return """
        window.MathJax = {
          tex: { inlineMath: [\(inline)], displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']], processEscapes: true },
          svg: { fontCache: 'local' },
          options: { skipHtmlTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'] },
          startup: { typeset: false }
        };
        """
    }

    private static func escape(_ s: String) -> String { MathProtector.escapeHTML(s).replacingOccurrences(of: "\"", with: "&quot;") }

    /// Page used by the live preview. References bundled resources by file URL.
    static func preview(body: String, title: String, baseURL: URL?, settings s: PreviewSettings) -> String {
        var head: [String] = []
        if let baseURL { head.append(#"<base href="\#(escape(baseURL.absoluteString))">"#) }
        head.append("<title>\(escape(title))</title>")
        if let css = styleURL(s) { head.append(#"<link rel="stylesheet" href="\#(css.absoluteString)">"#) }
        if s.syntaxHighlighting {
            head.append(#"<link rel="stylesheet" href="\#(prismThemeURL(s).absoluteString)">"#)
            if s.lineNumbers {
                head.append(#"<link rel="stylesheet" href="\#(web.appendingPathComponent("prism/plugins/line-numbers/prism-line-numbers.min.css").absoluteString)">"#)
            }
        }
        head.append("<style>\(extraCSS)</style>")

        let config = """
        window.MacDownConfig = {
          diagrams: \(s.diagrams ? "'pele'" : "null"),
          peleLook: \(s.peleLook == "none" ? "null" : "'\(s.peleLook)'"),
          peleAnimate: \(["true", "false"].contains(s.peleAnimate) ? s.peleAnimate : "'\(s.peleAnimate)'"),
          darkStyle: \(s.isDarkStyle),
          pageLook: \(s.pageLook), icons: \(s.icons), diagramPadding: \(s.diagramPadding),
          math: \(s.math), lineNumbers: \(s.syntaxHighlighting && s.lineNumbers)
        };
        """
        head.append("<script>\(config)</script>")
        if s.syntaxHighlighting {
            head.append("<script>window.Prism = window.Prism || {}; window.Prism.manual = true;</script>")
            head.append(script("prism/components/prism-core.min.js"))
            head.append(script("prism/plugins/autoloader/prism-autoloader.min.js"))
            head.append("<script>Prism.plugins.autoloader.languages_path = '\(web.appendingPathComponent("prism/components").absoluteString)/';</script>")
            if s.lineNumbers { head.append(script("prism/plugins/line-numbers/prism-line-numbers.min.js")) }
        }
        if s.needsLookFonts { head.append(#"<link rel="stylesheet" href="\#(peleFontsURL)">"#) }
        if s.needsPele { head.append(script("pele/pele.global.js")) }
        if s.math {
            head.append("<script>\(mathJaxConfig(s))</script>")
            head.append(script("mathjax/tex-svg-full.js"))
        }
        head.append(script("macdown.js", defer: true))

        return document(head: head, body: body)
    }

    /// Standalone HTML for export: stylesheets inlined, no scripts. `body` should already be post-processed
    /// (highlighted code, rendered diagrams/math) — typically taken from the live preview's DOM.
    static func export(body: String, title: String, settings s: PreviewSettings, includeStyles: Bool = true, runtimeCSS: String = "") -> String {
        var head: [String] = ["<title>\(escape(title))</title>"]
        if includeStyles {
            var css = ""
            if let url = styleURL(s), let text = try? String(contentsOf: url, encoding: .utf8) { css += text + "\n" }
            if s.syntaxHighlighting, let text = try? String(contentsOf: prismThemeURL(s), encoding: .utf8) { css += text + "\n" }
            if s.syntaxHighlighting && s.lineNumbers,
               let text = try? String(contentsOf: web.appendingPathComponent("prism/plugins/line-numbers/prism-line-numbers.min.css"), encoding: .utf8) {
                css += text + "\n"
            }
            css += extraCSS + "\n" + runtimeCSS
            if s.needsLookFonts { head.append(#"<link rel="stylesheet" href="\#(peleFontsURL)">"#) }
            head.append("<style>\n\(css)\n</style>")
        }
        return document(head: head, body: body)
    }

    private static func script(_ path: String, defer: Bool = false) -> String {
        #"<script src="\#(web.appendingPathComponent(path).absoluteString)"\#(`defer` ? " defer" : "")></script>"#
    }

    private static func document(head: [String], body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \(head.joined(separator: "\n"))
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
