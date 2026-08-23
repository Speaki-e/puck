//
//  PaneFrameReporter.swift
//  Puck
//
//  Publishes the editor pane's on-screen rect so the pet can be sent to it.
//  An NSView rather than a GeometryReader: GeometryReader reports view-local
//  coordinates, and only the backing view knows where its window is, which
//  is the part the pet needs.
//

import AppKit
import SwiftUI

struct PaneFrameReporter: NSViewRepresentable {
    let onChange: (CGRect?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ReportingView)?.onChange = onChange
    }

    final class ReportingView: NSView {
        var onChange: ((CGRect?) -> Void)?
        private var windowObservers: [NSObjectProtocol] = []

        /// Moving a window lays nothing out, so `layout()` never runs and the
        /// rect reported from it goes stale the moment the window is dragged:
        /// the pet stayed standing where the window used to be. The window's
        /// own notifications are the only thing that says it moved.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observeWindow()
            report()
        }

        deinit {
            windowObservers.forEach(NotificationCenter.default.removeObserver)
        }

        private func observeWindow() {
            windowObservers.forEach(NotificationCenter.default.removeObserver)
            windowObservers = []
            guard let window else { return }
            // Screen changes matter as much as moves: the same window on a
            // display with a different origin is a different rect in the
            // coordinates the pet lives in.
            for name: NSNotification.Name in [
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification,
                NSWindow.didChangeScreenNotification,
            ] {
                windowObservers.append(
                    NotificationCenter.default.addObserver(
                        forName: name,
                        object: window,
                        queue: .main
                    ) { [weak self] _ in
                        self?.report()
                    }
                )
            }
        }

        override func layout() {
            super.layout()
            report()
        }

        private func report() {
            guard let window, window.isVisible else {
                onChange?(nil)
                return
            }
            onChange?(window.convertToScreen(convert(bounds, to: nil)))
        }
    }
}
