import AppKit
import XCTest
@testable import Verbatim

final class EditorTests: XCTestCase {
    @MainActor func testSubstitutionsStayOffEvenWhenEnabled() {
        let editor = VerbatimTextView()
        editor.isRichText = true
        editor.isAutomaticQuoteSubstitutionEnabled = true
        editor.isAutomaticDashSubstitutionEnabled = true
        editor.isAutomaticTextReplacementEnabled = true
        editor.isAutomaticSpellingCorrectionEnabled = true
        editor.isAutomaticLinkDetectionEnabled = true
        editor.isAutomaticDataDetectionEnabled = true
        editor.isAutomaticTextCompletionEnabled = true
        editor.smartInsertDeleteEnabled = true
        XCTAssertFalse(editor.isRichText)
        XCTAssertFalse(editor.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(editor.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(editor.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(editor.isAutomaticSpellingCorrectionEnabled)
        XCTAssertFalse(editor.isAutomaticLinkDetectionEnabled)
        XCTAssertFalse(editor.isAutomaticDataDetectionEnabled)
        XCTAssertFalse(editor.isAutomaticTextCompletionEnabled)
        XCTAssertFalse(editor.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(editor.isGrammarCheckingEnabled)
        XCTAssertFalse(editor.smartInsertDeleteEnabled)
        XCTAssertTrue(editor.allowsUndo)
        XCTAssertTrue(editor.usesFindBar)
    }

    @MainActor func testTypingPreservesPunctuationAndListText() {
        let editor = VerbatimTextView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = editor
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        let text = "\"hello\" -- teh (c)\n1. one\n* two\nhttps://example.org\n"
        for scalar in text.unicodeScalars { editor.insertText(String(scalar), replacementRange: editor.selectedRange()) }
        XCTAssertEqual(editor.string, text)
    }

    @MainActor func testSystemToggleActionsCannotEnableSubstitutions() {
        let editor = VerbatimTextView()
        editor.toggleAutomaticQuoteSubstitution(nil)
        editor.toggleAutomaticDashSubstitution(nil)
        editor.toggleAutomaticTextReplacement(nil)
        editor.toggleAutomaticSpellingCorrection(nil)
        editor.toggleAutomaticLinkDetection(nil)
        editor.toggleAutomaticDataDetection(nil)
        editor.toggleAutomaticTextCompletion(nil)
        editor.toggleSmartInsertDelete(nil)
        XCTAssertFalse(editor.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(editor.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(editor.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(editor.isAutomaticSpellingCorrectionEnabled)
        XCTAssertFalse(editor.isAutomaticLinkDetectionEnabled)
        XCTAssertFalse(editor.isAutomaticDataDetectionEnabled)
        XCTAssertFalse(editor.isAutomaticTextCompletionEnabled)
        XCTAssertFalse(editor.smartInsertDeleteEnabled)
    }
}
