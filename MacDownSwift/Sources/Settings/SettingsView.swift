import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            EditorSettings().tabItem { Label("Editor", systemImage: "character.cursor.ibeam") }
            MarkdownSettings().tabItem { Label("Markdown", systemImage: "number") }
            RenderingSettings().tabItem { Label("Rendering", systemImage: "doc.richtext") }
        }
        .frame(width: 520)
        .scenePadding()
    }
}

private struct GeneralSettings: View {
    @AppStorage(Pref.syncScrolling) private var syncScrolling = true
    @AppStorage(Pref.previewOnRight) private var previewOnRight = true
    @AppStorage(Pref.showWordCount) private var showWordCount = true
    @State private var isDefault = FileAssociation.isDefaultHandler

    var body: some View {
        Form {
            LabeledContent("Markdown files") {
                if isDefault {
                    Text("MacDown is the default app").foregroundStyle(.secondary)
                } else {
                    Button("Make MacDown the Default") {
                        Task {
                            await FileAssociation.makeDefault()
                            isDefault = FileAssociation.isDefaultHandler
                        }
                    }
                }
            }
            Toggle("Synchronize preview scrolling with editor", isOn: $syncScrolling)
            Picker("Preview position", selection: $previewOnRight) {
                Text("Right of editor").tag(true)
                Text("Left of editor").tag(false)
            }
            Toggle("Show word count", isOn: $showWordCount)
        }
        .formStyle(.grouped)
    }
}

private struct EditorSettings: View {
    @AppStorage(Pref.editorFontFamily) private var fontFamily = "Menlo"
    @AppStorage(Pref.editorFontSize) private var fontSize = 14.0
    @AppStorage(Pref.editorTheme) private var theme = "Tomorrow+"
    @AppStorage(Pref.editorLineSpacing) private var lineSpacing = 2.0
    @AppStorage(Pref.editorInsertSpacesForTab) private var spacesForTab = true
    @AppStorage(Pref.editorTabWidth) private var tabWidth = 4
    @AppStorage(Pref.editorAutoPair) private var autoPair = true
    @AppStorage(Pref.editorContinueLists) private var continueLists = true
    @AppStorage(Pref.editorSpellCheck) private var spellCheck = false
    @AppStorage(Pref.editorWidthLimit) private var widthLimit = 0.0
    @AppStorage(Pref.editorHorizontalInset) private var horizontalInset = 16.0

    private let families = NSFontManager.shared.availableFontFamilies
    private let themes = ResourceLocator.names(in: "Themes", ext: "style")

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(themes, id: \.self) { Text($0).tag($0) }
                }
                Picker("Font", selection: $fontFamily) {
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                Stepper(value: $fontSize, in: 8...48, step: 1) {
                    LabeledContent("Font size", value: "\(Int(fontSize)) pt")
                }
                Stepper(value: $lineSpacing, in: 0...20, step: 1) {
                    LabeledContent("Line spacing", value: "\(Int(lineSpacing)) pt")
                }
                Stepper(value: $horizontalInset, in: 0...200, step: 4) {
                    LabeledContent("Horizontal padding", value: "\(Int(horizontalInset)) pt")
                }
                Stepper(value: $widthLimit, in: 0...2000, step: 40) {
                    LabeledContent("Maximum text width", value: widthLimit == 0 ? "Unlimited" : "\(Int(widthLimit)) pt")
                }
                Button("Reveal Themes Folder") { reveal("Themes") }
            }
            Section("Behaviour") {
                Toggle("Auto-pair brackets and quotes", isOn: $autoPair)
                Toggle("Continue lists and blockquotes on Return", isOn: $continueLists)
                Toggle("Insert spaces for Tab", isOn: $spacesForTab)
                Stepper(value: $tabWidth, in: 1...8) {
                    LabeledContent("Tab width", value: "\(tabWidth)")
                }
                Toggle("Check spelling while typing", isOn: $spellCheck)
            }
        }
        .formStyle(.grouped)
    }
}

private struct MarkdownSettings: View {
    @AppStorage(Pref.mdTables) private var tables = true
    @AppStorage(Pref.mdStrikethrough) private var strikethrough = true
    @AppStorage(Pref.mdAutolink) private var autolink = true
    @AppStorage(Pref.mdTaskLists) private var taskLists = true
    @AppStorage(Pref.mdFootnotes) private var footnotes = true
    @AppStorage(Pref.mdSmartPunctuation) private var smart = false
    @AppStorage(Pref.mdHardBreaks) private var hardBreaks = false

    var body: some View {
        Form {
            Section("GitHub Flavored Markdown") {
                Toggle("Tables", isOn: $tables)
                Toggle("Strikethrough (~~text~~)", isOn: $strikethrough)
                Toggle("Autolink URLs", isOn: $autolink)
                Toggle("Task lists (- [ ] item)", isOn: $taskLists)
                Toggle("Footnotes", isOn: $footnotes)
            }
            Section("Typography") {
                Toggle("Smart punctuation (quotes, dashes, ellipses)", isOn: $smart)
                Toggle("Treat newlines as hard line breaks", isOn: $hardBreaks)
            }
        }
        .formStyle(.grouped)
    }
}

private struct RenderingSettings: View {
    @AppStorage(Pref.htmlStyle) private var style = "Pele"
    @AppStorage(Pref.htmlSyntaxHighlighting) private var syntaxHighlighting = true
    @AppStorage(Pref.htmlPrismTheme) private var prismTheme = "prism"
    @AppStorage(Pref.htmlLineNumbers) private var lineNumbers = false
    @AppStorage(Pref.htmlMath) private var math = false
    @AppStorage(Pref.htmlMathInlineDollar) private var inlineDollar = true
    @AppStorage(Pref.htmlDiagrams) private var diagrams = true
    @AppStorage(Pref.peleLook) private var peleLook = "white"
    @AppStorage(Pref.peleAnimate) private var peleAnimate = "true"
    @AppStorage(Pref.peleWebFonts) private var peleWebFonts = true
    @AppStorage(Pref.htmlIcons) private var icons = true
    @AppStorage(Pref.diagramPadding) private var diagramPadding = 28

    private let styles = ResourceLocator.names(in: "Styles", ext: "css")
    private let prismThemes = ResourceLocator.prismThemes

    var body: some View {
        Form {
            Section("Preview") {
                Picker("CSS", selection: $style) {
                    ForEach(styles, id: \.self) { Text($0).tag($0) }
                }
                Text("“Pele” makes the page wear the diagram look (colours, fonts, shadows).")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reveal Styles Folder") { reveal("Styles") }
            }
            Section("Code") {
                Toggle("Syntax highlighting in code blocks", isOn: $syntaxHighlighting)
                Picker("Highlighting theme", selection: $prismTheme) {
                    ForEach(prismThemes, id: \.self) { Text($0.replacingOccurrences(of: "prism-", with: "").capitalized).tag($0) }
                }
                .disabled(!syntaxHighlighting)
                Toggle("Show line numbers", isOn: $lineNumbers)
                    .disabled(!syntaxHighlighting)
            }
            Section("Extensions") {
                Toggle("TeX math (MathJax)", isOn: $math)
                Toggle("Use $…$ for inline math", isOn: $inlineDollar)
                    .disabled(!math)
                Toggle("Lucide icon shortcodes (:check:, :database:, :rocket:…)", isOn: $icons)
            }
            Section("Diagrams") {
                Toggle("Draw ```mermaid blocks as diagrams (Pele)", isOn: $diagrams)
                Group {
                    Picker("Look", selection: $peleLook) {
                        Text("Plain").tag("none")
                        Divider()
                        ForEach(ResourceLocator.peleLooks, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Picker("Motion", selection: $peleAnimate) {
                        Text("Still").tag("false")
                        Text("Intro").tag("intro")
                        Text("Loop").tag("loop")
                        Text("Intro + loop").tag("true")
                    }
                    .disabled(peleLook == "none")
                    Stepper(value: $diagramPadding, in: 0...96, step: 4) {
                        LabeledContent("Padding inside diagrams", value: "\(diagramPadding) px")
                    }
                    Toggle("Load look web fonts (needs network)", isOn: $peleWebFonts)
                }
                .disabled(!diagrams)
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor private func reveal(_ subdir: String) {
    guard let url = ResourceLocator.userDirectory(subdir) else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
}
