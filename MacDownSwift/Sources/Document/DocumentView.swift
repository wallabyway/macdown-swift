import SwiftUI

struct DocumentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @State private var bridge = DocumentBridge()
    @AppStorage(Pref.previewOnRight) private var previewOnRight = true
    @AppStorage(Pref.showWordCount) private var showWordCount = true
    @AppStorage(Pref.peleLook) private var peleLook = "white"
    @AppStorage(Pref.htmlDiagrams) private var diagramsOn = true

    private var peleActive: Bool { diagramsOn }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                if previewOnRight {
                    editorPane
                    previewPane
                } else {
                    previewPane
                    editorPane
                }
            }
            if showWordCount {
                Divider()
                StatusBar(text: document.text)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Look", selection: $peleLook) {
                    Text("Plain").tag("none")
                    Divider()
                    ForEach(ResourceLocator.peleLooks, id: \.self) { look in
                        Text(look.capitalized).tag(look)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .help("Diagram and page look")
                .disabled(!peleActive && Pref.isPageLookStyle == false)

                Button {
                    bridge.replayDiagrams()
                } label: {
                    Label("Replay", systemImage: "repeat")
                }
                .help("Replay diagram animation (intro, then loop)")
                .disabled(!peleActive || peleLook == "none" || bridge.layout == .editor)
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("Layout", selection: $bridge.layout) {
                    ForEach(EditorLayout.allCases) { layout in
                        Label(layout.title, systemImage: layout.symbol).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("Editor / Preview layout")
            }
        }
        .focusedSceneValue(\.documentBridge, bridge)
        .onAppear {
            syncBridge()
            #if DEBUG
            DebugSnapshot.scheduleIfRequested(bridge: bridge)
            #endif
        }
        .onChange(of: fileURL) { syncBridge() }
    }

    private func syncBridge() {
        bridge.fileURL = fileURL
        bridge.text = { [binding = $document] in binding.wrappedValue.text }
    }

    @ViewBuilder private var editorPane: some View {
        if bridge.layout != .preview {
            MarkdownEditor(text: $document.text, bridge: bridge)
                .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var previewPane: some View {
        if bridge.layout != .editor {
            MarkdownPreview(text: document.text, fileURL: fileURL, bridge: bridge)
                .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct StatusBar: View {
    let text: String

    var body: some View {
        let stats = Self.stats(text)
        HStack(spacing: 16) {
            Text("\(stats.words) words")
            Text("\(stats.characters) characters")
            Text("\(stats.lines) lines")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }

    static func stats(_ text: String) -> (words: Int, characters: Int, lines: Int) {
        var words = 0, inWord = false, lines = text.isEmpty ? 0 : 1
        for scalar in text.unicodeScalars {
            if scalar == "\n" { lines += 1 }
            let isSpace = CharacterSet.whitespacesAndNewlines.contains(scalar)
            if !isSpace && !inWord { words += 1 }
            inWord = !isSpace
        }
        return (words, text.count, lines)
    }
}

extension FocusedValues {
    @Entry var documentBridge: DocumentBridge?
}
