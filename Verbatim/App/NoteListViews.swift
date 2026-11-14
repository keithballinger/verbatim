import AppKit

/// The secondary line of a note row: when the note was last modified.
enum NoteDateText {
    /// Today shows the time, then "Yesterday", then the weekday for the rest of the past week,
    /// then a full date. Days are calendar days, so 11pm last night is "Yesterday", not a time.
    static func string(for date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? .max
        if days == 1 {
            let relative = RelativeDateTimeFormatter()
            relative.locale = locale
            relative.calendar = calendar
            relative.dateTimeStyle = .named
            relative.formattingContext = .beginningOfSentence
            return relative.localizedString(from: DateComponents(day: -1))
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        switch days {
        case 0: formatter.dateStyle = .none; formatter.timeStyle = .short
        case 2...6: formatter.setLocalizedDateFormatFromTemplate("EEEE")
        default: formatter.dateStyle = .medium; formatter.timeStyle = .none
        }
        return formatter.string(from: date)
    }
}

/// A note row: title over its modification date, centered so the padding above and below is equal.
final class NoteCellView: NSTableCellView {
    static let rowHeight: CGFloat = 52
    let detail = NSTextField(labelWithString: "")
    private let title = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        let text = NSLayoutGuide()
        addLayoutGuide(text)
        // Direct subviews, so the row's selected state reaches both labels.
        for label in [title, detail] {
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4)
            ])
        }
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: title.topAnchor),
            text.bottomAnchor.constraint(equalTo: detail.bottomAnchor),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3)
        ])
        textField = title
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }

    func show(_ note: NoteRecord) {
        title.stringValue = note.title
        detail.stringValue = NoteDateText.string(for: note.modified)
    }
}
