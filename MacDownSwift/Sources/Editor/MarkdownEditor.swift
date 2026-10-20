import AppKit
import SwiftUI

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let bridge: DocumentBridge

    @AppStorage(Pref.editorFontFamily) private var fontFamily = "Menlo"
    @AppStorage(Pref.editorFontSize) private var fontSize = 14.0
    @AppStorage(Pref.editorTheme) private var themeName = "Tomorrow+"
    @AppStorage(Pref.editorLineSpacing) private var lineSpacing = 2.0
    @AppStorage(Pref.editorInsertSpacesForTab) private var spacesForTab = true
    @AppStorage(Pref.editorTabWidth) private var tabWidth = 4
    @AppStorage(Pref.editorAutoPair) private var autoPair = true
    @AppStorage(Pref.editorContinueLists) private var continueLists = true
    @AppStorage(Pref.editorSpellCheck) private var spellCheck = false
    @AppStorage(Pref.editorWidthLimit) private var widthLimit = 0.0
    @AppStorage(Pref.editorHorizontalInset) private var horizontalInset = 16.0

    struct Appearance: Equatable {
        var fontFamily: String
        var fontSize: Double
        var theme: String
        var lineSpacing: Double
    }

    private var appearance: Appearance {
        Appearance(fontFamily: fontFamily, fontSize: fontSize, theme: themeName, lineSpacing: lineSpacing)
    }

    static func resolveFont(family: String, size: Double) -> NSFont {
        NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
            ?? NSFont(name: family, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true

        let tv = MarkdownTextView(usingTextLayoutManager: false)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.lineFragmentPadding = 0

        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.allowsDocumentBackgroundColorChange = false
        tv.delegate = context.coordinator

        scroll.documentView = tv
        context.coordinator.attach(tv, scroll: scroll)

        tv.string = text
        context.coordinator.apply(appearance, force: true)
        applyBehaviour(tv)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
            tv.scroll(.zero)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView else { return }
        applyBehaviour(tv)
        c.apply(appearance, force: false)
        if tv.string != text {
            // External change (revert, reload from disk…).
            let sel = tv.selectedRange()
            tv.string = text
            c.rehighlight()
            let len = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    private func applyBehaviour(_ tv: MarkdownTextView) {
        tv.autoPair = autoPair
        tv.continueLists = continueLists
        tv.insertSpacesForTab = spacesForTab
        tv.tabWidth = tabWidth
        tv.widthLimit = widthLimit
        tv.horizontalInset = horizontalInset
        if tv.isContinuousSpellCheckingEnabled != spellCheck { tv.isContinuousSpellCheckingEnabled = spellCheck }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: MarkdownTextView?
        weak var scrollView: NSScrollView?
        private var highlighter: MarkdownHighlighter?
        private var lastAppearance: Appearance?
        private var lineStarts: [Int]?
        private var scrollObserver: NSObjectProtocol?

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func attach(_ tv: MarkdownTextView, scroll: NSScrollView) {
            textView = tv
            scrollView = scroll
            parent.bridge.textView = tv
            scroll.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportScroll() }
            }
        }

        func detach() {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }

        func apply(_ a: Appearance, force: Bool) {
            guard force || a != lastAppearance, let tv = textView else { return }
            lastAppearance = a
            let theme = EditorTheme.named(a.theme)
            let font = MarkdownEditor.resolveFont(family: a.fontFamily, size: a.fontSize)
            if let h = highlighter {
                h.theme = theme; h.font = font; h.lineSpacing = a.lineSpacing
            } else {
                highlighter = MarkdownHighlighter(theme: theme, font: font, lineSpacing: a.lineSpacing)
            }
            tv.backgroundColor = theme.background
            scrollView?.backgroundColor = theme.background
            tv.insertionPointColor = theme.caret
            var sel: [NSAttributedString.Key: Any] = [.backgroundColor: theme.selectionBackground]
            if let fg = theme.selectionForeground { sel[.foregroundColor] = fg }
            tv.selectedTextAttributes = sel
            scrollView?.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
            rehighlight()
        }

        func rehighlight() {
            guard let tv = textView, let storage = tv.textStorage, let h = highlighter else { return }
            h.highlight(storage)
            tv.typingAttributes = h.baseAttributes
            lineStarts = nil
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            rehighlight()
            parent.text = tv.string
        }

        // MARK: Scroll sync

        private func lineNumber(forCharacterAt index: Int, in string: NSString) -> Int {
            if lineStarts == nil {
                var starts = [0]
                let len = string.length
                var i = 0
                while i < len {
                    let r = string.lineRange(for: NSRange(location: i, length: 0))
                    i = NSMaxRange(r)
                    if i < len || (i == len && len > 0 && string.character(at: len - 1) == 0x0A) { starts.append(i) }
                    if r.length == 0 { break }
                }
                lineStarts = starts
            }
            // Binary search for last start <= index.
            var lo = 0, hi = lineStarts!.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if lineStarts![mid] <= index { lo = mid } else { hi = mid - 1 }
            }
            return lo + 1
        }

        func reportScroll() {
            guard let line = currentTopLine() else { return }
            parent.bridge.lastEditorLine = line
            parent.bridge.editorDidScroll?(line)
        }

        func currentTopLine() -> Double? {
            guard let tv = textView, let scroll = scrollView, let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
            let visible = scroll.contentView.bounds
            if visible.minY <= 1 { return 1 }
            if visible.maxY >= tv.frame.height - 1 { return -1 }
            let ns = tv.string as NSString
            guard ns.length > 0 else { return 1 }
            let y = visible.minY - tv.textContainerOrigin.y
            let glyph = lm.glyphIndex(for: NSPoint(x: 0, y: max(0, y)), in: tc)
            let charIndex = min(lm.characterIndexForGlyph(at: glyph), ns.length - 1)
            let lineRange = ns.lineRange(for: NSRange(location: charIndex, length: 0))
            let line = lineNumber(forCharacterAt: lineRange.location, in: ns)
            let glyphRange = lm.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            let frac = rect.height > 0 ? min(1, max(0, (y - rect.minY) / rect.height)) : 0
            return Double(line) + frac
        }
    }
}
