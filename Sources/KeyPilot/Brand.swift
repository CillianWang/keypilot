import AppKit

/// Original vector mark: the K's upper arm becomes a navigation arrow.
enum Brand {
    static let mint=NSColor(srgbRed:0.57,green:0.89,blue:0.76,alpha:1)
    static let ink=NSColor(srgbRed:0.08,green:0.27,blue:0.24,alpha:1)
    static func mark(in rect:NSRect,color:NSColor) {
        let scale=min(rect.width,rect.height)/100
        let transform=NSAffineTransform()
        transform.translateX(by:rect.midX-50*scale,yBy:rect.midY-50*scale)
        transform.scale(by:scale); transform.concat()
        let path=NSBezierPath()
        path.move(to:NSPoint(x:32,y:29)); path.line(to:NSPoint(x:32,y:71))
        path.move(to:NSPoint(x:33,y:53)); path.line(to:NSPoint(x:68,y:29))
        path.move(to:NSPoint(x:53,y:29)); path.line(to:NSPoint(x:68,y:29)); path.line(to:NSPoint(x:68,y:44))
        path.move(to:NSPoint(x:45,y:45)); path.line(to:NSPoint(x:69,y:71))
        path.lineWidth=7.5; path.lineCapStyle = .round; path.lineJoinStyle = .round
        color.setStroke(); path.stroke()
        transform.invert(); transform.concat()
    }
    static func image(size:CGFloat,template:Bool=false) -> NSImage {
        let image=NSImage(size:NSSize(width:size,height:size),flipped:true) { rect in
            NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
            if template {
                // Optical size: fill the menu icon without the app tile's padding.
                mark(in:rect.insetBy(dx:-size*0.34,dy:-size*0.34),color:.black)
            } else {
                let tile=rect.insetBy(dx:size*0.08,dy:size*0.08)
                let outline=NSBezierPath(roundedRect:tile,xRadius:size*0.19,yRadius:size*0.19)
                let shadow=NSShadow(); shadow.shadowColor=ink.withAlphaComponent(0.16)
                shadow.shadowBlurRadius=size*0.035; shadow.shadowOffset=NSSize(width:0,height:size*0.018)
                shadow.set()
                NSGradient(starting:NSColor(srgbRed:0.82,green:0.98,blue:0.91,alpha:1),ending:mint)!.draw(in:outline,angle:60)
                let clearShadow=NSShadow(); clearShadow.shadowColor = .clear; clearShadow.set()
                NSColor.white.withAlphaComponent(0.65).setStroke(); outline.lineWidth=max(0.5,size*0.002); outline.stroke()
                let inner=NSBezierPath(roundedRect:rect.insetBy(dx:size*0.135,dy:size*0.135),xRadius:size*0.14,yRadius:size*0.14)
                NSColor.white.withAlphaComponent(0.35).setStroke(); inner.lineWidth=size*0.003; inner.stroke()
                mark(in:rect,color:ink)
            }
            return true
        }
        image.isTemplate=template
        image.accessibilityDescription="Keylian"
        return image
    }
    static func export(to directory:String) throws {
        let root=URL(fileURLWithPath:directory,isDirectory:true)
        let set=root.appendingPathComponent("AppIcon.iconset",isDirectory:true)
        try FileManager.default.createDirectory(at:set,withIntermediateDirectories:true)
        func png(_ pixels:Int) throws -> Data {
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
            image(size:CGFloat(pixels)).draw(in:NSRect(x:0,y:0,width:pixels,height:pixels))
            NSGraphicsContext.restoreGraphicsState()
            guard let data=bitmap.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) }
            return data
        }
        for size in [16,32,128,256,512] {
            try png(size).write(to:set.appendingPathComponent("icon_\(size)x\(size).png"))
            try png(size*2).write(to:set.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
        }
        try png(1024).write(to:root.appendingPathComponent("Keylian.png"))
    }
}
