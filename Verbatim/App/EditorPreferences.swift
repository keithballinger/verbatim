import AppKit

enum EditorPreferences {
    static func font(defaults: UserDefaults = .standard) -> NSFont {
        let stored = defaults.double(forKey: "editorFontSize")
        let size = stored.isFinite && (8...96).contains(stored) ? stored : 14
        if let name = defaults.string(forKey: "editorFontName"), let font = NSFont(name: name, size: size) { return font }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }
    static func save(_ font: NSFont) {
        UserDefaults.standard.set(font.fontName, forKey: "editorFontName")
        UserDefaults.standard.set(font.pointSize, forKey: "editorFontSize")
    }
}

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let families = NSPopUpButton()
    private let size = NSTextField(string: "14")
    private let change: (NSFont) -> Void
    private var selectedFont: NSFont

    init(font: NSFont, change: @escaping (NSFont) -> Void) {
        selectedFont = font
        self.change = change
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 170),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Verbatim Settings"
        window.isReleasedWhenClosed = false
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(root)
        families.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted())
        let family = font.familyName ?? "Menlo"
        if families.indexOfItem(withTitle: family) < 0 { families.addItem(withTitle: family) }
        families.selectItem(withTitle: family)
        families.target = self
        families.action = #selector(updateFont(_:))
        families.setAccessibilityLabel("Editor font")
        size.stringValue = String(format: "%g", font.pointSize)
        size.delegate = self
        size.target = self
        size.action = #selector(updateFont(_:))
        size.widthAnchor.constraint(equalToConstant: 64).isActive = true
        size.setAccessibilityLabel("Font size in points, from 8 to 96")
        let row = NSStackView(views: [NSTextField(labelWithString: "Font"), families, size, NSTextField(labelWithString: "pt")])
        row.spacing = 10
        root.addArrangedSubview(row)
        let description = NSTextField(wrappingLabelWithString: "Font changes affect the editor only. Your files always remain plain text.")
        description.textColor = .secondaryLabelColor
        root.addArrangedSubview(description)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
        ])
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("Use init(font:change:)") }

    func controlTextDidEndEditing(_ obj: Notification) { updateFont(nil) }
    @objc private func updateFont(_ sender: Any?) {
        guard let points = Double(size.stringValue), points.isFinite, (8...96).contains(points) else {
            size.stringValue = String(format: "%g", selectedFont.pointSize)
            NSSound.beep()
            return
        }
        let family = families.titleOfSelectedItem ?? "Menlo"
        let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: points)
            ?? .monospacedSystemFont(ofSize: points, weight: .regular)
        selectedFont = font
        EditorPreferences.save(font)
        change(font)
    }
}
