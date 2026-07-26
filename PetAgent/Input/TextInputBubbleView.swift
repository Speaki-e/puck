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
