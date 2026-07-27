//
//  TextInputBubbleView.swift
//  PetAgent
//
//  F6 · owner: Haeyoung Park
//  NSVisualEffectView + NSTextField bubble UI
//
//  Enter -> onSubmit (protocol 3.3 user_input(source: "text")); Escape ->
//  onCancel. If the socket isn't connected, the caller is responsible for
//  showing a "워크스페이스 꺼져있음" bubble instead of actually sending —
//  that's Bridge-layer knowledge this view doesn't have.

import AppKit

final class TextInputBubbleView: NSVisualEffectView {
    private let textField = NSTextField()
    private var isShowingMessage = false

    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        configureTextField()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for TextInputBubbleView")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !isShowingMessage else { return }
        window?.makeFirstResponder(textField)
    }

    /// Read-only notice mode — used for F6's "워크스페이스 꺼져있음" and, later,
    /// agent_done summaries (EventReaction.bubbleText). Nothing can be typed
    /// or submitted while a notice is showing.
    func showMessage(_ text: String) {
        isShowingMessage = true
        textField.isEditable = false
        textField.isSelectable = false
        textField.stringValue = text
        window?.makeFirstResponder(nil)
    }

    /// Back to the editable input field.
    func showInput() {
        isShowingMessage = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.stringValue = ""
        window?.makeFirstResponder(textField)
    }

    private func configureTextField() {
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

extension TextInputBubbleView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // A notice bubble has nothing to submit; let Escape still dismiss it.
        if isShowingMessage, commandSelector == #selector(NSResponder.insertNewline(_:)) {
            return false
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onSubmit?(textField.stringValue)
            textField.stringValue = ""
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel?()
            return true
        }
        return false
    }
}
