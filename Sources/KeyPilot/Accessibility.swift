import AppKit
import ApplicationServices
import KeyPilotCore

/// Confined to the serial AX queue. CFEqual is the identity contract, never names or array offsets.
final class AXRegistry {
    private var next:ElementID=1
    private var buckets:[CFHashCode:[ElementID]]=[:]
    private var elements:[ElementID:AXUIElement]=[:]
    func id(_ element:AXUIElement) -> ElementID {
        let hash=CFHash(element)
        if let known=buckets[hash]?.first(where:{elements[$0].map{CFEqual($0,element)} ?? false}) { return known }
        let id=next; next += 1; elements[id]=element; buckets[hash,default:[]].append(id); return id
    }
    func element(_ id:ElementID) -> AXUIElement? { elements[id] }
    func prune(keeping:Set<ElementID>) {
        elements=elements.filter{keeping.contains($0.key)}
        buckets=buckets.mapValues{$0.filter{elements[$0] != nil}}.filter{!$0.value.isEmpty}
    }
}

struct AXWindow {
    var pid:pid_t
    var id:ElementID
    var frame:Rect
    var extras:[ElementID]
}

final class SystemAXReader: AXReading {
    let registry:AXRegistry
    let application:AXUIElement
    let pid:pid_t
    private let keyboardApplicationPID:()->pid_t?
    private var cache:[ElementID:AXNode]=[:]
    private var visibleRows:[ElementID:[ElementID]]=[:]
    private var priority:Set<ElementID>=[]
    private(set) var calls=0
    private(set) var ipcSeconds=0.0
    var accumulatedIPCSeconds:Double { ipcSeconds }
    init(pid:pid_t, registry:AXRegistry, keyboardApplicationPID:@escaping()->pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }) {
        self.pid=pid; self.registry=registry; application=AXUIElementCreateApplication(pid)
        self.keyboardApplicationPID=keyboardApplicationPID
        AXUIElementSetMessagingTimeout(application,0.04)
    }
    private func measure<T>(_ body:()->T) -> T {
        let start=ProcessInfo.processInfo.systemUptime; defer { calls += 1; ipcSeconds += ProcessInfo.processInfo.systemUptime-start }; return body()
    }
    func attribute(_ element:AXUIElement,_ name:String) -> CFTypeRef? {
        var result:CFTypeRef?
        let error=measure{AXUIElementCopyAttributeValue(element,name as CFString,&result)}
        return error == .success ? result:nil
    }
    func elementAttribute(_ element:AXUIElement,_ name:String) -> AXUIElement? {
        guard let value=attribute(element,name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    func begin() { cache=[:]; visibleRows=[:]; priority=[]; calls=0; ipcSeconds=0 }
    func prewarm() {
        for name in ["AXManualAccessibility","AXEnhancedUserInterface"] {
            var settable:DarwinBoolean=false
            if AXUIElementIsAttributeSettable(application,name as CFString,&settable) == .success && settable.boolValue {
                AXUIElementSetAttributeValue(application,name as CFString,kCFBooleanTrue)
            }
        }
        _=elementAttribute(application,kAXFocusedWindowAttribute)
        _=elementAttribute(application,kAXMainWindowAttribute)
    }
    func currentWindow(includeExtras:Bool=true) -> AXWindow? {
        guard frontmostMatches(), let window=elementAttribute(application,kAXFocusedWindowAttribute) ?? elementAttribute(application,kAXMainWindowAttribute) else { return nil }
        let id=registry.id(window)
        guard let node=readFresh(id), let frame=node.frame, frame.valid else { return nil }
        var extras:[ElementID]=[]
        if includeExtras {
            if let menu=elementAttribute(application,kAXMenuBarAttribute) { extras.append(registry.id(menu)) }
            // Bounded front-application windows only; never crawl other normal documents.
            if let windows=attribute(application,kAXWindowsAttribute) as? [AXUIElement] {
                for other in windows.prefix(32) where !CFEqual(other,window) {
                    let oid=registry.id(other)
                    if let n=read(oid), n.overlay { extras.append(oid) }
                }
            }
            if let focus=elementAttribute(application,kAXFocusedUIElementAttribute) {
                var item:AXUIElement?=focus
                for _ in 0..<16 {
                    guard let current=item else { break }
                    let fid=registry.id(current); priority.insert(fid)
                    if let n=read(fid), n.overlay { extras.append(fid) }
                    if CFEqual(current,window) { break }
                    item=elementAttribute(current,kAXParentAttribute)
                }
            }
        }
        return AXWindow(pid:pid,id:id,frame:frame,extras:Array(Set(extras)).sorted())
    }
    func frontmostPID() -> pid_t? {
        // Workspace identifies the application receiving keyboard events. AX's focused
        // application can disagree during overlays/transitions and must not end navigation.
        guard let actual=keyboardApplicationPID(),actual > 0 else { return nil }
        return actual
    }
    func frontmostMatches() -> Bool { frontmostPID() == pid }
    func read(_ id:ElementID) -> AXNode? { if let cached=cache[id] { return cached }; return readFresh(id) }
    func readFresh(_ id:ElementID) -> AXNode? {
        guard let element=registry.element(id) else { return nil }
        let names=[kAXRoleAttribute,kAXSubroleAttribute,kAXPositionAttribute,kAXSizeAttribute,kAXEnabledAttribute,"AXHidden",kAXVerticalScrollBarAttribute,kAXHorizontalScrollBarAttribute,kAXModalAttribute]
        var result:CFArray?
        let error=measure { AXUIElementCopyMultipleAttributeValues(element,names as CFArray,AXCopyMultipleAttributeOptions(rawValue:0),&result) }
        guard error == .success, let values=result as? [Any], values.count == names.count, let role=values[0] as? String else { return nil }
        var point=CGPoint.zero,size=CGSize.zero
        let position=values[2] as CFTypeRef, dimensions=values[3] as CFTypeRef
        var frame:Rect?
        if CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(dimensions) == AXValueGetTypeID(),
           AXValueGetValue(position as! AXValue,.cgPoint,&point), AXValueGetValue(dimensions as! AXValue,.cgSize,&size) { frame=Rect(point.x,point.y,size.width,size.height) }
        var count:CFIndex=0
        _=measure { AXUIElementGetAttributeValueCount(element,kAXChildrenAttribute as CFString,&count) }
        if ["AXTable","AXOutline"].contains(role), let rows=attribute(element,kAXVisibleRowsAttribute) as? [AXUIElement] {
            visibleRows[id]=rows.map{registry.id($0)}
            count += rows.count
        }
        var pressable=false
        if !AXNode.controls.contains(role), !["AXApplication","AXWindow","AXScrollArea","AXWebArea","AXMenuBar","AXMenu","AXSplitGroup"].contains(role) {
            var actions:CFArray?
            if measure({AXUIElementCopyActionNames(element,&actions)}) == .success, let list=actions as? [String] { pressable=list.contains(kAXPressAction) || list.contains(kAXPickAction) }
        }
        // False/unsupported AXHidden leaves visual visibility unknown. Neither
        // geometry nor a successful hit test promotes it to confirmed visible.
        let node=AXNode(id:id,role:role,subrole:values[1] as? String ?? "",frame:frame,enabled:(values[4] as? NSNumber)?.boolValue ?? true,hidden:(values[5] as? NSNumber)?.boolValue ?? false,modal:(values[8] as? NSNumber)?.boolValue ?? false,pressable:pressable,hasVerticalScroll:CFGetTypeID(values[6] as CFTypeRef) == AXUIElementGetTypeID(),childCount:count)
        cache[id]=node; return node
    }
    func children(_ id:ElementID,offset:Int,limit:Int) -> [ElementID] {
        guard let element=registry.element(id) else { return [] }
        let rows=visibleRows[id] ?? []
        var result=Array(rows.dropFirst(offset).prefix(limit))
        let childOffset=max(0,offset-rows.count)
        if result.count < limit {
            var values:CFArray?
            let count=min(limit-result.count,max(0,(cache[id]?.childCount ?? 0)-rows.count-childOffset))
            if count > 0, measure({AXUIElementCopyAttributeValues(element,kAXChildrenAttribute as CFString,childOffset,count,&values)}) == .success, let children=values as? [AXUIElement] {
                result += children.map { registry.id($0) }
            }
        }
        return result.sorted { priority.contains($0) && !priority.contains($1) }
    }
    func validatedHit(target:Target, window:ElementID, clippingRegions:Set<ElementID>=[]) -> Point? {
        validatedPoint(target:target,window:window,clippingRegions:clippingRegions,hover:false)
    }
    func validatedHover(target:Target, window:ElementID, clippingRegions:Set<ElementID>) -> Point? {
        validatedPoint(target:target,window:window,clippingRegions:clippingRegions,hover:true)
    }
    private func validatedPoint(target:Target,window:ElementID,clippingRegions:Set<ElementID>,hover:Bool) -> Point? {
        guard frontmostMatches(), currentWindow(includeExtras:false)?.id == window, let fresh=readFresh(target.id),
              !fresh.hidden,(hover || (target.purpose == .control && fresh.clickable)),let frame=fresh.frame else { return nil }
        let common=frame.intersection(target.frame)
        guard common.valid, common.area >= min(frame.area,target.frame.area)*0.15 else { return nil }
        // Recheck clipping ancestors so a control scrolled out of view cannot be clicked at an old location.
        var hit=common
        let clippingAncestors=target.layer.map { layer in Array(target.ancestors.drop(while:{$0 != layer})) } ?? target.ancestors
        for ancestor in clippingAncestors.suffix(24) {
            let required=clippingRegions.contains(ancestor)
            guard let node=readFresh(ancestor) else { if required { return nil }; continue }
            if node.scroll || node.listContainer || node.role == "AXWebArea" || node.overlay || required {
                guard let clip=node.frame else { if required { return nil }; continue }
                hit=hit.intersection(clip)
            }
        }
        guard hit.valid else { return nil }
        let started=ProcessInfo.processInfo.systemUptime
        let points=[hit.center,Point(hit.x+min(8,hit.width/4),hit.center.y),Point(hit.maxX-min(8,hit.width/4),hit.center.y),Point(hit.center.x,hit.y+min(6,hit.height/4)),Point(hit.center.x,hit.maxY-min(6,hit.height/4))]
        for point in points {
            if ProcessInfo.processInfo.systemUptime-started > 0.060 { break }
            var found:AXUIElement?
            guard measure({AXUIElementCopyElementAtPosition(application,Float(point.x),Float(point.y),&found)}) == .success,let found else { continue }
            var cursor:AXUIElement?=found
            for _ in 0..<12 {
                guard let element=cursor else { break }
                let id=registry.id(element)
                if id == target.id { return point }
                // A nested independent button is not a safe click point for its containing row.
                if !hover,let node=readFresh(id),node.clickable,let frame=node.frame,!frame.near(hit) { break }
                cursor=elementAttribute(element,kAXParentAttribute)
                if ProcessInfo.processInfo.systemUptime-started > 0.060 { break }
            }
        }
        return nil
    }
    func extent(region:ElementID) -> ScrollExtent? {
        guard let element=registry.element(region) else { return nil }
        if let bar=elementAttribute(element,kAXVerticalScrollBarAttribute),
           let value=attribute(bar,kAXValueAttribute) as? NSNumber,
           let low=attribute(bar,kAXMinValueAttribute) as? NSNumber,
           let high=attribute(bar,kAXMaxValueAttribute) as? NSNumber {
            return ScrollExtent(value:value.doubleValue,minimum:low.doubleValue,maximum:high.doubleValue)
        }
        // Bounded overflow geometry fallback. Only a content container spanning beyond its viewport is evidence.
        guard let viewport=readFresh(region)?.frame else { return nil }
        let start=ProcessInfo.processInfo.systemUptime
        var work=[(region,0)], cursor=0, checked=0
        while cursor < work.count && checked < 6 && ProcessInfo.processInfo.systemUptime-start < 0.060 {
            let (id,depth)=work[cursor]; cursor += 1
            guard depth < 2 else { continue }
            for child in children(id,offset:0,limit:6).prefix(6) {
                checked += 1
                guard let n=readFresh(child), n.listContainer || ["AXGroup","AXWebArea"].contains(n.role), let content=n.frame else { continue }
                if content.height > viewport.height+4 && content.width >= viewport.width*0.8 && content.x <= viewport.x+4 && content.maxX >= viewport.maxX-4 {
                    return ScrollExtent(value:viewport.y-content.y,minimum:0,maximum:content.height-viewport.height)
                }
                work.append((child,depth+1))
            }
        }
        return nil
    }
    func jump(region:ElementID,top:Bool) -> Bool {
        guard let element=registry.element(region), let bar=elementAttribute(element,kAXVerticalScrollBarAttribute), let limit=attribute(bar,top ? kAXMinValueAttribute:kAXMaxValueAttribute) else { return false }
        return AXUIElementSetAttributeValue(bar,kAXValueAttribute as CFString,limit) == .success
    }
}

final class AXObservation {
    private var observer:AXObserver?
    private var observed:[(AXUIElement,String)]=[]
    private let changed:()->Void
    init(changed:@escaping()->Void) { self.changed=changed }
    func install(reader:SystemAXReader, window:ElementID, nodes:[ElementID:ScannedNode]) {
        stop()
        var value:AXObserver?
        guard AXObserverCreate(reader.pid,{ _,_,_,context in
            guard let context else { return }; Unmanaged<AXObservation>.fromOpaque(context).takeUnretainedValue().changed()
        },&value) == .success, let value else { return }
        observer=value
        let context=Unmanaged.passUnretained(self).toOpaque()
        let appNames=[kAXFocusedWindowChangedNotification,kAXMainWindowChangedNotification,kAXFocusedUIElementChangedNotification,kAXWindowCreatedNotification]
        for name in appNames { add(value,reader.application,name,context) }
        if let element=reader.registry.element(window) {
            for name in [kAXMovedNotification,kAXResizedNotification,kAXUIElementDestroyedNotification,kAXSelectedChildrenChangedNotification,"AXLayoutChanged","AXValueChanged"] { add(value,element,name,context) }
        }
        let structural=nodes.values.filter { $0.node.scroll || $0.node.listContainer || $0.node.landmarkContainer || ["AXSplitGroup","AXTabGroup"].contains($0.node.role) }.sorted{$0.node.id < $1.node.id}.prefix(64)
        for item in structural {
            if let element=reader.registry.element(item.node.id) { for name in [kAXSelectedChildrenChangedNotification,kAXResizedNotification,"AXLayoutChanged"] { add(value,element,name,context) } }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(value),.commonModes)
    }
    private func add(_ observer:AXObserver,_ element:AXUIElement,_ name:String,_ context:UnsafeMutableRawPointer) {
        if AXObserverAddNotification(observer,element,name as CFString,context) == .success { observed.append((element,name)) }
    }
    func stop() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observer),.commonModes); for (element,name) in observed { AXObserverRemoveNotification(observer,element,name as CFString) } }
        observed=[]; observer=nil
    }
    deinit { stop() }
}
