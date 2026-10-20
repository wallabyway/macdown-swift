import AppKit
import SwiftUI

struct MacDownCommands: Commands {
    @FocusedValue(\.documentBridge) private var bridge

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Print…") { bridge?.print() }
                .keyboardShortcut("p")
                .disabled(bridge == nil)
        }

        CommandGroup(after: .importExport) {
            Button("Export HTML…") { bridge?.exportHTML() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(bridge == nil)
            Button("Export PDF…") { bridge?.exportPDF() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(bridge == nil)
            Divider()
            Button("Copy HTML") { bridge?.copyHTML() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(bridge == nil)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            ForEach(Array(EditorLayout.allCases.enumerated()), id: \.element) { idx, layout in
                Button(layout.title) { bridge?.layout = layout }
                    .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [.command, .control])
                    .disabled(bridge == nil)
            }
            Divider()
            Button("Replay Diagram Animation") { bridge?.replayDiagrams() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(bridge == nil)
            Divider()
        }

        CommandMenu("Format") {
            Button("Bold") { send(#selector(MarkdownTextView.toggleStrong(_:))) }
                .keyboardShortcut("b")
            Button("Italic") { send(#selector(MarkdownTextView.toggleEmphasis(_:))) }
                .keyboardShortcut("i")
            Button("Strikethrough") { send(#selector(MarkdownTextView.toggleStrikethrough(_:))) }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            Button("Inline Code") { send(#selector(MarkdownTextView.toggleInlineCode(_:))) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Divider()
            Button("Link") { send(#selector(MarkdownTextView.insertLink(_:))) }
                .keyboardShortcut("k")
            Button("Image") { send(#selector(MarkdownTextView.insertImage(_:))) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Code Block") { send(#selector(MarkdownTextView.insertCodeBlock(_:))) }
                .keyboardShortcut("c", modifiers: [.command, .control])
            Button("Horizontal Rule") { send(#selector(MarkdownTextView.insertHorizontalRule(_:))) }
            Divider()
            Menu("Heading") {
                Button("Heading 1") { send(#selector(MarkdownTextView.heading1(_:))) }.keyboardShortcut("1")
                Button("Heading 2") { send(#selector(MarkdownTextView.heading2(_:))) }.keyboardShortcut("2")
                Button("Heading 3") { send(#selector(MarkdownTextView.heading3(_:))) }.keyboardShortcut("3")
                Button("Heading 4") { send(#selector(MarkdownTextView.heading4(_:))) }.keyboardShortcut("4")
                Button("Heading 5") { send(#selector(MarkdownTextView.heading5(_:))) }.keyboardShortcut("5")
                Button("Heading 6") { send(#selector(MarkdownTextView.heading6(_:))) }.keyboardShortcut("6")
                Divider()
                Button("Paragraph") { send(#selector(MarkdownTextView.headingNone(_:))) }.keyboardShortcut("0")
            }
            Button("Bulleted List") { send(#selector(MarkdownTextView.toggleUnorderedList(_:))) }
                .keyboardShortcut("u", modifiers: [.command, .control])
            Button("Numbered List") { send(#selector(MarkdownTextView.toggleOrderedList(_:))) }
                .keyboardShortcut("o", modifiers: [.command, .control])
            Button("Blockquote") { send(#selector(MarkdownTextView.toggleBlockquote(_:))) }
                .keyboardShortcut("'", modifiers: [.command])
            Divider()
            Button("Shift Right") { send(#selector(MarkdownTextView.shiftRight(_:))) }
                .keyboardShortcut("]")
            Button("Shift Left") { send(#selector(MarkdownTextView.shiftLeft(_:))) }
                .keyboardShortcut("[")
        }
    }
}
