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

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
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
