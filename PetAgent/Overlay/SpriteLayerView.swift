//
//  SpriteLayerView.swift
//  PetAgent
//
//  F1 · owner: 박해영 (Haeyoung Park)
//  CALayer-backed NSView replacing PetARView (2026-07-29 2D switch).
//
//  RealityKit's ARView, a full 3D render pipeline, is overkill for a static
//  PNG illustration -- it's also what the alpha-halo mitigation dance in
//  PetARView's history existed for in the first place. Drawing a sprite as a
//  CALayer's `contents` has no such artifact to fight, and there's no GPU 3D
//  pass running every frame just to show a flat image (F1's idle-CPU note).
//
//  isFlipped = true puts this view's coordinate space at top-left origin,
//  Y down -- the same convention GlobalScreenSpace/StateContext already use
//  for every movement calculation, so SpriteAvatar can set screen positions
//  directly with zero conversion (unlike ScreenSpaceMapper's world<->screen
//  mapping, which USDZAvatar still needs for RealityKit's Y-up world space).
//

import AppKit
import QuartzCore

final class SpriteLayerView: NSView {
    /// Where the avatar's sprite layer attaches -- analogous to PetARView's
    /// `contentAnchor`, just a CALayer instead of a RealityKit AnchorEntity.
    let contentLayer = CALayer()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(contentLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for SpriteLayerView")
    }
}
