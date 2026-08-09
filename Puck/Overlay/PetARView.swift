//
//  PetARView.swift
//  Puck
//
//  F1 · owner: Sangwoo Kang
//  ARView(.nonAR) subclass, transparent background/camera setup, alpha-halo mitigation point
//

import RealityKit
import AppKit
import QuartzCore

/// Transparent, non-AR RealityKit view hosting the avatar for one display.
/// The camera is placed far away with a narrow FOV specifically to keep
/// perspective distortion negligible, so ScreenSpaceMapper's linear
/// pixel<->world mapping holds in practice (plan/02_pet-app.md F1).
final class PetARView: ARView {
    /// protocol/02_pet-app.md's fixed camera distance; paired with a narrow FOV.
    private static let cameraDistance: Float = 100
    private static let cameraFieldOfViewDegrees: Float = 10

    private let cameraAnchor = AnchorEntity(world: .zero)
    private let cameraEntity = PerspectiveCamera()

    /// Where avatar entities attach, in world space — kept separate from
    /// `cameraAnchor` so avatar positioning is independent of camera space.
    let contentAnchor = AnchorEntity(world: .zero)

    required init(frame frameRect: CGRect) {
        // Unlike iOS/visionOS, macOS's ARView has no camera-passthrough AR
        // session at all (no `cameraMode`/`automaticallyConfigureSession`
        // properties exist here) — it's non-AR by definition on this
        // platform, so there's nothing to opt out of.
        super.init(frame: frameRect)
        configureTransparentBackground()
        configureCamera()
        scene.addAnchor(contentAnchor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for PetARView")
    }

    private func configureTransparentBackground() {
        environment.background = .color(.clear)
        // alpha-halo mitigation procedure (plan/02_pet-app.md F1), in order:
        // 1. basic transparent-background render (this method) — check first.
        // 2. disable MSAA if a halo persists.
        // 3. check CAMetalLayer.isOpaque / pixelFormat (premultiplied alpha).
        // 4. last resort: a 1px erode post-process.
        // SceneKit fallback is the final decision if all of the above fail.
        // Steps 2-4 need a real running avatar to evaluate against and are
        // deliberately not implemented speculatively here.
        wantsLayer = true
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.isOpaque = false
        }
    }

    private func configureCamera() {
        cameraEntity.camera.fieldOfViewInDegrees = Self.cameraFieldOfViewDegrees
        cameraEntity.position = [0, 0, Self.cameraDistance]
        cameraAnchor.addChild(cameraEntity)
        scene.addAnchor(cameraAnchor)
    }
}
