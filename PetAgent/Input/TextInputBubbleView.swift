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
        // Spotlight's own look, as closely as AppKit gives it for free
        // (byeolki: "이거 spotlight 느낌으로 만들어줘", 2026-07-30): one wide
        // translucent slab holding one line of large text, and nothing else --
        // the leading glyph this had at first just read as clutter ("그 왼쪽에
        // 띄운 이상한 심볼 삭제", 2026-07-30).
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true
        // A layer corner radius rounds the CONTENTS; the behind-window blur is
        // drawn to the view's own shape and stayed a full rectangle, so the
        // panel read as a rounded box sitting on a square backdrop (byeolki:
        // "완전 직사각형 배경 위에 둥근 사각형이 나온듯한 느낌", 2026-07-30).
        // Only maskImage reshapes the blur itself.
        maskImage = Self.roundedMask(radius: Self.cornerRadius)
        // The hairline that keeps the panel from dissolving into a light
        // desktop -- Spotlight has one, and without it the blur alone leaves
        // no edge at all over pale backgrounds.
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        configureTextField()
    }

    /// Spotlight's panel proportions -- wide, one row tall, softly rounded.
    static let panelSize = CGSize(width: 640, height: 64)
    static let cornerRadius: CGFloat = 20
    private static let horizontalInset: CGFloat = 20

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
        // Big enough to be the only thing in the panel, like Spotlight's.
        textField.font = .systemFont(ofSize: 24, weight: .regular)
        textField.placeholderString = Self.placeholder
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// Hardcoded Korean, like the "워크스페이스가 꺼져 있어요" notice this same
    /// bubble shows -- bubble copy doesn't go through Strings yet.
    private static let placeholder = "무엇을 도와드릴까요?"

    /// A rounded rectangle just big enough to hold both corners, stretched
    /// across whatever size the panel ends up -- the cap insets keep the
    /// corners crisp instead of scaling them with the panel.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
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
