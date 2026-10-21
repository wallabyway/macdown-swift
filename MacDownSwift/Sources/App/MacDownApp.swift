import SwiftUI

@main
struct MacDownApp: App {
    init() {
        Pref.register()
        DispatchQueue.main.async { FileAssociation.registerOnFirstLaunch() }
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentView(document: file.$document, fileURL: file.fileURL)
        }
        // 100pt wider and 200pt taller than the size SwiftUI picked on its own (900×450).
        .defaultSize(width: 1000, height: 650)
        .commands { MacDownCommands() }

        Settings {
            SettingsView()
        }
    }
}
