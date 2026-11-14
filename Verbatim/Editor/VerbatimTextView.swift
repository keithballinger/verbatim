import AppKit

/// The invariant lives here, not in global user defaults or a one-time menu setting.
final class VerbatimTextView: NSTextView {
    private let ownedStorage: NSTextStorage?
    override var isRichText: Bool {
        get { super.isRichText }
        set { super.isRichText = false }
    }
    override var isAutomaticQuoteSubstitutionEnabled: Bool {
        get { super.isAutomaticQuoteSubstitutionEnabled }
        set { super.isAutomaticQuoteSubstitutionEnabled = false }
    }
    override var isAutomaticDashSubstitutionEnabled: Bool {
        get { super.isAutomaticDashSubstitutionEnabled }
        set { super.isAutomaticDashSubstitutionEnabled = false }
    }
    override var isAutomaticTextReplacementEnabled: Bool {
        get { super.isAutomaticTextReplacementEnabled }
        set { super.isAutomaticTextReplacementEnabled = false }
    }
    override var isAutomaticSpellingCorrectionEnabled: Bool {
        get { super.isAutomaticSpellingCorrectionEnabled }
        set { super.isAutomaticSpellingCorrectionEnabled = false }
    }
    override var isAutomaticLinkDetectionEnabled: Bool {
        get { super.isAutomaticLinkDetectionEnabled }
        set { super.isAutomaticLinkDetectionEnabled = false }
    }
    override var isAutomaticDataDetectionEnabled: Bool {
        get { super.isAutomaticDataDetectionEnabled }
        set { super.isAutomaticDataDetectionEnabled = false }
    }
    override var isAutomaticTextCompletionEnabled: Bool {
        get { super.isAutomaticTextCompletionEnabled }
        set { super.isAutomaticTextCompletionEnabled = false }
    }
    override var smartInsertDeleteEnabled: Bool {
        get { super.smartInsertDeleteEnabled }
        set { super.smartInsertDeleteEnabled = false }
    }

    convenience init() { self.init(frame: .zero, textContainer: nil) }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        let textContainer = container ?? NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        if container == nil {
            let storage = NSTextStorage()
            let layout = NSLayoutManager()
            storage.addLayoutManager(layout)
            layout.addTextContainer(textContainer)
            ownedStorage = storage
        } else { ownedStorage = nil }
        super.init(frame: frameRect, textContainer: textContainer)
        isRichText = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        importsGraphics = false
        allowsImageEditing = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textColor = .textColor
        backgroundColor = .textBackgroundColor
        textContainerInset = NSSize(width: 20, height: 20)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        isEditable = true
        isSelectable = true
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        autoresizingMask = [.width]
        self.textContainer?.widthTracksTextView = true
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    override func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        insertText(text, replacementRange: selectedRange())
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for (name, action) in [("Cut", #selector(cut(_:))), ("Copy", #selector(copy(_:))),
                               ("Paste", #selector(paste(_:))), ("Select All", #selector(selectAll(_:)))] {
            menu.addItem(withTitle: name, action: action, keyEquivalent: "")
        }
        return menu
    }
}
