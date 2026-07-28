//
//  PendingPointTracker.swift
//  PetAgent
//
//  F10/F11 · owner: Haeyoung Park
//  Tracks the single in-flight point_at request the pet is walking toward.
//
//  A point_at that arrives before a previous one has reached its target
//  redirects the walk (same as MoveTo's target being overwritten), but the
//  superseded request's caller was still waiting on its own onPointingStarted
//  callback -- silently dropping it left that tool_dispatch hanging until
//  ToolExecutor's 15s timeout instead of getting a reply. This class only
//  tracks state and reports what needs to happen; it has no side effects of
//  its own, so it's fully testable without RealityKit/AppKit.

import CoreGraphics

final class PendingPointTracker {
    private var pending: (frame: CGRect, onStarted: () -> Void)?

    /// Registers a new pending point_at, returning the previous one's
    /// callback (if any) so the caller can invoke it -- it was superseded,
    /// not failed, but still needs a reply.
    func replace(frame: CGRect, onStarted: @escaping () -> Void) -> (() -> Void)? {
        let superseded = pending?.onStarted
        pending = (frame, onStarted)
        return superseded
    }

    /// Called once Point actually starts. Returns the pending frame/callback
    /// and clears state, or nil if nothing is pending.
    func consumeIfPending() -> (frame: CGRect, onStarted: () -> Void)? {
        defer { pending = nil }
        return pending
    }
}
