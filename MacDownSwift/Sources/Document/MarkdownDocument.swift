import SwiftUI
import UniformTypeIdentifiers

nonisolated extension UTType {
    static let markdownDocument = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

nonisolated struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdownDocument, .plainText]
    static let writableContentTypes: [UTType] = [.markdownDocument, .plainText]

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let s = String(data: data, encoding: .utf8) {
            text = s
        } else {
            // Fall back to encoding detection for legacy files.
            var converted: NSString?
            let enc = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil)
            guard enc != 0, let converted else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            text = converted as String
        }
        // Drop a UTF-8 BOM if present.
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
