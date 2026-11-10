import AppKit
import QuartzCore
import KeyPilotCore

struct OverlayFrame {
    var regions:[Region]
    var selected:ElementID?
    var regionLabels:[ElementID:String]
    var placements:[Placement]
    var codes:[ElementID:String]
    var buttonPrefix:String
    var regionPrefix:String
    var selectedButton:ElementID?
    var mode:Mode
    var endpoint:Endpoint?
    var preferences:Preferences
}

final class OverlayCanvas:NSView {
    override var isFlipped:Bool { true }
    var screen:Screen
    private(set) var snapshot:OverlayFrame?
    private var borders:[ElementID:CAShapeLayer]=[:]
    private var lastSelected:ElementID?
    private let endpointLayer=CAShapeLayer()
    private enum LabelID:Hashable { case region(ElementID),button(ElementID) }
    private var labels:[LabelID:GlassLabelView]=[:]
    init(frame:NSRect,screen:Screen) {
        self.screen=screen; super.init(frame:frame)
        setAccessibilityElement(false); setAccessibilityChildren([])
        wantsLayer=true; layer?.masksToBounds=true; layer?.addSublayer(endpointLayer)
        endpointLayer.fillColor=nil
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func local(_ rect:Rect) -> CGRect { CGRect(x:rect.x-screen.frame.x,y:rect.y-screen.frame.y,width:rect.width,height:rect.height) }
    static func regionLabelRect(_ region:Region,code:String,fontSize:Double) -> Rect {
        let font=NSFont.monospacedSystemFont(ofSize:max(20,fontSize+6),weight:.semibold)
        let width=(code as NSString).size(withAttributes:[.font:font]).width+14
        return Rect(region.frame.x+7,region.frame.y+7,width,max(20,fontSize+6)+10)
    }
    static func regionLabelRects(_ regions:[Region],labels:[ElementID:String],fontSize:Double,screens:[Screen]) -> [ElementID:Rect] {
        var placed:[ElementID:Rect]=[:]
        for region in regions {
            guard let code=labels[region.id],let screen=Screen.owner(of:region.frame,screens:screens) else { continue }
            let visible=Region(id:region.id,frame:region.frame.intersection(screen.frame)),base=regionLabelRect(visible,code:code,fontSize:fontSize)
            var options=[base]
            for index in 1...16 {
                let x=min(visible.frame.maxX-base.width-5,base.x+Double(index)*(base.width+4))
                options.append(Rect(x,base.y,base.width,base.height))
            }
            options += [Rect(base.x,visible.frame.maxY-base.height-5,base.width,base.height),Rect(visible.frame.maxX-base.width-5,visible.frame.maxY-base.height-5,base.width,base.height)]
            placed[region.id]=options.first{candidate in !placed.values.contains{$0.inset(-2).intersects(candidate)}} ?? base
        }
        return placed
    }
    func update(_ frame:OverlayFrame) {
        snapshot=frame
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let color=NSColor(srgbRed:frame.preferences.red,green:frame.preferences.green,blue:frame.preferences.blue,alpha:1)
        let shown=frame.regions.filter { $0.frame.intersects(screen.frame) && (frame.mode != .input || $0.id == frame.selected) }
        let ids=Set(shown.map(\.id))
        for id in Array(borders.keys) where !ids.contains(id) { borders.removeValue(forKey:id)?.removeFromSuperlayer() }
        for region in shown {
            let selected=region.id == frame.selected
            let shape:CAShapeLayer
            if let existing=borders[region.id] { shape=existing }
            else { shape=CAShapeLayer(); shape.fillColor=nil; borders[region.id]=shape; layer?.addSublayer(shape) }
            let rect=local(region.frame).insetBy(dx:1,dy:1)
            if selected,frame.mode == .navigation,let edge=frame.endpoint {
                // Avoid stacking a 50% border beneath the 55% endpoint edge.
                let path=CGMutablePath()
                if edge == .top {
                    path.move(to:CGPoint(x:rect.minX,y:rect.minY)); path.addLine(to:CGPoint(x:rect.minX,y:rect.maxY)); path.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY)); path.addLine(to:CGPoint(x:rect.maxX,y:rect.minY))
                } else {
                    path.move(to:CGPoint(x:rect.minX,y:rect.maxY)); path.addLine(to:CGPoint(x:rect.minX,y:rect.minY)); path.addLine(to:CGPoint(x:rect.maxX,y:rect.minY)); path.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY))
                }
                shape.path=path
            } else { shape.path=CGPath(rect:rect,transform:nil) }
            shape.strokeColor=color.withAlphaComponent(selected ? 0.5:0.1).cgColor; shape.lineWidth=selected ? 1.4:0.6
            let animate=selected && frame.preferences.animation && !frame.preferences.reduceMotion
            if animate {
                if shape.animation(forKey:"breath") == nil || lastSelected != frame.selected {
                    let animation=CABasicAnimation(keyPath:"opacity")
                    animation.fromValue=lastSelected == frame.selected ? (shape.presentation()?.opacity ?? 1):1
                    animation.toValue=0; animation.duration=10; animation.autoreverses=true; animation.repeatCount = .infinity
                    animation.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut)
                    shape.opacity=1; shape.add(animation,forKey:"breath")
                }
            } else { shape.removeAnimation(forKey:"breath"); shape.opacity=1 }
        }
        endpointLayer.path=nil
        if frame.mode == .navigation,let edge=frame.endpoint,let selected=shown.first(where:{$0.id == frame.selected}) {
            let rect=local(selected.frame), y=edge == .top ? rect.minY+1.5:rect.maxY-1.5
            let path=CGMutablePath(); path.move(to:CGPoint(x:rect.minX+1,y:y)); path.addLine(to:CGPoint(x:rect.maxX-1,y:y))
            endpointLayer.path=path; endpointLayer.strokeColor=color.withAlphaComponent(0.55).cgColor; endpointLayer.lineWidth=3
        }
        updateLabels(frame)
        lastSelected=frame.selected
        CATransaction.commit(); needsDisplay=true
    }
    private func updateLabels(_ state:OverlayFrame) {
        var alive:Set<LabelID>=[]
        func place(_ id:LabelID,code:String,rect:CGRect,size:Double,prefix:String,selected:Bool,region:Bool) {
            alive.insert(id)
            let view:GlassLabelView
            if let existing=labels[id] { view=existing }
            else { view=GlassLabelView(); labels[id]=view; addSubview(view) }
            view.update(frame:rect,appearance:LabelAppearance(code:code,fontSize:size,prefix:prefix,selected:selected,region:region,reduceTransparency:state.preferences.reduceTransparency,style:state.preferences.glassStyle))
        }
        if state.mode == .navigation {
            let models=OverlayManager.screenModels
            let regionRects=Self.regionLabelRects(state.regions,labels:state.regionLabels,fontSize:state.preferences.fontSize,screens:models)
            for region in state.regions {
                guard let code=state.regionLabels[region.id],Screen.owner(of:region.frame,screens:models)?.id == screen.id,let rect=regionRects[region.id] else { continue }
                place(.region(region.id),code:code,rect:local(rect),size:max(20,state.preferences.fontSize+6),prefix:region.id == state.selected ? code:state.regionPrefix,selected:false,region:true)
            }
            for placement in state.placements where placement.screen == screen.id {
                guard let code=state.codes[placement.target.id] else { continue }
                var rect=local(placement.rect)
                rect.size.width=(code as NSString).size(withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:state.preferences.fontSize,weight:.semibold)]).width+10
                place(.button(placement.target.id),code:code,rect:rect,size:state.preferences.fontSize,prefix:state.buttonPrefix,selected:state.selectedButton == placement.target.id,region:false)
            }
        }
        for id in Array(labels.keys) where !alive.contains(id) { labels.removeValue(forKey:id)?.removeFromSuperview() }
    }
    override func draw(_ dirtyRect:NSRect) {
        guard let state=snapshot,state.mode == .navigation else { return }
        for placement in state.placements where placement.screen == screen.id && placement.leader {
            guard let code=state.codes[placement.target.id] else { continue }
            var rect=local(placement.rect)
            rect.size.width=(code as NSString).size(withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:state.preferences.fontSize,weight:.semibold)]).width+10
            let path=NSBezierPath(); path.move(to:CGPoint(x:rect.midX,y:rect.midY))
            let hit=local(placement.target.frame)
            path.line(to:CGPoint(x:min(hit.maxX,max(hit.minX,rect.midX)),y:min(hit.maxY,max(hit.minY,rect.midY))))
            NSColor(srgbRed:0.35,green:0.48,blue:0.60,alpha:0.5).setStroke(); path.lineWidth=0.7; path.stroke()
        }
    }
    func glassEvidence() -> [String:Any] {
        ["label_count":labels.count,"backdrop_count":labels.values.filter{!$0.effect.isHidden}.count,
         "behind_window":labels.values.allSatisfy{$0.effect.blendingMode == .behindWindow},
         "active_material":labels.values.allSatisfy{$0.effect.state == .active && $0.effect.material == .popover},
         "material_alpha":labels.values.first?.effect.alphaValue ?? 0,
         "button_tint_alpha":labels.values.first{!($0.appearanceValue?.region ?? true) && !($0.appearanceValue?.selected ?? true)}?.appearanceValue?.tintAlpha ?? 0,
         "region_tint_alpha":labels.values.first{$0.appearanceValue?.region ?? false}?.appearanceValue?.tintAlpha ?? 0]
    }
    func animationEvidence() -> [String:Any] {
        let selected=lastSelected.flatMap{borders[$0]}, animation=selected?.animation(forKey:"breath") as? CABasicAnimation
        return ["fill_is_nil":borders.values.allSatisfy{$0.fillColor == nil},"selected_width":selected?.lineWidth ?? 0,"animation_keypath":animation?.keyPath ?? "none","half_cycle_seconds":animation?.duration ?? 0,"autoreverses":animation?.autoreverses ?? false,"endpoint_width":endpointLayer.lineWidth]
    }
}

final class OverlayManager {
    private var windows:[UInt32:OverlayPanel]=[:]
    private var canvases:[UInt32:OverlayCanvas]=[:]
    static var screenModels:[Screen] {
        let height=NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.compactMap { screen in
            guard let id=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
            return Screen(id:id,frame:Rect(screen.frame.minX,height-screen.frame.maxY,screen.frame.width,screen.frame.height))
        }
    }
    func prepare() {
        let models=Self.screenModels
        for screen in NSScreen.screens {
            guard let id=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32,let model=models.first(where:{$0.id == id}) else { continue }
            if windows[id] != nil { continue }
            let window=OverlayPanel(screenFrame:screen.frame)
            let canvas=OverlayCanvas(frame:CGRect(origin:.zero,size:screen.frame.size),screen:model)
            window.contentView=canvas; windows[id]=window; canvases[id]=canvas
            _="SSS".size(withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:13,weight:.semibold)])
        }
    }
    func show(_ frame:OverlayFrame) { prepare(); for (id,canvas) in canvases { canvas.update(frame); windows[id]?.orderFrontRegardless(); canvas.displayIfNeeded() } }
    func hide() { windows.values.forEach{$0.orderOut(nil)} }
    func reset() { hide(); windows.values.forEach{$0.close()}; windows=[:]; canvases=[:] }
}
