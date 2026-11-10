import Foundation

public struct AXNode: Sendable {
    public var id:ElementID
    public var role:String
    public var subrole:String
    public var frame:Rect?
    public var enabled:Bool
    public var visualVisibility:VisualVisibility
    public var hidden:Bool { visualVisibility == .hidden }
    public var modal:Bool
    public var pressable:Bool
    public var hasVerticalScroll:Bool
    public var childCount:Int
    public init(id:ElementID, role:String="AXGroup", subrole:String="", frame:Rect?=nil, enabled:Bool=true, hidden:Bool=false, modal:Bool=false, pressable:Bool=false, hasVerticalScroll:Bool=false, childCount:Int=0, visualVisibility:VisualVisibility = .unknown) {
        self.id=id; self.role=role; self.subrole=subrole; self.frame=frame; self.enabled=enabled
        self.visualVisibility=hidden ? .hidden:visualVisibility
        self.modal=modal; self.pressable=pressable; self.hasVerticalScroll=hasVerticalScroll; self.childCount=childCount
    }
    public var overlay:Bool { modal || ["AXSheet","AXDialog","AXMenu","AXPopover"].contains(role) || ["AXDialog","AXSystemDialog","AXFloatingWindow"].contains(subrole) }
    public var scroll:Bool { role == "AXScrollArea" || hasVerticalScroll }
    public var listContainer:Bool { ["AXList","AXOutline","AXTable","AXBrowser"].contains(role) || subrole == "AXContentList" }
    public var landmarkContainer:Bool { role == "AXGroup" && ["AXLandmarkNavigation","AXLandmarkComplementary","AXLandmarkMain"].contains(subrole) }
    public static let controls:Set<String>=["AXButton","AXLink","AXCheckBox","AXRadioButton","AXMenuItem","AXMenuBarItem","AXTextField","AXTextArea","AXComboBox","AXSlider","AXDisclosureTriangle","AXRow","AXTab","AXSwitch","AXPopUpButton","AXIncrementor","AXColorWell"]
    public var operable:Bool { enabled && (Self.controls.contains(role) || pressable) }
    public var clickable:Bool { operable && !hidden }
}
public protocol AXReading: AnyObject {
    var accumulatedIPCSeconds:Double { get }
    func read(_ id:ElementID) -> AXNode?
    func children(_ id:ElementID, offset:Int, limit:Int) -> [ElementID]
}
public extension AXReading { var accumulatedIPCSeconds:Double { 0 } }
public struct ScannedNode: Sendable {
    public var node:AXNode
    public var ancestors:[ElementID]
    public var clip:Rect
    public var layer:ElementID?
}
public struct ScanSnapshot: Sendable {
    public var nodes:[ElementID:ScannedNode]
    public var targets:[Target]
    public var regions:[Region]
    public var overlays:[ElementID:Rect]
    public var final:Bool
    public var exhaustive:Bool
    public var count:Int
    public var workingSeconds:Double
    public init(nodes:[ElementID:ScannedNode],targets:[Target],regions:[Region],overlays:[ElementID:Rect],final:Bool,exhaustive:Bool,count:Int,workingSeconds:Double) {
        self.nodes=nodes; self.targets=targets; self.regions=regions; self.overlays=overlays; self.final=final; self.exhaustive=exhaustive; self.count=count; self.workingSeconds=workingSeconds
    }
}

/// One sliced traversal discovers targets, containers and ancestry. The reader is injectable for regressions.
public final class ScanTraversal {
    private struct Work {
        var id:ElementID, ancestors:[ElementID], clip:Rect, layer:ElementID?, offset:Int?
    }
    private let reader:AXReading
    private let root:ElementID
    private let window:Rect
    private var queue:[Work]=[]
    private var cursor=0
    private var visited:Set<ElementID>=[]
    private var nodes:[ElementID:ScannedNode]=[:]
    private var targets:[Target]=[]
    private var overlays:[ElementID:Rect]=[:]
    private var seconds=0.0
    public private(set) var resolutionSeconds=0.0
    public private(set) var localSeconds=0.0
    public private(set) var computationSeconds=0.0
    private var failed=false
    private var first=true
    public private(set) var finished=false
    public init(reader:AXReading, root:ElementID, window:Rect, additionalRoots:[ElementID]=[], priorityRoots:[ElementID]=[]) {
        self.reader=reader; self.root=root; self.window=window
        // Priority is expressed through child ordering by the reader, never by discarding ancestor paths.
        queue=([root]+additionalRoots).map { Work(id:$0,ancestors:[],clip:window,layer:nil,offset:nil) }
    }
    public func step(cancelled:() -> Bool = {false}) -> ScanSnapshot {
        let start=ProcessInfo.processInfo.systemUptime
        let ipcBefore=reader.accumulatedIPCSeconds
        let budget=first ? 0.012:0.040
        var items=0
        while cursor < queue.count && items < 160 && ProcessInfo.processInfo.systemUptime-start < budget && !cancelled() {
            if visited.count >= 7000 || targets.count >= 2500 || seconds + ProcessInfo.processInfo.systemUptime-start >= 1.5 { failed=true; finished=true; break }
            let work=queue[cursor]; cursor += 1; items += 1
            guard work.ancestors.count <= 80 else { failed=true; continue }
            if let offset=work.offset {
                let children=reader.children(work.id,offset:offset,limit:128)
                if children.isEmpty && offset < (nodes[work.id]?.node.childCount ?? 0) { failed=true }
                // Breadth first, with only bounded child batches. Every sibling stays in the worklist.
                queue += children.map { Work(id:$0,ancestors:work.ancestors,clip:work.clip,layer:work.layer,offset:nil) }
                if children.count == 128 { queue.append(Work(id:work.id,ancestors:work.ancestors,clip:work.clip,layer:work.layer,offset:offset+128)) }
                continue
            }
            guard visited.insert(work.id).inserted else { continue }
            guard let node=reader.read(work.id) else { failed=true; continue }
            if node.hidden { continue }
            var clip=work.clip, layer=work.layer
            if node.overlay, let frame=node.frame, frame.valid { clip=frame; layer=node.id; overlays[node.id]=frame }
            // A menu bar is an attached application surface, outside the document window.
            if node.role == "AXMenuBar", let frame=node.frame { clip=frame }
            let entry=ScannedNode(node:node,ancestors:work.ancestors,clip:clip,layer:layer)
            nodes[node.id]=entry
            if node.clickable, let frame=node.frame {
                let hit=frame.intersection(clip)
                if hit.valid { targets.append(Target(id:node.id,frame:hit,ancestors:work.ancestors,layer:layer,role:node.role,visualVisibility:node.visualVisibility)) }
            }
            if node.scroll || node.listContainer || node.role == "AXWebArea", let frame=node.frame { clip=frame.intersection(clip) }
            if node.childCount > 0 {
                queue.append(Work(id:node.id,ancestors:work.ancestors+[node.id],clip:clip,layer:layer,offset:0))
            }
        }
        let walked=ProcessInfo.processInfo.systemUptime-start
        seconds += walked
        first=false
        if cursor >= queue.count { finished=true }
        let resolutionStart=ProcessInfo.processInfo.systemUptime
        let regions=RegionDiscovery.resolve(nodes:nodes,root:root,window:window)
        let resolved=ProcessInfo.processInfo.systemUptime-resolutionStart
        let dedupeStart=ProcessInfo.processInfo.systemUptime
        let unique=deduplicate(targets,regions:regions)
        localSeconds += ProcessInfo.processInfo.systemUptime-dedupeStart; resolutionSeconds += resolved
        seconds += ProcessInfo.processInfo.systemUptime-resolutionStart
        computationSeconds += max(0,ProcessInfo.processInfo.systemUptime-start-(reader.accumulatedIPCSeconds-ipcBefore))
        return ScanSnapshot(nodes:nodes,targets:unique,regions:regions,overlays:overlays,final:finished,exhaustive:finished && !failed,count:visited.count,workingSeconds:seconds)
    }
    private func deduplicate(_ targets:[Target],regions:[Region]) -> [Target] {
        struct Box:Hashable { var rect:Rect; var layer:ElementID? }
        let viewports=Dictionary(regions.map{($0.id,$0.frame)},uniquingKeysWith:{$1})
        var groups:[Box:[Target]]=[:], result:[Target]=[]
        for var target in targets {
            // Inferred panels also bound their moving list content. Floating surfaces
            // have their own clip and must not inherit the panel behind them.
            if target.layer == nil {
                for ancestor in target.ancestors {
                    if let viewport=viewports[ancestor] { target.frame=target.frame.intersection(viewport) }
                }
            }
            guard target.frame.valid else { continue }
            let key=Box(rect:target.frame,layer:target.layer)
            let matches=groups[key,default:[]]
            if matches.prefix(8).contains(where:{ target.ancestors.contains($0.id) || $0.ancestors.contains(target.id) }) { continue }
            groups[key,default:[]].append(target); result.append(target)
        }
        return result
    }
}

public enum RegionDiscovery {
    public static func resolve(nodes:[ElementID:ScannedNode], root:ElementID, window:Rect) -> [Region] {
        var candidates:[Region]=[]
        var siblings:[ElementID:[ScannedNode]]=[:]
        let containerRoles:Set<String>=["AXGroup","AXSplitGroup","AXOutline","AXTable","AXList","AXBrowser","AXScrollArea","AXWebArea"]
        func visible(_ entry:ScannedNode) -> Rect? { entry.node.frame.map{$0.intersection(entry.clip).intersection(window)} }
        func hasOwnScrollViewport(_ entry:ScannedNode,frame:Rect) -> Bool {
            // A document-wide scroll ancestor does not own an independent narrow sidebar.
            // Suppress a semantic container only when a scroll viewport spans the same column.
            entry.ancestors.contains { id in
                guard let ancestor=nodes[id],ancestor.node.scroll,let viewport=visible(ancestor) else { return false }
                return frame.width >= viewport.width*0.85 && frame.intersection(viewport).width >= frame.width*0.95
            }
        }
        for entry in nodes.values {
            guard entry.layer == nil,let frame=visible(entry) else { continue }
            guard frame.width >= 72,frame.height >= 64,frame.area >= window.area*0.018 else { continue }
            if entry.node.scroll || entry.node.role == "AXWebArea" {
                candidates.append(Region(id:entry.node.id,frame:frame,kind:entry.node.scroll ? .scroll:.web,ancestors:entry.ancestors))
            } else if entry.node.listContainer || entry.node.landmarkContainer,
                      frame.width >= 96,frame.height >= max(180,window.height*0.35),
                      !hasOwnScrollViewport(entry,frame:frame) {
                // Semantic lists and navigation/main landmarks need no matching-height peer.
                candidates.append(Region(id:entry.node.id,frame:frame,kind:.inferred,ancestors:entry.ancestors))
            }
            guard containerRoles.contains(entry.node.role),frame.width >= 96,frame.height >= 120 else { continue }
            // Normalize only transparent wrappers. Retain real AX identities and ancestry.
            // This joins columns at a common layout parent without scanning descendants again.
            let ancestry=entry.ancestors
            var index=ancestry.count-1,skipped=0
            while index > 0,skipped < 16,let wrapper=nodes[ancestry[index]],wrapper.node.role == "AXGroup",!wrapper.node.landmarkContainer {
                if let bounds=visible(wrapper),frame.intersection(bounds).area < bounds.area*0.90 { break }
                index -= 1; skipped += 1
            }
            if index >= 0 { siblings[ancestry[index],default:[]].append(entry) }
        }
        for (parent,children) in siblings {
            guard let p=nodes[parent],let parentFrame=visible(p),parentFrame.area >= window.area*0.25 else { continue }
            let list=Array(children.sorted { a,b in
                let af=visible(a)!,bf=visible(b)!
                return af.x != bf.x ? af.x < bf.x:(af.y != bf.y ? af.y < bf.y:a.node.id < b.node.id)
            }.prefix(128))
            for i in list.indices {
                for j in (i+1)..<min(i+5,list.count) {
                    let a=visible(list[i])!,b=visible(list[j])!
                    guard !list[i].ancestors.contains(list[j].node.id),!list[j].ancestors.contains(list[i].node.id) else { continue }
                    let coverage=(a.area+b.area-a.intersection(b).area)/max(1,parentFrame.area)
                    guard coverage >= 0.48 else { continue }
                    let verticalOverlap=max(0,min(a.maxY,b.maxY)-max(a.y,b.y))/max(1,min(a.height,b.height))
                    let horizontalOverlap=max(0,min(a.maxX,b.maxX)-max(a.x,b.x))/max(1,min(a.width,b.width))
                    let sideBySide=verticalOverlap >= 0.65 && horizontalOverlap < 0.12 && min(a.height,b.height) >= max(180,parentFrame.height*0.55)
                    let stacked=p.node.role == "AXSplitGroup" && horizontalOverlap >= 0.65 && verticalOverlap < 0.12 && min(a.area,b.area) >= parentFrame.area*0.08
                    if sideBySide || stacked {
                        for item in [list[i],list[j]] { candidates.append(Region(id:item.node.id,frame:visible(item)!,kind:.inferred,ancestors:item.ancestors)) }
                    }
                }
            }
        }
        // AXList can describe a moving section of a sidebar, not its viewport.
        // Keep the already-discovered enclosing column's identity as sections scroll
        // in and out. Native outlines/tables and explicit scroll views remain independent.
        let panels=Dictionary(candidates.filter { item in
            guard let node=nodes[item.id]?.node else { return false }
            return item.kind == .scroll || (item.kind == .inferred && node.role == "AXGroup" && !node.listContainer)
        }.map{($0.id,$0)},uniquingKeysWith:{a,b in a.kind.rawValue >= b.kind.rawValue ? a:b})
        candidates.removeAll { item in
            guard let node=nodes[item.id]?.node,!node.scroll,
                  node.role == "AXList" || node.subrole == "AXContentList" else { return false }
            return item.ancestors.contains { id in
                guard let panel=panels[id] else { return false }
                return item.frame.width >= panel.frame.width*0.75 && item.frame.intersection(panel.frame).width >= item.frame.width*0.95
            }
        }
        // Quantized rectangles avoid quadratic alias comparisons for deeply wrapped web documents.
        struct Bucket:Hashable { var x:Int,y:Int,w:Int,h:Int }
        var buckets:[Bucket:[Region]]=[:], unique:[Region]=[]
        for item in candidates.sorted(by:{ $0.kind == $1.kind ? $0.id < $1.id : $0.kind.rawValue > $1.kind.rawValue }) {
            let r=item.frame, key=Bucket(x:Int((r.x/4).rounded()),y:Int((r.y/4).rounded()),w:Int((r.width/4).rounded()),h:Int((r.height/4).rounded()))
            if buckets[key,default:[]].prefix(8).contains(where:{$0.frame.near(r)}) { continue }
            buckets[key,default:[]].append(item); unique.append(item)
        }
        // Only descendants of a wrapping page can make it redundant; at most 32 near-size interiors.
        let byID=Dictionary(unique.map{($0.id,$0)},uniquingKeysWith:{$1})
        var descendants:[ElementID:[Region]]=[:]
        for item in unique { for ancestor in item.ancestors where byID[ancestor] != nil { if descendants[ancestor,default:[]].count < 32 { descendants[ancestor,default:[]].append(item) } } }
        unique=unique.filter { outer in
            if outer.kind == .inferred,!((nodes[outer.id]?.node.listContainer) ?? false),
               (descendants[outer.id] ?? []).contains(where:{ child in
                   let semantic=nodes[child.id]?.node.listContainer == true || nodes[child.id]?.node.landmarkContainer == true || child.kind == .scroll || child.kind == .web
                   return semantic && child.frame.width >= outer.frame.width*0.85 && child.frame.height >= outer.frame.height*0.65 && child.frame.intersection(outer.frame).area >= outer.frame.area*0.68
               }) { return false }
            let inside=(descendants[outer.id] ?? []).filter { $0.frame.area < outer.frame.area*0.96 && $0.frame.area > outer.frame.area*0.07 }.sorted{$0.frame.x < $1.frame.x}
            var accepted:[Rect]=[]
            for child in inside where !accepted.contains(where:{$0.intersection(child.frame).area > child.frame.area*0.2}) { accepted.append(child.frame) }
            return accepted.count < 2 || accepted.reduce(0,{$0+$1.area}) < outer.frame.area*0.72
        }
        if unique.isEmpty { unique=[Region(id:root,frame:window,kind:.fallback)] }
        return unique.sorted { a,b in abs(a.frame.x-b.frame.x) > 3 ? a.frame.x < b.frame.x : (abs(a.frame.y-b.frame.y) > 3 ? a.frame.y < b.frame.y : a.id < b.id) }
    }
}
