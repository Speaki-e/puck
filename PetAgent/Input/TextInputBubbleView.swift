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

final class TextInputBubbleView: NSView {
    private let textField = NSTextField()
    private var isShowingMessage = false

    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installBackground()
        configureTextField()
    }

    /// Real Liquid Glass on macOS 26 (the AppKit side of the same gate
    /// GlassSurface applies in SwiftUI), the Spotlight-style vibrant slab it
    /// always had before that. The background is a sibling *below* the text
    /// field, not its superview -- the field stays a direct subview so
    /// first-responder wiring and tests keep finding it in `subviews`.
    private func installBackground() {
        let background: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.cornerRadius
            background = glass
        } else {
            // Spotlight's own look, as closely as AppKit gives it for free
            // (byeolki: "이거 spotlight 느낌으로 만들어줘", 2026-07-30): one wide
            // translucent slab holding one line of large text, and nothing else --
            // the leading glyph this had at first just read as clutter ("그 왼쪽에
            // 띄운 이상한 심볼 삭제", 2026-07-30).
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = Self.cornerRadius
            effect.layer?.masksToBounds = true
            // A layer corner radius rounds the CONTENTS; the behind-window blur is
            // drawn to the view's own shape and stayed a full rectangle, so the
            // panel read as a rounded box sitting on a square backdrop (byeolki:
            // "완전 직사각형 배경 위에 둥근 사각형이 나온듯한 느낌", 2026-07-30).
            // Only maskImage reshapes the blur itself.
            effect.maskImage = Self.roundedMask
            // The hairline that keeps the panel from dissolving into a light
            // desktop -- Spotlight has one, and without it the blur alone leaves
            // no edge at all over pale backgrounds.
            effect.layer?.borderWidth = 1
            effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            background = effect
        }
        background.frame = bounds
        background.autoresizingMask = [.width, .height]
        addSubview(background)
    }

    /// Spotlight's panel proportions -- wide, one row tall, softly rounded.
    static let panelSize = CGSize(width: 640, height: 64)
    static let cornerRadius: CGFloat = 20
    static let horizontalInset: CGFloat = 20
    /// Only used for speech sizing; the input panel's height is fixed.
    static let verticalInset: CGFloat = 12

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for TextInputBubbleView")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !isShowingMessage else { return }
        window?.makeFirstResponder(textField)
    }

    /// Read-only notice mode — F6's "워크스페이스 꺼져있음", agent_done
    /// summaries, the mute sulk. Nothing can be typed while a notice shows.
    ///
    /// This is the pet *speaking*, so it drops the Spotlight typography: the
    /// bar's 24pt single line is right for a capture field the user is aiming
    /// at, and wrong for a bubble the size of a sentence sitting over a
    /// character's head (byeolki, 2026-07-31: "말풍선이 펫한테서 나오게").
    func showMessage(_ text: String) {
        isShowingMessage = true
        textField.isEditable = false
        textField.isSelectable = false
        textField.font = Self.speechFont
        textField.usesSingleLineMode = false
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        textField.alignment = .center
        textField.stringValue = text
        window?.makeFirstResponder(nil)
    }

    /// Back to the editable input field.
    func showInput() {
        isShowingMessage = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.font = Self.inputFont
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.alignment = .natural
        textField.stringValue = ""
        window?.makeFirstResponder(textField)
    }

    /// Big enough to be the only thing in the Spotlight panel.
    static let inputFont = NSFont.systemFont(ofSize: 24, weight: .regular)
    /// Speech is read at a glance beside the pet, not aimed at.
    static let speechFont = NSFont.systemFont(ofSize: 15, weight: .regular)

    /// A speech bubble is the size of what was said. Wraps past
    /// `speechMaxWidth` rather than growing into another Spotlight bar.
    static let speechMaxWidth: CGFloat = 300

    static func speechSize(for text: String) -> CGSize {
        let available = speechMaxWidth - horizontalInset * 2
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: available, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: speechFont]
        )
        return CGSize(
            width: min(speechMaxWidth, ceil(bounds.width) + horizontalInset * 2),
            height: max(44, ceil(bounds.height) + verticalInset * 2)
        )
    }

    private func configureTextField() {
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        // Big enough to be the only thing in the panel, like Spotlight's.
        textField.font = Self.inputFont
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
    /// corners crisp instead of scaling them with the panel. Rendered once:
    /// a fresh bubble view is built per show, and the mask never varies.
    private static let roundedMask: NSImage = {
        let radius = cornerRadius
        let side = radius * 2 + 1
        let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }()
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
