//
//  VisualEffectBackground.swift
//  Puck
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  Wraps NSVisualEffectView so the sidebar gets the same vibrant, translucent
//  material real Mac apps (Mail, Notes, Xcode) use -- a flat Color reads as
//  a plain settings pane no matter what tone it is (byeolki: "맥 기본
//  설정창처럼 생겼네").
//

import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
