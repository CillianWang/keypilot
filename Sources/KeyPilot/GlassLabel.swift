import AppKit

struct LabelAppearance:Equatable {
    var code:String
    var fontSize:Double
    var prefix:String
    var selected:Bool
    var region:Bool
    var reduceTransparency:Bool
    var style:GlassStyle = .light
    var radius:CGFloat { region ? 8:6 }
    var tintAlpha:Double {
        if reduceTransparency { return 1 }
        if region { return 0.28 }
        if style == .tea { return selected ? 0.42:0.30 }
        return selected ? 0.18:0.06
    }
}

/// The system compositor blurs only each label's rounded backdrop, never the content area.
final class GlassLabelView:NSView {
    let effect=NSVisualEffectView()
    private let ink=LabelInkView()
    private(set) var appearanceValue:LabelAppearance?
    override var isFlipped:Bool { true }
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    init() {
        super.init(frame:.zero)
        wantsLayer=true
        setAccessibilityElement(false); setAccessibilityChildren([])
        effect.material = .popover; effect.blendingMode = .behindWindow; effect.state = .active
        effect.wantsLayer=true; effect.layer?.masksToBounds=true
        effect.setAccessibilityElement(false); effect.setAccessibilityChildren([])
        ink.setAccessibilityElement(false)
        addSubview(effect); addSubview(ink)
        layer?.shadowColor=NSColor(srgbRed:0.10,green:0.18,blue:0.27,alpha:1).cgColor
        layer?.shadowOpacity=0.08; layer?.shadowRadius=2.5; layer?.shadowOffset=CGSize(width:0,height:-0.75)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(frame:NSRect,appearance:LabelAppearance) {
        let changedGeometry=self.frame.size != frame.size || appearanceValue?.radius != appearance.radius
        self.frame=frame; effect.frame=bounds; ink.frame=bounds
        effect.isHidden=appearance.reduceTransparency
        // Fade the backdrop independently so the letters retain full contrast.
        effect.alphaValue=appearance.style == .tea ? 0.88:0.62
        if appearanceValue?.style != appearance.style {
            switch appearance.style {
            case .light:self.appearance=NSAppearance(named:.aqua)
            case .dark,.tea:self.appearance=NSAppearance(named:.darkAqua)
            case .system:self.appearance=nil
            }
            layer?.shadowColor=(appearance.style == .tea ? NSColor(srgbRed:0.19,green:0.09,blue:0.03,alpha:1):NSColor(srgbRed:0.10,green:0.18,blue:0.27,alpha:1)).cgColor
        }
        if changedGeometry {
            let radius=appearance.radius
            effect.layer?.cornerRadius=radius; effect.layer?.cornerCurve = .continuous
            effect.maskImage=NSImage(size:bounds.size,flipped:false) { rect in
                NSColor.white.setFill(); NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius).fill(); return true
            }
            layer?.shadowPath=CGPath(roundedRect:bounds,cornerWidth:radius,cornerHeight:radius,transform:nil)
        }
        if appearanceValue != appearance { ink.value=appearance; ink.needsDisplay=true }
        appearanceValue=appearance
    }
}

private final class LabelInkView:NSView {
    var value:LabelAppearance?
    override var isFlipped:Bool { true }
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay=true }
    override func draw(_ dirtyRect:NSRect) {
        guard let value else { return }
        let dark=effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        let lightRegionInk=dark && !value.reduceTransparency
        let tea=value.style == .tea
        let tint:NSColor
        if value.region {
            tint=NSColor(srgbRed:0.44,green:0.91,blue:0.72,alpha:value.tintAlpha)
        } else if tea {
            tint=value.selected ? NSColor(srgbRed:0.72,green:0.49,blue:0.22,alpha:value.tintAlpha):NSColor(srgbRed:0.48,green:0.29,blue:0.13,alpha:value.tintAlpha)
        } else {
            let background=dark ? NSColor(white:0.13,alpha:value.tintAlpha):NSColor(srgbRed:0.93,green:0.97,blue:1,alpha:value.tintAlpha)
            tint=value.selected ? NSColor(srgbRed:0.44,green:0.91,blue:0.72,alpha:value.tintAlpha):background
        }
        tint.setFill(); NSBezierPath(roundedRect:bounds,xRadius:value.radius,yRadius:value.radius).fill()
        let rimColor=value.region ? NSColor(srgbRed:0.68,green:0.96,blue:0.84,alpha:0.40):(tea ? NSColor(srgbRed:0.98,green:0.82,blue:0.55,alpha:0.25):NSColor(white:1,alpha:dark ? 0.16:0.32))
        rimColor.setStroke()
        let rim=NSBezierPath(roundedRect:bounds.insetBy(dx:0.3,dy:0.3),xRadius:value.radius-0.3,yRadius:value.radius-0.3)
        rim.lineWidth=0.5; rim.stroke()
        let font=NSFont.monospacedSystemFont(ofSize:value.fontSize,weight:.semibold)
        let foreground=value.region ? (lightRegionInk ? NSColor(srgbRed:0.73,green:0.97,blue:0.87,alpha:1):NSColor(srgbRed:0.10,green:0.27,blue:0.22,alpha:1)):(tea ? NSColor(srgbRed:0.99,green:0.93,blue:0.82,alpha:1):(dark ? NSColor(white:0.98,alpha:1):NSColor(srgbRed:0.10,green:0.15,blue:0.20,alpha:1)))
        let text=NSMutableAttributedString(string:value.code,attributes:[.font:font,.foregroundColor:foreground])
        if !value.prefix.isEmpty,value.code.hasPrefix(value.prefix) {
            let faded=value.region ? (lightRegionInk ? NSColor(srgbRed:0.50,green:0.74,blue:0.65,alpha:1):NSColor(srgbRed:0.34,green:0.52,blue:0.45,alpha:1)):(tea ? NSColor(srgbRed:0.76,green:0.65,blue:0.49,alpha:1):(dark ? NSColor(srgbRed:0.60,green:0.70,blue:0.76,alpha:1):NSColor(srgbRed:0.43,green:0.54,blue:0.62,alpha:1)))
            text.addAttribute(.foregroundColor,value:faded,range:NSRange(location:0,length:min(value.code.count,value.prefix.count)))
        }
        let size=text.size(); text.draw(at:NSPoint(x:bounds.midX-size.width/2,y:bounds.midY-size.height/2))
    }
}

/// Even while ordering above another application, this panel cannot own keyboard focus.
final class OverlayPanel:NSPanel {
    override var canBecomeKey:Bool { false }
    override var canBecomeMain:Bool { false }
    init(screenFrame:NSRect) {
        super.init(contentRect:screenFrame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        backgroundColor = .clear; isOpaque=false; hasShadow=false; ignoresMouseEvents=true
        hidesOnDeactivate=false; becomesKeyOnlyIfNeeded=true
        level=NSWindow.Level(rawValue:NSWindow.Level.popUpMenu.rawValue+1)
        collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
        isReleasedWhenClosed=false
        setAccessibilityElement(false); setAccessibilityChildren([])
    }
}
