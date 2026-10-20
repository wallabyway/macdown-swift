import AppKit
import SwiftUI
import WebKit

struct MarkdownPreview: NSViewRepresentable {
    let text: String
    let fileURL: URL?
    let bridge: DocumentBridge

    // Read so SwiftUI re-runs updateNSView when any of these change.
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
    @AppStorage(Pref.mdTables) private var tables = true
    @AppStorage(Pref.mdStrikethrough) private var strikethrough = true
    @AppStorage(Pref.mdAutolink) private var autolink = true
    @AppStorage(Pref.mdTaskLists) private var taskLists = true
    @AppStorage(Pref.mdFootnotes) private var footnotes = true
    @AppStorage(Pref.mdSmartPunctuation) private var smart = false
    @AppStorage(Pref.mdHardBreaks) private var hardBreaks = false
    @AppStorage(Pref.syncScrolling) private var syncScrolling = true

    private var settings: PreviewSettings {
        PreviewSettings(style: style, syntaxHighlighting: syntaxHighlighting, prismTheme: prismTheme,
                        lineNumbers: lineNumbers, math: math, inlineDollarMath: inlineDollar, diagrams: diagrams,
                        peleLook: peleLook, peleAnimate: peleAnimate,
                        peleWebFonts: peleWebFonts, icons: icons, diagramPadding: diagramPadding)
    }

    private var options: MarkdownRenderer.Options {
        .init(tables: tables, strikethrough: strikethrough, autolink: autolink, taskLists: taskLists,
              footnotes: footnotes, smartPunctuation: smart, hardBreaks: hardBreaks,
              math: math, inlineDollarMath: inlineDollar)
    }

    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        webView.isInspectable = true
        context.coordinator.webView = webView
        bridge.webView = webView
        bridge.editorDidScroll = { [weak coordinator = context.coordinator] line in coordinator?.scroll(to: line) }
        context.coordinator.update(text: text, settings: settings, options: options, baseURL: baseURL, sync: syncScrolling)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(text: text, settings: settings, options: options, baseURL: baseURL, sync: syncScrolling)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    private var baseURL: URL? { fileURL?.deletingLastPathComponent() }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        let bridge: DocumentBridge

        private let pageFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdown-preview-\(UUID().uuidString).html")
        private var loadedSettings: PreviewSettings?
        private var loadedBaseURL: URL??
        private var loadedOptions: MarkdownRenderer.Options?
        private var renderedText: String?
        private var renderedBody = ""
        private var isLoaded = false
        private var pendingBody: String?
        private var renderTask: Task<Void, Never>?
        private var sync = true

        init(bridge: DocumentBridge) { self.bridge = bridge }

        func update(text: String, settings: PreviewSettings, options: MarkdownRenderer.Options, baseURL: URL?, sync: Bool) {
            let syncChanged = sync != self.sync
            self.sync = sync
            if syncChanged {
                if sync { scroll(to: bridge.lastEditorLine) }
                else { webView?.evaluateJavaScript("MacDown.disableSync()") }
            }

            let shellChanged = settings != loadedSettings || loadedBaseURL != .some(baseURL)
            let optionsChanged = options != loadedOptions
            if shellChanged || optionsChanged || renderedText == nil {
                renderTask?.cancel()
                loadedOptions = options
                renderedText = text
                renderedBody = MarkdownRenderer(options: options).html(from: text)
                if shellChanged {
                    loadShell(settings: settings, baseURL: baseURL)
                } else {
                    push(renderedBody)
                }
                return
            }
            guard text != renderedText else { return }
            renderedText = text
            // Debounce rapid typing; rendering is fast but DOM replacement + highlighting is not free.
            renderTask?.cancel()
            renderTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(text.utf16.count > 50_000 ? 150 : 40))
                guard let self, !Task.isCancelled, let current = self.renderedText else { return }
                self.renderedBody = MarkdownRenderer(options: options).html(from: current)
                self.push(self.renderedBody)
            }
        }

        private func loadShell(settings: PreviewSettings, baseURL: URL?) {
            loadedSettings = settings
            loadedBaseURL = .some(baseURL)
            isLoaded = false
            pendingBody = nil
            let page = HTMLPage.preview(body: renderedBody, title: bridge.title, baseURL: baseURL, settings: settings)
            do {
                try page.write(to: pageFile, atomically: true, encoding: .utf8)
                webView?.loadFileURL(pageFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
            } catch {
                webView?.loadHTMLString(page, baseURL: baseURL)
            }
        }

        private func push(_ body: String) {
            guard isLoaded, let webView else { pendingBody = body; return }
            webView.callAsyncJavaScript("MacDown.update(html)", arguments: ["html": body], in: nil, in: .page) { _ in }
        }

        func scroll(to line: Double) {
            guard sync, isLoaded, let webView else { return }
            webView.callAsyncJavaScript("MacDown.scrollToLine(line)", arguments: ["line": line], in: nil, in: .page) { _ in }
        }

        func teardown() {
            renderTask?.cancel()
            try? FileManager.default.removeItem(at: pageFile)
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            if let body = pendingBody { pendingBody = nil; push(body) }
            if sync { scroll(to: bridge.lastEditorLine) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.allow) }
            // Initial page load (and our own reloads).
            if action.navigationType != .linkActivated {
                decisionHandler(url.standardizedFileURL == pageFile.standardizedFileURL || url.scheme == "about" ? .allow : .cancel)
                return
            }
            decisionHandler(.cancel)

            // In-page anchors (e.g. footnotes). With <base> set, "#x" resolves against the document directory.
            if let fragment = url.fragment, !fragment.isEmpty {
                var noFragment = URLComponents(url: url, resolvingAgainstBaseURL: false)
                noFragment?.fragment = nil
                let target = noFragment?.url?.standardizedFileURL
                let base = (loadedBaseURL ?? nil)?.standardizedFileURL
                if target == pageFile.standardizedFileURL || (base != nil && target?.path == base?.path) {
                    webView.callAsyncJavaScript(
                        "var el = document.getElementById(id) || document.getElementsByName(id)[0]; if (el) el.scrollIntoView({behavior: 'smooth'});",
                        arguments: ["id": fragment.removingPercentEncoding ?? fragment], in: nil, in: .page) { _ in }
                    return
                }
            }
            if url.isFileURL, ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "text", "txt"].contains(url.pathExtension.lowercased()) {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
