import AppKit
import UniformTypeIdentifiers

/// Makes MacDown the default app for Markdown files (`.md`, `.markdown`, …).
enum FileAssociation {
    private static let didRegisterKey = "didRegisterAsMarkdownHandler"

    static var markdownType: UTType {
        UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md", conformingTo: .plainText)!
    }

    /// True when the app is running from a disk image or a translocated (quarantined) copy, where
    /// registering would point Launch Services at a path that disappears later.
    static var isRunningFromTemporaryLocation: Bool {
        let path = Bundle.main.bundleURL.path
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    static var isDefaultHandler: Bool {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: markdownType) else { return false }
        return url.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// Called at launch. Registers once; retries on later launches until it has run from a
    /// permanent location (e.g. after being dragged to /Applications).
    static func registerOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didRegisterKey), !isRunningFromTemporaryLocation else { return }
        Task {
            if await makeDefault() { defaults.set(true, forKey: didRegisterKey) }
        }
    }

    /// Sets MacDown as the default handler for Markdown files. Returns true on success.
    @discardableResult
    static func makeDefault() async -> Bool {
        let appURL = Bundle.main.bundleURL
        // Make sure Launch Services knows about this copy before asking it to become the default.
        LSRegisterURL(appURL as CFURL, true)
        var types: [UTType] = [markdownType]
        if let md = UTType(filenameExtension: "md"), !types.contains(md) { types.append(md) }
        var ok = true
        for type in types {
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
            } catch {
                NSLog("MacDown: could not become default for \(type.identifier): \(error)")
                ok = false
            }
        }
        return ok
    }
}
