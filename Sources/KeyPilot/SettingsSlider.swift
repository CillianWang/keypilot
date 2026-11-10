import AppKit
import SwiftUI

/// Native slider without dozens of tick marks; mouse, keys and AX share one step.
struct SettingsSlider:NSViewRepresentable {
    @Binding var value:Double
    let range:ClosedRange<Double>,step:Double,title:String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context:Context) -> SteppedSettingsSlider {
        let slider=SteppedSettingsSlider()
        slider.numberOfTickMarks=0; slider.isContinuous=true
        slider.target=context.coordinator; slider.action=#selector(Coordinator.changed(_:))
        slider.setContentHuggingPriority(.defaultLow,for:.horizontal)
        return slider
    }
    func updateNSView(_ slider:SteppedSettingsSlider,context:Context) {
        context.coordinator.parent=self
        slider.minValue=range.lowerBound; slider.maxValue=range.upperBound
        slider.increment=step; slider.altIncrementValue=step; slider.doubleValue=value
        slider.trackFillColor=NSColor(srgbRed:0.28,green:0.65,blue:0.52,alpha:1)
        slider.setAccessibilityLabel(title)
    }
    final class Coordinator:NSObject {
        var parent:SettingsSlider
        init(_ parent:SettingsSlider) { self.parent=parent }
        @objc func changed(_ slider:SteppedSettingsSlider) {
            let low=parent.range.lowerBound
            let rounded=low+((slider.doubleValue-low)/parent.step).rounded()*parent.step
            parent.value=min(parent.range.upperBound,max(low,rounded))
            slider.doubleValue=parent.value
        }
    }
}
final class SteppedSettingsSlider:NSSlider {
    var increment=1.0
    @discardableResult func moveStep(_ direction:Double) -> Bool {
        let next=min(maxValue,max(minValue,doubleValue+increment*direction))
        guard next != doubleValue else { return false }
        doubleValue=next
        if let action { sendAction(action,to:target) }
        return true
    }
    override func keyDown(with event:NSEvent) {
        if !event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 123,125:moveStep(-1); return
            case 124,126:moveStep(1); return
            default:break
            }
        }
        super.keyDown(with:event)
    }
    override func accessibilityPerformIncrement() -> Bool { moveStep(1) }
    override func accessibilityPerformDecrement() -> Bool { moveStep(-1) }
}
