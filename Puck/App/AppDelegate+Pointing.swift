//
//  AppDelegate+Pointing.swift
//  Puck
//
//  F10/F11 · owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Walks the pet to a target and holds a point gesture on it, driven by
//  point_at / tool_cancel.
//

import CoreGraphics
import Foundation

extension AppDelegate {
    // MARK: - Pointing (F10/F11)

    /// point_at: walk to the target, then point at it. The tool only learns
    /// the pet arrived when Point is actually entered, which is what protocol
    /// section 4 promises the agent.
    func pointAt(frame: CGRect, onPointingStarted: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let controller = self.characterController else {
                onPointingStarted() // nothing can point; don't strand the caller
                return
            }

            // A still-pending point_at (pet hasn't arrived yet) redirects the
            // walk, same as MoveTo's target being overwritten -- but its
            // caller was still waiting on onPointingStarted, which would
            // otherwise be silently dropped and hang until ToolExecutor's
            // 15s timeout instead of getting a reply now.
            if let superseded = self.pendingPointTracker.replace(frame: frame, onStarted: onPointingStarted) {
                superseded()
            }

            // Stand beside the target rather than on top of it, so the
            // character isn't covering what it is trying to show.
            let standOffset: CGFloat = 60
            self.moveToState.target = CGPoint(x: frame.midX - standOffset, y: frame.maxY)
            self.moveToState.nextState = .point
            controller.transition(to: .moveTo)
        }
    }

    /// tool_cancel or ToolExecutor's 15s timeout for an in-flight point_at.
    /// Clears the tracked entry so a pet that arrives after cancellation
    /// doesn't still fire onPointingStarted for a call the caller was
    /// already told was cancelled (found via review).
    func cancelPointing() {
        DispatchQueue.main.async { [weak self] in
            self?.pendingPointTracker.clearPending()
        }
    }

    /// Called by PointState once the pet is in place and the point clip is up.
    func beginPointingTimer() {
        guard let (frame, onStarted) = pendingPointTracker.consumeIfPending() else { return }

        pointingController.onPointingReleased = { [weak self] in
            self?.characterController?.transition(to: .idle)
        }
        pointingController.beginPointing(targetFrame: frame)
        onStarted()
    }
}
