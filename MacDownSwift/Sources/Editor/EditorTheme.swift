import AppKit

/// A MacDown/Mou editor theme (`.style` file). Sections are element names followed by `key: value` lines.
struct EditorTheme {
    struct Style {
        var foreground: NSColor?
        var background: NSColor?
        var bold = false
        var italic = false
        var fontSize: CGFloat?
    }

    var foreground: NSColor = .textColor
    var background: NSColor = .textBackgroundColor
    var caret: NSColor = .textColor
    var selectionForeground: NSColor?
    var selectionBackground: NSColor = .selectedTextBackgroundColor
    var styles: [String: Style] = [:]

    static let fallback = EditorTheme()

    static func named(_ name: String) -> EditorTheme {
        guard let url = ResourceLocator.url(named: name, in: "Themes", ext: "style"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return .fallback }
        return EditorTheme(parsing: text)
    }

    init() {}

    init(parsing text: String) {
        var current: String?
        var sections: [String: [String: String]] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if let colon = line.firstIndex(of: ":") {
                guard let section = current else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                sections[section, default: [:]][key] = value
            } else {
                current = line
            }
        }

        if let editor = sections.removeValue(forKey: "editor") {
            if let c = editor["foreground"].flatMap(NSColor.init(hex:)) { foreground = c }
            if let c = editor["background"].flatMap(NSColor.init(hex:)) { background = c }
            caret = editor["caret"].flatMap(NSColor.init(hex:)) ?? foreground
        }
        if let sel = sections.removeValue(forKey: "editor-selection") {
            selectionForeground = sel["foreground"].flatMap(NSColor.init(hex:))
            if let c = sel["background"].flatMap(NSColor.init(hex:)) { selectionBackground = c }
        }
        for (name, attrs) in sections {
            var s = Style()
            s.foreground = attrs["foreground"].flatMap(NSColor.init(hex:))
            s.background = attrs["background"].flatMap(NSColor.init(hex:))
            let fs = (attrs["font-style"] ?? "").lowercased()
            s.bold = fs.contains("bold")
            s.italic = fs.contains("italic")
            if let size = attrs["font-size"], let v = Double(size.replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespaces)) {
                s.fontSize = CGFloat(v)
            }
            styles[name.uppercased()] = s
        }
    }

    var isDark: Bool {
        guard let c = background.usingColorSpace(.sRGB) else { return false }
        return (0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent) < 0.5
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r = CGFloat((v >> (hasAlpha ? 24 : 16)) & 0xff) / 255
        let g = CGFloat((v >> (hasAlpha ? 16 : 8)) & 0xff) / 255
        let b = CGFloat((v >> (hasAlpha ? 8 : 0)) & 0xff) / 255
        let a = hasAlpha ? CGFloat(v & 0xff) / 255 : 1
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
