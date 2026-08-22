//
//  VerticalSlider.swift
//  Puck
//
//  An upright slider, which SwiftUI does not have on macOS.
//
//  The first attempt was a SwiftUI `Slider` turned on its side with
//  `rotationEffect`. It drew correctly and took no drags at all: the control
//  underneath is an AppKit one, and it goes on receiving mouse events in its
//  own unrotated space whatever the layer is doing. AppKit has had vertical
//  sliders all along, so this asks for one.
//

import AppKit
import SwiftUI

struct VerticalSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.isVertical = true
        slider.controlSize = .mini
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.onChange = { value = $0 }
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        // Only when it differs: writing the slider's own value back while a
        // drag is in flight fights the drag.
        if abs(slider.doubleValue - value) > 0.001 {
            slider.doubleValue = value
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator { value = $0 } }

    final class Coordinator: NSObject {
        var onChange: (Double) -> Void

        init(onChange: @escaping (Double) -> Void) {
            self.onChange = onChange
        }

        @objc func changed(_ sender: NSSlider) {
            onChange(sender.doubleValue)
        }
    }
}
