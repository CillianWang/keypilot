import Foundation

/// A presentation policy, not a detector for CSS hover or opacity.
public struct RowActionGroup: Sendable {
    public enum Kind:String,Sendable { case semantic,primary,repeated,peers }
    public var row:Target
    public var anchor:Target
    public var actions:Set<ElementID>
    public var kind:Kind = .semantic
}

public struct RowDisclosure: Sendable {
    public var groups:[RowActionGroup]
    public var candidateCount:Int
    public var actionCount:Int
    public var unassignedActionCount:Int
    public var structureCounts:[String:Int]
    public init(targets:[Target],nodes:[ElementID:ScannedNode],regions:[Region]) {
        let regionIDs=Set(regions.map(\.id))
        let viewports=Dictionary(regions.map{($0.id,$0.frame)},uniquingKeysWith:{$1})
        func visible(_ entry:ScannedNode) -> Rect? {
            guard entry.layer == nil,!entry.node.hidden,let frame=entry.node.frame else { return nil }
            var hit=frame.intersection(entry.clip)
            for id in entry.ancestors { if let viewport=viewports[id] { hit=hit.intersection(viewport) } }
            return hit.valid ? hit:nil
        }
        // All inference uses this scan's structure. No new AX reads, names or pixels.
        let frames=nodes.compactMapValues(visible)
        let primaryRoles:Set<String>=["AXRow","AXButton","AXLink","AXGroup"]
        let actionRoles:Set<String>=["AXButton","AXPopUpButton","AXMenuButton"]
        let formRoles:Set<String>=["AXTextField","AXTextArea","AXComboBox","AXSlider","AXCheckBox","AXRadioButton","AXSwitch"]
        // AXPress/AXPick can expose a button as a Group, Image or another role.
        // Keep richer control/content semantics even when they also offer AXPress.
        let preservedRoles=AXNode.controls.subtracting(actionRoles).union(["AXStaticText","AXHeading"])
        func isAction(_ target:Target) -> Bool {
            actionRoles.contains(target.role) ||
                (!preservedRoles.contains(target.role) && nodes[target.id]?.node.pressable == true)
        }
        func isPrimary(_ target:Target) -> Bool {
            primaryRoles.contains(target.role) ||
                (!formRoles.contains(target.role) && nodes[target.id]?.node.pressable == true)
        }
        let ordinary=targets.filter{$0.layer == nil}
        var descendants:[ElementID:[Target]]=[:]
        for target in ordinary {
            for id in target.ancestors+[target.id] { descendants[id,default:[]].append(target) }
        }
        var forms:Set<ElementID>=[],body:[ElementID:Rect]=[:]
        for entry in nodes.values where frames[entry.node.id] != nil {
            if formRoles.contains(entry.node.role) { forms.formUnion(entry.ancestors+[entry.node.id]) }
            guard entry.node.role == "AXStaticText",let frame=frames[entry.node.id] else { continue }
            for id in entry.ancestors.reversed() {
                // Text used as a button label is not independent row content.
                guard nodes[id]?.node.operable != true else { break }
                if frame.area > (body[id]?.area ?? 0) { body[id]=frame }
            }
        }
        func rowTarget(_ entry:ScannedNode) -> Target? {
            guard !regionIDs.contains(entry.node.id),let frame=frames[entry.node.id] else { return nil }
            return Target(id:entry.node.id,frame:frame,ancestors:entry.ancestors,role:entry.node.role,visualVisibility:entry.node.visualVisibility,purpose:.rowDisclosure)
        }
        func inToolbar(_ entry:ScannedNode) -> Bool {
            ([entry.node.id]+entry.ancestors).contains { ["AXToolbar","AXMenuBar"].contains(nodes[$0]?.node.role ?? "") }
        }
        func genericRow(_ entry:ScannedNode) -> Target? {
            guard primaryRoles.contains(entry.node.role) || entry.node.pressable,
                  !entry.node.scroll,!entry.node.listContainer,!entry.node.landmarkContainer,
                  !forms.contains(entry.node.id),!inToolbar(entry) else { return nil }
            return rowTarget(entry)
        }
        func compactAction(_ target:Target,in row:Target) -> Bool {
            isAction(target) && target.id != row.id &&
            target.frame.width <= row.frame.width*0.50 && target.frame.area <= row.frame.area*0.45 &&
            target.frame.intersection(row.frame).area >= target.frame.area*0.80
        }
        func primary(in items:[Target],row:Target,requireHeight:Bool) -> Target? {
            items.first{$0.id == row.id} ?? items.filter {
                isPrimary($0) && $0.frame.width >= row.frame.width*0.60 &&
                (!requireHeight || $0.frame.height >= row.frame.height*0.60)
            }.sorted { $0.frame.area == $1.frame.area ? $0.id < $1.id:$0.frame.area > $1.frame.area }.first
        }
        var semanticRows:[ElementID:Target]=[:]
        func addSemantic(_ entry:ScannedNode) {
            if let row=rowTarget(entry) { semanticRows[row.id]=row }
        }
        for entry in nodes.values where entry.node.role == "AXRow" || entry.node.role == "AXListItem" || entry.node.subrole == "AXListItem" || entry.node.subrole == "AXOutlineRow" {
            addSemantic(entry)
        }
        for target in ordinary {
            // A list item may be an ordinary AXGroup wrapping its primary link
            // and secondary buttons. Skip wrappers spanning the entire list.
            guard let listIndex=target.ancestors.lastIndex(where:{ nodes[$0]?.node.listContainer == true }),
                  let listFrame=frames[target.ancestors[listIndex]] else { continue }
            for id in target.ancestors.dropFirst(listIndex+1) {
                guard let entry=nodes[id],entry.node.role == "AXGroup",!entry.node.landmarkContainer,
                      let frame=frames[id],frame.width >= listFrame.width*0.55,
                      frame.height < listFrame.height*0.85 else { continue }
                addSemantic(entry); break
            }
        }
        var owned:[ElementID:[Target]]=[:]
        for target in ordinary {
            if let row=([target.id]+target.ancestors.reversed()).first(where:{semanticRows[$0] != nil}) { owned[row,default:[]].append(target) }
        }
        var candidates:[ElementID:RowActionGroup]=[:]
        for row in semanticRows.values {
            let items=owned[row.id] ?? []
            let anchor=primary(in:items,row:row,requireHeight:false) ?? row
            let actions=Set(items.filter { $0.id != anchor.id && isAction($0) }.map(\.id))
            if !actions.isEmpty { candidates[row.id]=RowActionGroup(row:row,anchor:anchor,actions:actions) }
        }
        func withinSemanticRow(_ entry:ScannedNode) -> Bool {
            semanticRows[entry.node.id] != nil || entry.ancestors.contains{semanticRows[$0] != nil}
        }
        // Generic groups and clickable parents can expose a row without AXList/AXRow.
        // A dominant primary must share the row's vertical band with compact actions.
        var contentRows:[ElementID:Target]=[:]
        var genericWithActions=0,dominantPrimaries=0
        for entry in nodes.values {
            guard !withinSemanticRow(entry),let row=genericRow(entry),let items=descendants[row.id] else { continue }
            let actions=items.filter{compactAction($0,in:row)}
            guard !actions.isEmpty else { continue }
            genericWithActions += 1
            if let anchor=primary(in:items,row:row,requireHeight:true) {
                dominantPrimaries += 1
                let sameBand=actions.filter { action in
                    action.id != anchor.id && action.frame.width <= anchor.frame.width*0.50 &&
                    max(0,min(action.frame.maxY,anchor.frame.maxY)-max(action.frame.y,anchor.frame.y)) >= action.frame.height*0.50
                }
                // Do not turn a wrapper containing several primary rows into one row.
                let otherPrimary=items.contains { item in
                    item.id != anchor.id && isPrimary(item) && item.frame.width >= row.frame.width*0.60 &&
                    !item.ancestors.contains(anchor.id) && !anchor.ancestors.contains(item.id)
                }
                if !sameBand.isEmpty,!otherPrimary {
                    candidates[row.id]=RowActionGroup(row:row,anchor:anchor,actions:Set(sameBand.map(\.id)),kind:.primary)
                }
            }
            if let text=body[row.id],text.width >= row.frame.width*0.25,
               row.frame.height >= (actions.map(\.frame.height).max() ?? 0)*1.25 {
                contentRows[row.id]=row
            }
        }
        // Repeated content blocks may be non-clickable and contain an action toolbar.
        // Normalize only transparent/single-child wrappers, retaining real AX row IDs.
        func peerParent(_ row:Target) -> ElementID? {
            for id in row.ancestors.reversed() {
                guard let entry=nodes[id] else { return nil }
                if entry.node.role == "AXGroup",!entry.node.operable,!entry.node.landmarkContainer,!regionIDs.contains(id),
                   frames[id] == nil || entry.node.childCount == 1 || frames[id]!.near(row.frame) { continue }
                return id
            }
            return nil
        }
        func verticallyRepeated(_ a:Target,_ b:Target) -> Bool {
            let overlap=max(0,min(a.frame.maxY,b.frame.maxY)-max(a.frame.y,b.frame.y))
            let horizontal=max(0,min(a.frame.maxX,b.frame.maxX)-max(a.frame.x,b.frame.x))
            return overlap <= min(a.frame.height,b.frame.height)*0.10 &&
                horizontal >= max(a.frame.width,b.frame.width)*0.65 &&
                !a.ancestors.contains(b.id) && !b.ancestors.contains(a.id)
        }
        var siblings:[ElementID:[Target]]=[:]
        for row in contentRows.values {
            if let parent=peerParent(row),let frame=frames[parent],row.frame.width >= frame.width*0.45 {
                siblings[parent,default:[]].append(row)
            }
        }
        for rows in siblings.values {
            let sorted=rows.sorted { $0.frame.y == $1.frame.y ? $0.id < $1.id:$0.frame.y < $1.frame.y }
            for i in sorted.indices where candidates[sorted[i].id] == nil {
                let row=sorted[i]
                guard sorted[max(0,i-4)..<min(sorted.count,i+5)].contains(where:{verticallyRepeated(row,$0)}) else { continue }
                let actions=Set((descendants[row.id] ?? []).filter{compactAction($0,in:row)}.map(\.id))
                candidates[row.id]=RowActionGroup(row:row,anchor:row,actions:actions,kind:.repeated)
            }
        }
        // Some trees flatten each row's primary and action buttons into sibling nodes.
        // Require multiple wide, vertically repeated primaries under a shared container;
        // attach only small buttons within an unambiguous primary's vertical band.
        let containerRoles:Set<String>=["AXGroup","AXScrollArea","AXWebArea","AXList","AXOutline","AXTable"]
        let existingAnchors=Set(candidates.values.map(\.anchor.id))
        for id in descendants.keys.sorted(by:{ a,b in
            let ad=nodes[a]?.ancestors.count ?? 0,bd=nodes[b]?.ancestors.count ?? 0
            return ad == bd ? a < b:ad > bd
        }) {
            let items=descendants[id] ?? []
            guard let entry=nodes[id],containerRoles.contains(entry.node.role),!inToolbar(entry),!forms.contains(id),
                  !withinSemanticRow(entry),let frame=frames[id] else { continue }
            let primaries=items.filter { item in
                isPrimary(item) && item.id != id && item.frame.width >= frame.width*0.55 &&
                item.frame.height <= frame.height*0.45 && candidates[item.id] == nil && !existingAnchors.contains(item.id)
            }.sorted{$0.frame.y == $1.frame.y ? $0.id < $1.id:$0.frame.y < $1.frame.y}
            guard primaries.count >= 2 else { continue }
            for i in primaries.indices {
                let anchor=primaries[i]
                guard primaries[max(0,i-4)..<min(primaries.count,i+5)].contains(where:{verticallyRepeated(anchor,$0)}) else { continue }
                let actions=items.filter { action in
                    isAction(action) && action.id != anchor.id &&
                    action.frame.width <= anchor.frame.width*0.50 && action.frame.area <= anchor.frame.area*0.45 &&
                    action.frame.center.y >= anchor.frame.y && action.frame.center.y <= anchor.frame.maxY &&
                    action.frame.intersection(frame).area >= action.frame.area*0.80 &&
                    // Nearby unrelated columns cannot donate actions to this row.
                    max(anchor.frame.x-action.frame.maxX,action.frame.x-anchor.frame.maxX) <= anchor.frame.width*0.35 &&
                    !primaries.contains { other in
                        other.id != anchor.id && other.frame.contains(action.frame.center) && !other.ancestors.contains(anchor.id)
                    }
                }
                guard !actions.isEmpty else { continue }
                var row=anchor; row.purpose = .rowDisclosure
                let proposed=RowActionGroup(row:row,anchor:anchor,actions:Set(actions.map(\.id)),kind:.peers)
                if candidates[row.id] == nil { candidates[row.id]=proposed }
            }
        }
        candidateCount=candidates.count
        // Several transparent wrappers can nominate the same clickable primary.
        // Publish one disclosure entry and let it reveal all of that primary's actions.
        var byAnchor:[ElementID:RowActionGroup]=[:]
        for group in candidates.values.sorted(by:{ $0.row.id < $1.row.id }) {
            if var prior=byAnchor[group.anchor.id] {
                prior.actions.formUnion(group.actions)
                if prior.row.ancestors.contains(group.row.id) { prior.row=group.row; prior.kind=group.kind }
                byAnchor[group.anchor.id]=prior
            } else { byAnchor[group.anchor.id]=group }
        }
        // Prefer the nearest real row. An enclosing content block must never fold a
        // nested row's primary or own its buttons a second time.
        let anchors=Set(byAnchor.keys)
        var claimed:Set<ElementID>=[],result:[RowActionGroup]=[]
        for var group in byAnchor.values.sorted(by:{ a,b in
            if a.row.ancestors.count != b.row.ancestors.count { return a.row.ancestors.count > b.row.ancestors.count }
            if a.row.frame.area != b.row.frame.area { return a.row.frame.area < b.row.frame.area }
            return a.row.id < b.row.id
        }) {
            group.actions.subtract(claimed); group.actions.subtract(anchors)
            guard !group.actions.isEmpty else { continue }
            claimed.formUnion(group.actions); result.append(group)
        }
        groups=result.sorted{$0.row.id < $1.row.id}
        let actionIDs=Set(ordinary.filter(isAction).map(\.id))
        actionCount=actionIDs.count
        let unassigned=actionIDs.subtracting(claimed).subtracting(Set(groups.map(\.anchor.id)))
        unassignedActionCount=unassigned.count
        let pressActions=Set(ordinary.filter{isAction($0) && !actionRoles.contains($0.role)}.map(\.id))
        let semanticItems=owned.values.flatMap{$0}
        structureCounts=["semantic_rows":semanticRows.count,"semantic_rows_with_targets":owned.count,
                         "semantic_owned_targets":semanticItems.count,"semantic_action_targets":semanticItems.filter(isAction).count,
                         "semantic_press_actions":semanticItems.filter{pressActions.contains($0.id)}.count,
                         "press_actions":pressActions.count,"unassigned_press_actions":unassigned.intersection(pressActions).count,
                         "generic_with_actions":genericWithActions,"dominant_primaries":dominantPrimaries,
                         "content_blocks":contentRows.count,"content_parent_sets":siblings.count]
    }
    public func group(forAnchor id:ElementID) -> RowActionGroup? { groups.first{$0.anchor.id == id} }
    public func presented(_ targets:[Target],fold:Bool,expanded:ElementID?,choosing:Bool,all:Bool) -> [Target] {
        if choosing,!groups.isEmpty { return groups.map(\.anchor) }
        guard fold,!all else { return targets }
        let folded=groups.filter{$0.row.id != expanded}.reduce(into:Set<ElementID>()){$0.formUnion($1.actions)}
        var shown=targets.filter{!folded.contains($0.id)}
        let ids=Set(shown.map(\.id))
        shown += groups.map(\.anchor).filter{!ids.contains($0.id)}
        return shown
    }
}
