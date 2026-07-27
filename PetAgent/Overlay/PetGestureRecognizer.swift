//
//  PetGestureRecognizer.swift
//  PetAgent
//
//  F1/F3 · owner: 강상우 (Sangwoo Kang)
//  Raw mouse events over the character -> tap or drag.
//
//  ClickThroughController already decides *when* the overlay accepts clicks
//  at all (cursor inside the hitbox); this decides what a press-move-release
//  sequence meant. Kept as a value type with no AppKit dependency so the
//  distinction — which is entirely about thresholds and ordering — is
//  testable without synthesizing NSEvents.
//

import CoreGraphics

enum PetGesture: Equatable {
    /// Pressed and released without meaningfully moving.
    case tapped
    case dragBegan(CGPoint)
    case dragMoved(CGPoint)
    case dragEnded
}

struct PetGestureRecognizer {
    /// How far the cursor may travel while pressed and still count as a click.
    /// A hand shifting a pixel or two shouldn't yank the pet across the screen.
    static let dragThreshold: CGFloat = 4

    private var pressOrigin: CGPoint?
    private var isDragging = false

    mutating func mouseDown(at point: CGPoint) -> PetGesture? {
        pressOrigin = point
        isDragging = false
        return nil
    }

    mutating func mouseDragged(to point: CGPoint) -> PetGesture? {
        // No press means this belongs to something else that happened to pass
        // under the cursor — not an interaction with the pet.
        guard let origin = pressOrigin else { return nil }

        if isDragging {
            return .dragMoved(point)
        }
        guard hypot(point.x - origin.x, point.y - origin.y) > Self.dragThreshold else {
            return nil
        }
        isDragging = true
        return .dragBegan(point)
    }

    mutating func mouseUp(at point: CGPoint) -> PetGesture? {
        guard pressOrigin != nil else { return nil }
        defer {
            pressOrigin = nil
            isDragging = false
        }
        return isDragging ? .dragEnded : .tapped
    }
}
