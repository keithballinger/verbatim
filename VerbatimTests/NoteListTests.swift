import XCTest
@testable import Verbatim

final class NoteListTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    private func label(_ modified: Date) -> String {
        // "Now" is Saturday, November 14, 2026 at noon.
        NoteDateText.string(for: modified, now: date(2026, 11, 14), calendar: calendar, locale: locale)
    }

    func testNoteModifiedTodayShowsItsTime() {
        XCTAssertTrue(label(date(2026, 11, 14, 9, 5)).hasPrefix("9:05"), label(date(2026, 11, 14, 9, 5)))
    }
    func testNoteModifiedYesterdaySaysYesterdayEvenLessThanADayAgo() {
        XCTAssertEqual(label(date(2026, 11, 13, 23, 30)), "Yesterday")
    }
    func testNoteModifiedEarlierThisWeekShowsTheWeekday() {
        XCTAssertEqual(label(date(2026, 11, 10)), "Tuesday")
    }
    func testOlderNoteShowsItsDateWithTheYear() {
        XCTAssertEqual(label(date(2026, 11, 7)), "Nov 7, 2026")
        XCTAssertEqual(label(date(2023, 3, 2)), "Mar 2, 2023")
    }
    func testNoteDatedInTheFutureShowsItsDate() {
        XCTAssertEqual(label(date(2026, 11, 20)), "Nov 20, 2026")
    }
}
