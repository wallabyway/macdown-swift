#if DEBUG
import AppKit
import WebKit

/// Debug-only: when MACDOWN_SNAPSHOT_DIR is set, writes window/preview PNGs (and optional JS probe results)
/// a few seconds after launch. Used to verify rendering and to make the README screenshots without
/// screen-recording permission. Environment:
///   MACDOWN_SNAPSHOT_DIR, MACDOWN_SNAPSHOT_DELAY (s), MACDOWN_SNAPSHOT_LAYOUT (editor|split|preview),
///   MACDOWN_SNAPSHOT_EDITOR_SCROLL (pt), MACDOWN_SNAPSHOT_TYPE (text to type), MACDOWN_SNAPSHOT_PRE_JS,
///   MACDOWN_SNAPSHOT_JS, MACDOWN_SNAPSHOT_ASYNC_JS (body of an async function; its return value is saved).
enum DebugSnapshot {
    static func scheduleIfRequested(bridge: DocumentBridge) {
        guard let dir = ProcessInfo.processInfo.environment["MACDOWN_SNAPSHOT_DIR"] else { return }
        let delay = Double(ProcessInfo.processInfo.environment["MACDOWN_SNAPSHOT_DELAY"] ?? "") ?? 4
        Task { @MainActor in
            if let layout = ProcessInfo.processInfo.environment["MACDOWN_SNAPSHOT_LAYOUT"].flatMap(EditorLayout.init(rawValue:)) {
                bridge.layout = layout
            }
            try? await Task.sleep(for: .seconds(delay))
            if let script = ProcessInfo.processInfo.environment["MACDOWN_SNAPSHOT_EDITOR_SCROLL"],
               let y = Double(script), let tv = bridge.textView {
                tv.enclosingScrollView?.contentView.scroll(to: NSPoint(x: 0, y: y))
                tv.enclosingScrollView?.reflectScrolledClipView(tv.enclosingScrollView!.contentView)
                try? await Task.sleep(for: .seconds(1))
            }
            if let typed = ProcessInfo.processInfo.environment["MACDOWN_SNAPSHOT_TYPE"], let tv = bridge.textView {
                _ = try? await bridge.webView?.evaluateJavaScript("window.__probe = document.querySelector('.pele-diagram'); window.__probePos = window.__probe && window.__probe.getAttribute('data-sourcepos'); 1")
                tv.setSelectedRange(NSRange(location: 0, length: 0))
                tv.insertText(typed.replacingOccurrences(of: "\\n", with: "\n"), replacementRange: NSRange(location: 0, length: 0))
                try? await Task.sleep(for: .seconds(1))
            }
            if let pre = ProcessInfo.processInfo.environment["MACDOWN_SNAPSHOT_PRE_JS"] {
                _ = try? await bridge.webView?.evaluateJavaScript(pre)
                try? await Task.sleep(for: .milliseconds(500))
            }
            let base = URL(fileURLWithPath: dir)
            if let view = bridge.textView?.window?.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: base.appendingPathComponent("window.png"))
            }
            // Whole window: the frame view (title bar, toolbar, editor) with the web view drawn into place,
            // since WKWebView content isn't captured by cacheDisplay.
            if let window = bridge.textView?.window, let frameView = window.contentView?.superview,
               let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
                frameView.cacheDisplay(in: frameView.bounds, to: rep)
                if let webView = bridge.webView, let shot = try? await webView.takeSnapshot(configuration: nil) {
                    let rect = webView.convert(webView.bounds, to: frameView)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                    let flipped = frameView.isFlipped ? NSRect(x: rect.minX, y: frameView.bounds.height - rect.maxY, width: rect.width, height: rect.height) : rect
                    shot.draw(in: flipped)
                    NSGraphicsContext.restoreGraphicsState()
                }
                try? rep.representation(using: .png, properties: [:])?.write(to: base.appendingPathComponent("window-full.png"))
            }
            if let webView = bridge.webView {
                webView.takeSnapshot(with: nil) { image, _ in
                    guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
                    try? rep.representation(using: .png, properties: [:])?.write(to: base.appendingPathComponent("preview.png"))
                }
                if let html = try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String {
                    try? html.write(to: base.appendingPathComponent("preview.html"), atomically: true, encoding: .utf8)
                }
                if let body = ProcessInfo.processInfo.environment["MACDOWN_SNAPSHOT_ASYNC_JS"] {
                    let out: String
                    do { out = "\(try await webView.callAsyncJavaScript(body, contentWorld: .page) ?? "nil")" } catch { out = "error: \(error)" }
                    try? out.write(to: base.appendingPathComponent("async.txt"), atomically: true, encoding: .utf8)
                }
                if let js = ProcessInfo.processInfo.environment["MACDOWN_SNAPSHOT_JS"] {
                    let out: String
                    do { out = "\(try await webView.evaluateJavaScript(js) ?? "nil")" } catch { out = "error: \(error)" }
                    try? out.write(to: base.appendingPathComponent("js.txt"), atomically: true, encoding: .utf8)
                }
                if let y = try? await webView.evaluateJavaScript("window.scrollY") {
                    try? "\(y)".write(to: base.appendingPathComponent("preview-scrolly.txt"), atomically: true, encoding: .utf8)
                }
            }
        }
    }
}
#endif
