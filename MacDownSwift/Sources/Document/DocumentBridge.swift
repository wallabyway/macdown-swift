import AppKit
import Observation
import UniformTypeIdentifiers
import WebKit

enum EditorLayout: String, CaseIterable, Identifiable {
    case editor, split, preview
    var id: String { rawValue }
    var title: String {
        switch self {
        case .editor: "Editor Only"
        case .split: "Editor and Preview"
        case .preview: "Preview Only"
        }
    }
    var symbol: String {
        switch self {
        case .editor: "doc.plaintext"
        case .split: "rectangle.split.2x1"
        case .preview: "doc.richtext"
        }
    }
}

/// Per-window glue between the editor, the preview and menu commands.
@Observable
final class DocumentBridge {
    var layout: EditorLayout = .split

    @ObservationIgnored weak var textView: MarkdownTextView?
    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored var fileURL: URL?
    @ObservationIgnored var text: () -> String = { "" }

    /// Set by the preview; called by the editor whenever it scrolls. Argument is a 1-based fractional line, or -1 for bottom.
    @ObservationIgnored var editorDidScroll: ((Double) -> Void)?
    /// Last known editor scroll line, so a freshly created preview can sync immediately.
    @ObservationIgnored var lastEditorLine: Double = 1

    var title: String { fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled" }

    // MARK: Export

    private static let sourcePosRegex = try! NSRegularExpression(pattern: #" data-(?:sourcepos|diagram-source)="[^"]*""#)

    private func stripInternalAttributes(_ html: String) -> String {
        Self.sourcePosRegex.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: (html as NSString).length), withTemplate: "")
    }

    /// Body HTML after preview post-processing (syntax highlighting, diagrams, math) if a preview is live.
    private func processedBody() async -> String {
        if let webView, let result = try? await webView.callAsyncJavaScript("return MacDown.bodyHTML()", contentWorld: .page) as? String {
            return stripInternalAttributes(result)
        }
        return MarkdownRenderer(options: .fromDefaults()).html(from: text(), sourcePositions: false)
    }

    private func runtimeCSS() async -> String {
        guard let webView else { return "" }
        return (try? await webView.callAsyncJavaScript("return MacDown.pageCSS()", contentWorld: .page) as? String) ?? ""
    }

    /// Restart Pele diagram animations: intro from the beginning, then loop.
    func replayDiagrams() {
        webView?.callAsyncJavaScript("return MacDown.replayDiagrams()", arguments: [:], in: nil, in: .page) { _ in }
    }

    func copyHTML() {
        let html = MarkdownRenderer(options: .fromDefaults()).html(from: text(), sourcePositions: false)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .string)
    }

    func exportHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = title + ".html"
        panel.canCreateDirectories = true
        let stylesBox = NSButton(checkboxWithTitle: "Include stylesheets", target: nil, action: nil)
        stylesBox.state = .on
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 36))
        stylesBox.frame.origin = NSPoint(x: 12, y: 8)
        accessory.addSubview(stylesBox)
        panel.accessoryView = accessory

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let includeStyles = stylesBox.state == .on
            Task { @MainActor in
                let body = await self.processedBody()
                let css = await self.runtimeCSS()
                let page = HTMLPage.export(body: body, title: self.title, settings: .fromDefaults(), includeStyles: includeStyles, runtimeCSS: css)
                do { try page.write(to: url, atomically: true, encoding: .utf8) }
                catch { NSAlert(error: error).runModal() }
            }
        }
        if let window = textView?.window ?? webView?.window { panel.beginSheetModal(for: window, completionHandler: handle) }
        else { handle(panel.runModal()) }
    }

    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = title + ".pdf"
        panel.canCreateDirectories = true
        guard let window = textView?.window ?? webView?.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                // Let the sheet finish closing before starting a print-modal session.
                try? await Task.sleep(for: .milliseconds(100))
                self.runPrint(saveTo: url)
            }
        }
    }

    func print() { runPrint(saveTo: nil) }

    private func runPrint(saveTo url: URL?) {
        Task { @MainActor in
            // Print from an offscreen web view so the live preview's layout and scroll are untouched,
            // and so printing works even when the preview is hidden.
            let body = await processedBody()
            let page = HTMLPage.export(body: body, title: title, settings: .fromDefaults(), runtimeCSS: await runtimeCSS())
            let printer = PrintRenderer()
            await printer.load(html: page, baseURL: fileURL?.deletingLastPathComponent())

            let info = (NSPrintInfo.shared.copy() as! NSPrintInfo)
            info.horizontalPagination = .fit
            info.verticalPagination = .automatic
            info.isVerticallyCentered = false
            info.isHorizontallyCentered = false
            info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
            if let url {
                info.jobDisposition = .save
                info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            }
            let op = printer.webView.printOperation(with: info)
            op.view?.frame = printer.webView.bounds
            op.showsPrintPanel = url == nil
            op.showsProgressPanel = true
            op.jobTitle = title
            if let window = textView?.window ?? webView?.window {
                op.runModal(for: window, delegate: printer,
                            didRun: #selector(PrintRenderer.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
            } else {
                op.run()
                printer.cleanup()
            }
        }
    }
}

/// Hosts an offscreen WKWebView for printing / PDF export.
@MainActor
final class PrintRenderer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var continuation: CheckedContinuation<Void, Never>?
    private var tempFile: URL?
    private static var live: Set<PrintRenderer> = []

    override init() {
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1000))
        super.init()
        webView.navigationDelegate = self
        Self.live.insert(self)
    }

    func load(html: String, baseURL: URL?) async {
        var html = html
        if let baseURL {
            html = html.replacingOccurrences(of: "<head>", with: "<head>\n<base href=\"\(baseURL.absoluteString)\">")
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("macdown-print-\(UUID().uuidString).html")
        try? html.write(to: file, atomically: true, encoding: .utf8)
        tempFile = file
        await withCheckedContinuation { c in
            continuation = c
            webView.loadFileURL(file, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(); continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(); continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(); continuation = nil
    }

    @objc func printOperationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        cleanup()
    }

    func cleanup() {
        if let tempFile { try? FileManager.default.removeItem(at: tempFile) }
        Self.live.remove(self)
    }
}
