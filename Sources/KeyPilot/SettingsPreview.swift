import AppKit
import SwiftUI
import KeyPilotCore

/// Uses the production label and border renderer, inside the settings window only.
struct LabelPreview:NSViewRepresentable {
    let preferences:Preferences
    func makeNSView(context:Context) -> LabelPreviewSurface { LabelPreviewSurface() }
    func updateNSView(_ view:LabelPreviewSurface,context:Context) { view.preferences=preferences; view.refresh() }
}
final class LabelPreviewSurface:NSView {
    override var isFlipped:Bool { true }
    var preferences=Preferences()
    private var canvas:OverlayCanvas?
    override func layout() { super.layout(); refresh() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    func refresh() {
        guard bounds.width > 40,bounds.height > 40 else { return }
        let screen=OverlayManager.screenModels.first ?? Screen(id:1,frame:Rect(0,0,1200,800))
        let surface:OverlayCanvas
        if let canvas { surface=canvas } else {
            surface=OverlayCanvas(frame:bounds,screen:screen); canvas=surface; addSubview(surface)
        }
        surface.frame=bounds
        let x=screen.frame.x,y=screen.frame.y,w=Double(bounds.width),h=Double(bounds.height),split=min(190,w*0.31)
        let regions=[Region(id:1,frame:Rect(x+12,y+12,split-18,h-24)),Region(id:2,frame:Rect(x+split+6,y+12,w-split-18,h-24))]
        let locations=[Rect(x+72,y+80,38,26),Rect(x+split+65,y+82,38,26),Rect(x+w-82,y+122,38,26)]
        let placements=locations.enumerated().map { index,rect in
            Placement(target:Target(id:ElementID(index+10),frame:rect),rect:rect,screen:screen.id)
        }
        surface.update(OverlayFrame(regions:regions,selected:2,regionLabels:[1:"W",2:"E"],placements:placements,codes:[10:"AA",11:"SS",12:"DD"],buttonPrefix:"",regionPrefix:"",selectedButton:11,mode:.navigation,endpoint:nil,preferences:preferences))
        // In a settings preview the backdrop is the sample surface in this window.
        for label in surface.subviews.compactMap({$0 as? GlassLabelView}) { label.effect.blendingMode = .withinWindow }
        needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect) {
        let dark=effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        (dark ? NSColor(srgbRed:0.13,green:0.17,blue:0.17,alpha:1):NSColor(srgbRed:0.95,green:0.97,blue:0.96,alpha:1)).setFill()
        bounds.fill()
        let split=min(190,bounds.width*0.31)
        func line(_ rect:NSRect) {
            NSColor.secondaryLabelColor.withAlphaComponent(dark ? 0.20:0.13).setFill()
            NSBezierPath(roundedRect:rect,xRadius:3,yRadius:3).fill()
        }
        for y in [70.0,110,148] { line(NSRect(x:26,y:y,width:split-55,height:5)) }
        for (index,width) in [0.86,0.74,0.81,0.53].enumerated() {
            line(NSRect(x:split+24,y:68+CGFloat(index)*22,width:(bounds.width-split-57)*width,height:5))
        }
        let font=NSFont.systemFont(ofSize:11,weight:.medium)
        ("会话" as NSString).draw(at:NSPoint(x:66,y:28),withAttributes:[.font:font,.foregroundColor:NSColor.secondaryLabelColor])
        ("当前区域" as NSString).draw(at:NSPoint(x:split+59,y:28),withAttributes:[.font:font,.foregroundColor:NSColor.secondaryLabelColor])
    }
}

/// Saved pictures of the real settings view, with isolated fixture preferences.
enum SettingsRenderer {
    static func render(to directory:String) throws {
        let root=URL(fileURLWithPath:directory,isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let suite="dev.pingy.keypilot.preview.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let settings=Settings(defaults:defaults,observeSystem:false)
        settings.trusted=true; settings.hotkeysReady=true; settings.status="热键已就绪：⇧⌘Space / ⇧⌘J"
        var reports:[[String:Any]]=[]
        for (page,dark) in SettingsPage.allCases.map({($0,false)})+[(.appearance,true)] {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:980,height:730),styleMask:[.borderless],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false; window.appearance=NSAppearance(named:dark ? .darkAqua:.aqua)
            let view=NSHostingView(rootView:SettingsView(settings:settings,page:page).environment(\.colorScheme,dark ? .dark:.light))
            window.contentView=view; view.frame=NSRect(x:0,y:0,width:980,height:730)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until:Date().addingTimeInterval(0.15))
            view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
            guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { throw CocoaError(.fileWriteUnknown) }
            view.cacheDisplay(in:view.bounds,to:bitmap)
            guard let data=bitmap.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) }
            let name=page.rawValue+(dark ? "-dark":"")+".png"
            try data.write(to:root.appendingPathComponent(name))
            reports.append(["page":page.rawValue,"dark":dark,"width":bitmap.pixelsWide,"height":bitmap.pixelsHigh])
            window.close()
        }
        printJSON(["settings_previews":reports,"isolated_preferences":true])
    }
}
