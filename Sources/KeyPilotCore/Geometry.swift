import Foundation
import CoreGraphics

public typealias ElementID = UInt64

public struct Point: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public func distance(to p: Point) -> Double { hypot(x - p.x, y - p.y) }
}

/// All model geometry uses AX/Quartz global coordinates: origin at the main screen's top left.
public struct Rect: Hashable, Codable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public init(_ r: CGRect) { self.init(r.minX, r.minY, r.width, r.height) }
    public var cg: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var area: Double { max(0, width) * max(0, height) }
    public var center: Point { Point(x + width / 2, y + height / 2) }
    public var valid: Bool { x.isFinite && y.isFinite && width.isFinite && height.isFinite && width > 1 && height > 1 }
    public func contains(_ p: Point) -> Bool { p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY }
    public func intersection(_ b: Rect) -> Rect {
        Rect(max(x,b.x), max(y,b.y), max(0,min(maxX,b.maxX)-max(x,b.x)), max(0,min(maxY,b.maxY)-max(y,b.y)))
    }
    public func intersects(_ b: Rect) -> Bool { intersection(b).area > 0 }
    public func inset(_ v: Double) -> Rect { Rect(x+v, y+v, width-2*v, height-2*v) }
    public func near(_ b: Rect, tolerance: Double = 3) -> Bool {
        abs(x-b.x) <= tolerance && abs(y-b.y) <= tolerance && abs(width-b.width) <= tolerance && abs(height-b.height) <= tolerance
    }
    public func appKit(mainScreenHeight: Double) -> CGRect { CGRect(x:x, y:mainScreenHeight-maxY, width:width, height:height) }
}

public struct Screen: Hashable, Sendable {
    public var id: UInt32
    public var frame: Rect
    public init(id: UInt32, frame: Rect) { self.id = id; self.frame = frame }
    public static func owner(of rect: Rect, screens: [Screen]) -> Screen? {
        screens.max { a, b in
            let aa = a.frame.intersection(rect).area, ba = b.frame.intersection(rect).area
            return aa == ba ? a.id > b.id : aa < ba
        }.flatMap { $0.frame.intersection(rect).area > 0 ? $0 : nil }
    }
}

public struct Region: Equatable, Sendable {
    public enum Kind: Int, Sendable { case fallback = 0, web = 1, inferred = 2, scroll = 3 }
    public var id: ElementID
    public var frame: Rect
    public var kind: Kind
    public var ancestors: [ElementID]
    public init(id: ElementID, frame: Rect, kind: Kind = .scroll, ancestors: [ElementID] = []) {
        self.id = id; self.frame = frame; self.kind = kind; self.ancestors = ancestors
    }
}

/// AX operability and geometric hit testing do not establish pixel visibility.
public enum VisualVisibility: String, Sendable { case visible, hidden, unknown }

public struct Target: Equatable, Sendable {
    public enum Purpose: Sendable { case control, rowDisclosure }
    public var id: ElementID
    public var frame: Rect
    public var ancestors: [ElementID]
    public var layer: ElementID?
    public var role: String
    public var visualVisibility: VisualVisibility
    public var purpose: Purpose
    public init(id: ElementID, frame: Rect, ancestors: [ElementID] = [], layer: ElementID? = nil, role: String = "AXButton", visualVisibility: VisualVisibility = .unknown, purpose: Purpose = .control) {
        self.id = id; self.frame = frame; self.ancestors = ancestors; self.layer = layer; self.role = role
        self.visualVisibility=visualVisibility; self.purpose=purpose
    }
}

public enum TargetScope {
    public static func filter(_ targets: [Target], regions: [Region], selected: ElementID?, wholeWindow: Bool, overlays: [ElementID: Rect]) -> [Target] {
        targets.filter { target in
            if overlays.contains(where: { id, rect in id != target.layer && rect.contains(target.frame.center) && target.layer == nil }) { return false }
            if target.layer != nil || wholeWindow { return true }
            // Ancestry, not center proximity, decides membership. Parent/child regions can share controls.
            let owners = regions.filter { $0.id == target.id || target.ancestors.contains($0.id) }
            return owners.isEmpty || owners.contains { $0.id == selected }
        }
    }
}

public enum ScrollRoute {
    /// A stable label scope can include fixed chrome. Route within its actual
    /// visible content, using only the nodes from the current traversal.
    public static func point(in region: Region, snapshot: ScanSnapshot) -> Point? {
        let candidates=snapshot.nodes.values.compactMap { entry -> (ScannedNode,Rect)? in
            guard entry.layer == nil,entry.node.scroll || entry.node.listContainer,
                  entry.node.id == region.id || entry.ancestors.contains(region.id),
                  let frame=entry.node.frame else { return nil }
            let visible=frame.intersection(entry.clip).intersection(region.frame)
            return visible.valid ? (entry,visible):nil
        }.sorted { a,b in
            if a.1.area != b.1.area { return a.1.area > b.1.area }
            if a.0.node.scroll != b.0.node.scroll { return a.0.node.scroll }
            return a.0.node.id < b.0.node.id
        }
        var contentID=region.id,contentFrame=region.frame
        let own=snapshot.nodes[region.id]?.node
        if region.kind == .inferred,own?.scroll != true,own?.listContainer != true {
            // A sliced scan may have reached the panel/header but not its list yet.
            // Let it continue; the held-key intent can resume when content is known.
            if let content=candidates.first {
                contentID=content.0.node.id; contentFrame=content.1
            } else if !snapshot.final { return nil }
        }
        let nested=candidates.filter { item in
            item.0.node.scroll && item.0.ancestors.contains(contentID)
        }.map { $0.1 }
        return point(in:contentFrame,targets:snapshot.targets,excluding:nested)
    }
    public static func point(in region: Rect, targets: [Target]) -> Point {
        point(in:region,targets:targets,excluding:[])
    }
    private static func point(in region: Rect, targets: [Target], excluding: [Rect]) -> Point {
        let inside = region.inset(min(16, min(region.width,region.height)/5))
        guard inside.valid else { return region.center }
        let controls = targets.filter { $0.frame.intersects(region) && $0.frame.area < region.area * 0.45 }
        // Start in the content interior, not beside the first toolbar button in
        // traversal order. Avoid smaller independently scrolling descendants.
        let seeds = controls.prefix(48).flatMap { [Point($0.frame.maxX+10, $0.frame.center.y), Point($0.frame.x-10, $0.frame.center.y)] }
        let grid = [0.5,0.3,0.7,0.15,0.85].flatMap { x in [0.5,0.3,0.7,0.15,0.85].map { y in Point(inside.x+inside.width*x, inside.y+inside.height*y) } }
        let safe=(grid+seeds).filter { p in inside.contains(p) && !excluding.contains { $0.inset(-5).contains(p) } }
        return safe.first { p in !controls.contains { $0.frame.inset(-5).contains(p) } } ?? safe.first ?? region.center
    }
}

public enum Endpoint: String, Sendable { case top, bottom }
public struct ScrollExtent: Equatable, Sendable {
    public var value: Double, minimum: Double, maximum: Double
    public init(value: Double, minimum: Double, maximum: Double) { self.value=value; self.minimum=minimum; self.maximum=maximum }
    public func endpoint(direction: Int) -> Endpoint? {
        guard value.isFinite, minimum.isFinite, maximum.isFinite, maximum > minimum, direction != 0 else { return nil }
        let epsilon = (maximum-minimum) * 0.0005
        if direction < 0 && value <= minimum+epsilon { return .top }
        if direction > 0 && value >= maximum-epsilon { return .bottom }
        return nil
    }
}
