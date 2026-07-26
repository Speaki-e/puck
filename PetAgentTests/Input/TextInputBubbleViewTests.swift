//
//  TextInputBubbleViewTests.swift
//  PetAgent
//
//  F6 test · owner: 박해영 (Haeyoung Park)
//  Enter -> onSubmit(text) + clears the field; Escape -> onCancel.
//

import XCTest
import AppKit
@testable import PetAgent

final class TextInputBubbleViewTests: XCTestCase {
    private func makeView() -> TextInputBubbleView {
        TextInputBubbleView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
    }

    func test_enter_firesOnSubmitWithCurrentText_andClearsField() throws {
        let view = makeView()
        let textField = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
        textField.stringValue = "hello"

        var submitted: String?
        view.onSubmit = { submitted = $0 }

        let handled = view.control(textField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))

        XCTAssertTrue(handled)
        XCTAssertEqual(submitted, "hello")
        XCTAssertEqual(textField.stringValue, "")
    }

    func test_escape_firesOnCancel() throws {
        let view = makeView()
        let textField = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)

        var cancelled = false
        view.onCancel = { cancelled = true }

        let handled = view.control(textField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))

        XCTAssertTrue(handled)
        XCTAssertTrue(cancelled)
    }

    func test_unrelatedCommand_isNotHandled() throws {
        let view = makeView()
        let textField = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)

        let handled = view.control(textField, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveLeft(_:)))

        XCTAssertFalse(handled)
    }
}
