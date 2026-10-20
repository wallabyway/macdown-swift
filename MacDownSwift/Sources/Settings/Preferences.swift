import Foundation

/// Centralised user-defaults keys and defaults. Views read these via `@AppStorage`.
nonisolated enum Pref {
    // Editor
    static let editorFontFamily = "editorFontFamily"
    static let editorFontSize = "editorFontSize"
    static let editorTheme = "editorTheme"
    static let editorLineSpacing = "editorLineSpacing"
    static let editorInsertSpacesForTab = "editorInsertSpacesForTab"
    static let editorTabWidth = "editorTabWidth"
    static let editorAutoPair = "editorAutoPair"
    static let editorContinueLists = "editorContinueLists"
    static let editorSpellCheck = "editorSpellCheck"
    static let editorWidthLimit = "editorWidthLimit"
    static let editorHorizontalInset = "editorHorizontalInset"

    // Markdown
    static let mdTables = "mdTables"
    static let mdStrikethrough = "mdStrikethrough"
    static let mdAutolink = "mdAutolink"
    static let mdTaskLists = "mdTaskLists"
    static let mdFootnotes = "mdFootnotes"
    static let mdSmartPunctuation = "mdSmartPunctuation"
    static let mdHardBreaks = "mdHardBreaks"

    // Rendering
    static let htmlStyle = "htmlStyle"
    static let htmlSyntaxHighlighting = "htmlSyntaxHighlighting"
    static let htmlPrismTheme = "htmlPrismTheme"
    static let htmlLineNumbers = "htmlLineNumbers"
    static let htmlMath = "htmlMath"
    static let htmlMathInlineDollar = "htmlMathInlineDollar"
    static let htmlDiagrams = "htmlDiagrams"        // ```mermaid blocks drawn by Pele
    static let peleLook = "peleLook"                // "none" | one of pele.LOOKS
    static let peleAnimate = "peleAnimate"          // "false" | "intro" | "loop" | "true"
    static let peleWebFonts = "peleWebFonts"
    static let diagramPadding = "diagramPadding"      // px inside a Pele diagram's card
    static let htmlIcons = "htmlIcons"              // :name: Lucide shortcodes

    // General
    static let syncScrolling = "syncScrolling"
    static let previewOnRight = "previewOnRight"
    static let showWordCount = "showWordCount"

    nonisolated(unsafe) static let defaults: [String: Any] = [
        editorFontFamily: "Menlo",
        editorFontSize: 14.0,
        editorTheme: "Tomorrow+",
        editorLineSpacing: 2.0,
        editorInsertSpacesForTab: true,
        editorTabWidth: 4,
        editorAutoPair: true,
        editorContinueLists: true,
        editorSpellCheck: false,
        editorWidthLimit: 0.0,
        editorHorizontalInset: 16.0,

        mdTables: true,
        mdStrikethrough: true,
        mdAutolink: true,
        mdTaskLists: true,
        mdFootnotes: true,
        mdSmartPunctuation: false,
        mdHardBreaks: false,

        htmlStyle: "Pele",
        htmlSyntaxHighlighting: true,
        htmlPrismTheme: "prism",
        htmlLineNumbers: false,
        htmlMath: false,
        htmlMathInlineDollar: true,
        htmlDiagrams: true,
        peleLook: "white",
        peleAnimate: "true",
        peleWebFonts: true,
        htmlIcons: true,
        diagramPadding: 28,

        syncScrolling: true,
        previewOnRight: true,
        showWordCount: true,
    ]

    /// Whether the preview stylesheet is the look-following "Pele" sheet.
    static var isPageLookStyle: Bool { UserDefaults.standard.string(forKey: htmlStyle) == "Pele" }

    static func register() {
        UserDefaults.standard.register(defaults: defaults)
    }
}

/// Locations of bundled and user-installed themes / styles.
enum ResourceLocator {
    /// ~/Library/Application Support/MacDown/<subdir>, created on demand.
    static func userDirectory(_ subdir: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = base.appendingPathComponent("MacDown", isDirectory: true).appendingPathComponent(subdir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Names (without extension) of all files with `ext` in the bundled + user `subdir`.
    static func names(in subdir: String, ext: String) -> [String] {
        var names = Set<String>()
        for dir in [Bundle.main.resourceURL?.appendingPathComponent(subdir), userDirectory(subdir)].compactMap({ $0 }) {
            let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for item in items where item.pathExtension == ext {
                names.insert(item.deletingPathExtension().lastPathComponent)
            }
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Resolve a named resource; user directory wins over the bundle.
    static func url(named name: String, in subdir: String, ext: String) -> URL? {
        if let user = userDirectory(subdir)?.appendingPathComponent(name).appendingPathExtension(ext),
           FileManager.default.fileExists(atPath: user.path) {
            return user
        }
        let bundled = Bundle.main.resourceURL?.appendingPathComponent(subdir).appendingPathComponent(name).appendingPathExtension(ext)
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return nil
    }

    static var webDirectory: URL { Bundle.main.resourceURL!.appendingPathComponent("Web", isDirectory: true) }

    /// Looks shipped with the bundled Pele build (see `pele.LOOKS`).
    static let peleLooks = ["white", "paper", "elevated", "neon", "blueprint", "midnight", "editorial", "terminal", "pastel"]

    static var prismThemes: [String] {
        let dir = webDirectory.appendingPathComponent("prism/themes")
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return items.filter { $0.hasSuffix(".min.css") }.map { String($0.dropLast(8)) }.sorted()
    }
}
