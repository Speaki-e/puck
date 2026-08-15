//
//  WindowMinimumSize.swift
//  Puck
//
//  Keeps the hosting NSWindow's `minSize` in step with what the view is
//  currently showing (2026-08-15).
//
//  Why this exists rather than `.frame(minWidth:)`: PuckClient sets
//  `sizingOptions = []` on its hosting controller (so SwiftUI's fitting size
//  never yanks the window around), which also means a SwiftUI minimum is not
//  a real resize limit -- `NSWindow.minSize` is. The floor also is not one
//  number: opening the editor pane adds a whole column, and a single value
//  that fits both is either too tall a floor for chat alone or too short for
//  chat plus editor. The second case is the one that shipped: the shortfall
//  came out of the file tree and clipped its rows.
//

import AppKit
import SwiftUI

struct WindowMinimumSize: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // Applied on the next runloop pass: at makeNSView time the view is not
        // in a window yet, so `view.window` is nil.
        DispatchQueue.main.async { apply(to: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView) }
    }

    private func apply(to view: NSView) {
        guard let window = view.window else { return }
        window.minSize = CGSize(width: width, height: height)
        // Raising the floor above the current size does not resize the window
        // on its own -- AppKit only enforces minSize during a user drag. Left
        // alone, opening the editor in an already-narrow window would produce
        // exactly the squeezed layout the floor exists to prevent.
        let size = window.frame.size
        guard size.width < width || size.height < height else { return }
        var frame = window.frame
        // Grown from the top-left, the corner macOS windows are anchored to:
        // growing from the origin would walk the title bar off the screen.
        frame.origin.y -= max(0, height - size.height)
        frame.size = CGSize(width: max(size.width, width), height: max(size.height, height))
        window.setFrame(frame, display: true, animate: true)
    }
}
