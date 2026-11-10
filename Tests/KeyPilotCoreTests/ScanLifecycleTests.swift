import XCTest
@testable import KeyPilotCore

final class MockReader:AXReading {
    var nodes:[ElementID:AXNode]=[:]
    var edges:[ElementID:[ElementID]]=[:]
    var reads=0
    func add(_ node:AXNode,children:[ElementID]=[]) { var node=node; node.childCount=children.count; nodes[node.id]=node; edges[node.id]=children }
    func read(_ id:ElementID) -> AXNode? { reads += 1; return nodes[id] }
    func children(_ id:ElementID,offset:Int,limit:Int) -> [ElementID] { Array((edges[id] ?? []).dropFirst(offset).prefix(limit)) }
    func scan(window:Rect=Rect(0,0,1000,800)) -> ScanSnapshot {
        let scan=ScanTraversal(reader:self,root:1,window:window)
        var result=scan.step(); while !result.final { result=scan.step() }; return result
    }
}
final class ScanLifecycleTests:XCTestCase {
    func panels() -> MockReader {
        let r=MockReader()
        r.add(AXNode(id:1,role:"AXWindow",frame:Rect(0,0,1000,800)),children:[2,3,4])
        r.add(AXNode(id:2,role:"AXScrollArea",frame:Rect(10,50,250,700)),children:[5])
        r.add(AXNode(id:3,role:"AXScrollArea",frame:Rect(270,50,720,700)),children:[6])
        r.add(AXNode(id:4,role:"AXButton",frame:Rect(900,10,30,30)))
        r.add(AXNode(id:5,role:"AXButton",frame:Rect(30,80,30,30)))
        r.add(AXNode(id:6,role:"AXButton",frame:Rect(350,80,30,30)))
        return r
    }
    func testAncestryOutsideControlsSortingAndLargest() {
        let snapshot=panels().scan()
        XCTAssertEqual(snapshot.regions.map(\.id),[2,3])
        let selection=RegionSelection.resolve(previous:nil,interacted:false,regions:snapshot.regions,final:true)
        XCTAssertEqual(selection.selected,3)
        let scoped=TargetScope.filter(snapshot.targets,regions:snapshot.regions,selected:2,wholeWindow:false,overlays:[:])
        XCTAssertEqual(Set(scoped.map(\.id)),[4,5])
        XCTAssertEqual(snapshot.targets.first{$0.id == 5}?.ancestors,[1,2])
    }
    func testDisabledAndFramelessWrappersStillTraverse() {
        let r=panels(); r.add(AXNode(id:5,enabled:false),children:[7]); r.add(AXNode(id:7,role:"AXButton",frame:Rect(30,100,30,30)))
        let result=r.scan(); XCTAssertTrue(result.targets.contains{$0.id == 7}); XCTAssertFalse(result.targets.contains{$0.id == 5})
    }
    func testOverlayIndependentClippingAndOcclusionRecovery() {
        let r=panels()
        r.add(AXNode(id:5,role:"AXButton",frame:Rect(30,80,30,30)),children:[8])
        r.add(AXNode(id:8,role:"AXMenu",frame:Rect(300,50,220,300)),children:[9])
        r.add(AXNode(id:9,role:"AXMenuItem",frame:Rect(350,80,30,30)))
        var result=r.scan()
        XCTAssertEqual(result.targets.first{$0.id == 9}?.frame,Rect(350,80,30,30))
        var visible=TargetScope.filter(result.targets,regions:result.regions,selected:2,wholeWindow:true,overlays:result.overlays)
        XCTAssertTrue(visible.contains{$0.id == 9}); XCTAssertFalse(visible.contains{$0.id == 6})
        r.edges[5]=[]; result=r.scan()
        visible=TargetScope.filter(result.targets,regions:result.regions,selected:2,wholeWindow:true,overlays:result.overlays)
        XCTAssertTrue(visible.contains{$0.id == 6})
    }
    func testParentAndChildRegionShareAndSiblingsDoNot() {
        let target=Target(id:10,frame:Rect(10,10,10,10),ancestors:[1,2,3])
        let regions=[Region(id:2,frame:Rect(0,0,200,200)),Region(id:3,frame:Rect(0,0,100,100)),Region(id:4,frame:Rect(200,0,100,100))]
        XCTAssertEqual(TargetScope.filter([target],regions:regions,selected:2,wholeWindow:false,overlays:[:]).count,1)
        XCTAssertEqual(TargetScope.filter([target],regions:regions,selected:3,wholeWindow:false,overlays:[:]).count,1)
        XCTAssertEqual(TargetScope.filter([target],regions:regions,selected:4,wholeWindow:false,overlays:[:]).count,0)
    }
    func testInferenceRequiresStructureNotStackedCards() {
        let r=MockReader(); r.add(AXNode(id:1,role:"AXWindow",frame:Rect(0,0,1000,800)),children:[2,3])
        r.add(AXNode(id:2,frame:Rect(0,0,300,800))); r.add(AXNode(id:3,frame:Rect(310,0,690,800)))
        XCTAssertEqual(r.scan().regions.map(\.id),[2,3])
        r.add(AXNode(id:2,frame:Rect(0,0,1000,350))); r.add(AXNode(id:3,frame:Rect(0,400,1000,350)))
        XCTAssertEqual(r.scan().regions.map(\.id),[1])
        r.nodes[1]?.role="AXSplitGroup"
        XCTAssertEqual(Set(r.scan().regions.map(\.id)),[2,3])
    }
    func testNarrowSidebarBesideWebContentOnWideWindow() {
        let r=MockReader(),window=Rect(0,0,3600,1000)
        r.add(AXNode(id:1,role:"AXWindow",frame:window),children:[2,3])
        r.add(AXNode(id:2,frame:Rect(0,40,180,960)))
        r.add(AXNode(id:3,role:"AXWebArea",frame:Rect(180,40,3420,960)))
        XCTAssertEqual(r.scan(window:window).regions.map(\.id),[2,3])
    }
    func testFramelessWrapperDoesNotHideSiblingSidebar() {
        let r=MockReader()
        r.add(AXNode(id:1,role:"AXWindow",frame:Rect(0,0,1000,800)),children:[2,3])
        r.add(AXNode(id:2),children:[4])
        r.add(AXNode(id:4,frame:Rect(0,40,200,760)))
        r.add(AXNode(id:3,role:"AXWebArea",frame:Rect(200,40,800,760)))
        XCTAssertEqual(r.scan().regions.map(\.id),[4,3])
    }
    func testStandaloneListIsRegionWithoutScrollbarAndKeepsRowScope() {
        let r=MockReader()
        r.add(AXNode(id:1,role:"AXWindow",frame:Rect(0,0,1000,800)),children:[2,3])
        r.add(AXNode(id:2),children:[4])
        r.add(AXNode(id:4,role:"AXList",frame:Rect(10,50,220,700)),children:[5,6])
        r.add(AXNode(id:3,role:"AXWebArea",frame:Rect(300,0,700,800)),children:[7])
        r.add(AXNode(id:5,role:"AXRow",frame:Rect(10,60,220,32)))
        r.add(AXNode(id:6,role:"AXRow",frame:Rect(10,740,220,32)))
        r.add(AXNode(id:7,role:"AXButton",frame:Rect(400,60,40,32)))
        let result=r.scan()
        XCTAssertEqual(result.regions.map(\.id),[4,3])
        XCTAssertEqual(result.targets.first{$0.id == 6}?.frame.height,10)
        XCTAssertEqual(Set(TargetScope.filter(result.targets,regions:result.regions,selected:4,wholeWindow:false,overlays:[:]).map(\.id)),[5,6])
    }
    func testActualListScrollViewportTakesPriorityOverDecorativeSidebarWrapper() {
        let r=MockReader()
        r.add(AXNode(id:1,role:"AXWindow",frame:Rect(0,0,1000,800)),children:[2,3])
        r.add(AXNode(id:2,frame:Rect(0,0,220,800)),children:[4])
        r.add(AXNode(id:4,role:"AXList",frame:Rect(0,60,220,740),hasVerticalScroll:true),children:[5])
        r.add(AXNode(id:5,role:"AXRow",frame:Rect(0,70,220,30)))
        r.add(AXNode(id:3,role:"AXWebArea",frame:Rect(220,0,780,800)))
        XCTAssertEqual(r.scan().regions.map(\.id),[4,3])
    }
    func testScrollingListSectionsKeepSidebarIdentityAndVisibleRowLabels() {
        let r=MockReader(),window=Rect(0,0,1000,800)
        r.add(AXNode(id:1,role:"AXWebArea",frame:window),children:[2,3])
        r.add(AXNode(id:2,subrole:"AXLandmarkNavigation",frame:Rect(0,50,240,700)),children:[4,5])
        r.add(AXNode(id:3,role:"AXScrollArea",frame:Rect(260,50,740,700)),children:[10])
        r.add(AXNode(id:4,role:"AXList",frame:Rect(0,50,240,650)),children:[6,7])
        r.add(AXNode(id:5,role:"AXList",frame:Rect(0,720,240,300)),children:[8,9])
        r.add(AXNode(id:6,role:"AXRow",frame:Rect(10,70,220,30)))
        r.add(AXNode(id:7,role:"AXRow",frame:Rect(10,660,220,30)))
        r.add(AXNode(id:8,role:"AXRow",frame:Rect(10,730,220,30)))
        r.add(AXNode(id:9,role:"AXRow",frame:Rect(10,900,220,30)))
        r.add(AXNode(id:10,role:"AXButton",frame:Rect(300,100,40,30)))
        let before=r.scan()
        XCTAssertEqual(before.regions.map(\.id),[2,3])
        let sidebar=before.regions.first?.id
        for id:ElementID in [4,5,6,7,8,9] { r.nodes[id]?.frame?.y -= 480 }
        let after=r.scan()
        XCTAssertEqual(after.regions.map(\.id),before.regions.map(\.id))
        let selection=RegionSelection.resolve(previous:sidebar,interacted:true,regions:after.regions,final:true)
        XCTAssertEqual(selection.selected,2)
        let rows=TargetScope.filter(after.targets,regions:after.regions,selected:selection.selected,wholeWindow:false,overlays:[:])
        XCTAssertEqual(Set(rows.map(\.id)),[7,8,9])
        var book=CodeBook()
        let codes=book.publish(ids:rows.map(\.id),alive:Set(after.targets.map(\.id)),final:true,exhaustive:true)
        let layout=LabelLayout.layout(targets:rows,screens:[Screen(id:1,frame:window)],reserved:[],size:Point(35,23))
        let pages=LabelPages(geometry:layout,codes:codes)
        XCTAssertEqual(Set(pages.display.flatMap{$0}.map{$0.target.id}),[7,8,9])
    }
    func testInferredSidebarClipsMovingContentButNotItsFloatingMenu() {
        let r=MockReader(),window=Rect(0,0,1000,800)
        r.add(AXNode(id:1,role:"AXWindow",frame:window),children:[2,3])
        r.add(AXNode(id:2,frame:Rect(0,100,240,650)),children:[4])
        r.add(AXNode(id:3,role:"AXWebArea",frame:Rect(260,100,740,650)))
        r.add(AXNode(id:4,role:"AXList",frame:Rect(0,-300,240,1200)),children:[5,6,7,8])
        r.add(AXNode(id:5,role:"AXRow",frame:Rect(10,50,220,30)))
        r.add(AXNode(id:6,role:"AXRow",frame:Rect(10,110,220,30)))
        r.add(AXNode(id:7,role:"AXRow",frame:Rect(10,740,220,30)))
        r.add(AXNode(id:8,role:"AXMenu",frame:Rect(400,50,200,300)),children:[9])
        r.add(AXNode(id:9,role:"AXMenuItem",frame:Rect(410,60,180,30)))
        let result=r.scan()
        XCTAssertEqual(result.regions.map(\.id),[2,3])
        XCTAssertFalse(result.targets.contains{$0.id == 5})
        XCTAssertEqual(result.targets.first{$0.id == 7}?.frame,Rect(10,740,220,10))
        XCTAssertEqual(result.targets.first{$0.id == 9}?.frame,Rect(410,60,180,30))
    }
    func testNativeOutlineRemainsAnIndependentViewportInsidePanel() {
        let r=MockReader()
        r.add(AXNode(id:1,role:"AXWindow",frame:Rect(0,0,1000,800)),children:[2,3])
        r.add(AXNode(id:2,frame:Rect(0,0,220,800)),children:[4])
        r.add(AXNode(id:4,role:"AXOutline",frame:Rect(0,60,220,740)),children:[5])
        r.add(AXNode(id:5,role:"AXRow",frame:Rect(0,70,220,30)))
        r.add(AXNode(id:3,role:"AXWebArea",frame:Rect(220,0,780,800)))
        XCTAssertEqual(r.scan().regions.map(\.id),[4,3])
    }
    func testSmallListsAndNestedCardsDoNotBecomeMajorRegions() {
        let r=MockReader()
        r.add(AXNode(id:1,role:"AXWindow",frame:Rect(0,0,1000,800)),children:[2,3])
        r.add(AXNode(id:2,role:"AXList",frame:Rect(20,20,150,100)),children:[6])
        r.add(AXNode(id:6,role:"AXRow",frame:Rect(20,20,150,30)))
        r.add(AXNode(id:3,frame:Rect(300,100,400,300)),children:[4,5])
        r.add(AXNode(id:4,frame:Rect(300,100,190,300)))
        r.add(AXNode(id:5,frame:Rect(510,100,190,300)))
        XCTAssertEqual(r.scan().regions.map(\.id),[1])
    }
    func testPageScrollAncestorDoesNotSuppressNarrowListRegion() {
        let r=MockReader(),window=Rect(0,0,1000,800)
        r.add(AXNode(id:1,role:"AXWindow",frame:window),children:[2])
        r.add(AXNode(id:2,role:"AXScrollArea",frame:Rect(0,40,1000,760)),children:[3,4])
        r.add(AXNode(id:3,frame:Rect(0,40,240,760)),children:[5])
        r.add(AXNode(id:4,frame:Rect(280,40,720,350)),children:[7])
        r.add(AXNode(id:5,role:"AXList",frame:Rect(0,260,240,540)),children:[6])
        r.add(AXNode(id:6,role:"AXRow",frame:Rect(0,300,240,32)))
        r.add(AXNode(id:7,role:"AXButton",frame:Rect(300,100,40,32)))
        let result=r.scan()
        XCTAssertTrue(result.regions.contains{$0.id == 5})
        XCTAssertEqual(Set(TargetScope.filter(result.targets,regions:result.regions,selected:5,wholeWindow:false,overlays:[:]).map(\.id)),[6])
    }
    func testListInsideItsOwnScrollViewportDoesNotAddDuplicateRegion() {
        let r=MockReader(),window=Rect(0,0,1000,800)
        r.add(AXNode(id:1,role:"AXWindow",frame:window),children:[2])
        r.add(AXNode(id:2,role:"AXScrollArea",frame:Rect(0,40,1000,760)),children:[3])
        r.add(AXNode(id:3,role:"AXList",frame:Rect(20,120,960,640)),children:[4])
        r.add(AXNode(id:4,role:"AXRow",frame:Rect(20,140,960,30)))
        XCTAssertEqual(r.scan().regions.map(\.id),[2])
    }
    func testSemanticSidebarAndMainDoNotRequireMatchingHeights() {
        for subrole in ["AXLandmarkNavigation","AXLandmarkComplementary"] {
            let r=MockReader(),window=Rect(0,0,1000,800)
            r.add(AXNode(id:1,role:"AXWebArea",frame:window),children:[2,3])
            r.add(AXNode(id:2,subrole:subrole,frame:Rect(0,120,240,360)),children:[4])
            r.add(AXNode(id:3,subrole:"AXLandmarkMain",frame:Rect(280,40,720,760)),children:[5])
            r.add(AXNode(id:4,role:"AXButton",frame:Rect(10,150,220,32)))
            r.add(AXNode(id:5,role:"AXButton",frame:Rect(300,150,40,32)))
            let result=r.scan()
            XCTAssertEqual(result.regions.map(\.id),[2,3])
            XCTAssertEqual(Set(TargetScope.filter(result.targets,regions:result.regions,selected:2,wholeWindow:false,overlays:[:]).map(\.id)),[4])
        }
    }
    func testDeepFramelessWrappersStillExposeSiblingPanels() {
        let r=MockReader(),window=Rect(0,0,1000,800)
        r.add(AXNode(id:1,role:"AXWindow",frame:window),children:[2,20])
        for id in 2...9 { r.add(AXNode(id:UInt64(id)),children:[UInt64(id+1)]) }
        r.add(AXNode(id:10,frame:Rect(0,40,240,760)))
        r.add(AXNode(id:20,role:"AXWebArea",frame:Rect(240,40,760,760)))
        XCTAssertEqual(r.scan().regions.map(\.id),[10,20])
    }
    func testSmallAndFloatingLandmarksAreNotWindowRegions() {
        let r=MockReader(),window=Rect(0,0,1000,800)
        r.add(AXNode(id:1,role:"AXWebArea",frame:window),children:[2,3,4])
        r.add(AXNode(id:2,subrole:"AXLandmarkNavigation",frame:Rect(0,0,1000,80)))
        r.add(AXNode(id:3,subrole:"AXLandmarkComplementary",frame:Rect(0,100,150,100)))
        r.add(AXNode(id:4,role:"AXDialog",frame:Rect(200,100,600,600)),children:[5])
        r.add(AXNode(id:5,subrole:"AXLandmarkNavigation",frame:Rect(200,100,220,600)))
        XCTAssertEqual(r.scan().regions.map(\.id),[1])
    }
    func testScrollClippingAndNoProximityDeduplication() {
        let r=panels(); r.edges[2]=[5,7,8]; r.nodes[2]?.childCount=3
        r.add(AXNode(id:7,role:"AXButton",frame:Rect(62,80,30,30)))
        r.add(AXNode(id:8,role:"AXButton",frame:Rect(10,740,40,40)))
        let result=r.scan()
        XCTAssertTrue(result.targets.contains{$0.id == 5}); XCTAssertTrue(result.targets.contains{$0.id == 7})
        XCTAssertEqual(result.targets.first{$0.id == 8}?.frame.height,10)
    }
    func testSameRectangleAliasesPreferActualScrollAndRemoveWrapper() {
        let r=panels(); r.nodes[1]?.role="AXWebArea"
        r.edges[2]=[7]; r.nodes[2]?.childCount=1; r.add(AXNode(id:7,role:"AXWebArea",frame:Rect(10,50,250,700)),children:[5])
        let result=r.scan()
        XCTAssertEqual(result.regions.map(\.id),[2,3])
    }
    func testBatchedChildrenAndProtectionBudget() {
        let r=MockReader(); let children=(2...1000).map(UInt64.init)
        r.add(AXNode(id:1,role:"AXWindow",frame:Rect(0,0,1000,800)),children:children)
        for id in children { r.add(AXNode(id:id,role:"AXButton",frame:Rect(Double(id%20)*40,Double(id/20)*10,20,10))) }
        let result=r.scan(); XCTAssertTrue(result.final); XCTAssertTrue(result.exhaustive); XCTAssertEqual(result.count,1000)
        XCTAssertEqual(r.reads,1000)
    }
    func testPartialFailureDoesNotClaimExhaustive() {
        let r=panels(); r.nodes.removeValue(forKey:6)
        XCTAssertFalse(r.scan().exhaustive)
    }
    func testMissingSelectionWaitsThenFallsBackOnlyOnComplete() {
        let old:ElementID=2, new=[Region(id:3,frame:Rect(0,0,1000,800))]
        let partial=RegionSelection.resolve(previous:old,interacted:true,regions:new,final:false)
        XCTAssertEqual(partial.selected,old); XCTAssertFalse(partial.geometryValid); XCTAssertTrue(partial.preserveOldBorder)
        let final=RegionSelection.resolve(previous:old,interacted:true,regions:new,final:true)
        XCTAssertEqual(final.selected,3); XCTAssertTrue(final.geometryValid)
    }
    func testIncrementalLargestOnlyBeforeUserInteraction() {
        let regions=[Region(id:1,frame:Rect(0,0,100,100)),Region(id:2,frame:Rect(100,0,900,800))]
        XCTAssertEqual(RegionSelection.resolve(previous:1,interacted:false,regions:regions,final:false).selected,2)
        XCTAssertEqual(RegionSelection.resolve(previous:1,interacted:true,regions:regions,final:false).selected,1)
        XCTAssertEqual(RegionSelection.resolve(previous:9,interacted:false,regions:regions,final:false).selected,2)
        XCTAssertFalse(RegionSelection.resolve(previous:nil,interacted:true,regions:[Region(id:9,frame:Rect(0,0,900,900),kind:.fallback)],final:false).geometryValid)
    }
    func testFiniteRefreshFindsDelayedDeepPanelWithoutAncestorChange() {
        var plan=TransitionRefreshPlan(); plan.replace(now:0)
        XCTAssertFalse(plan.takeDue(now:0.14,canScan:true,lastCompletedScanStarted:0))
        XCTAssertTrue(plan.takeDue(now:0.65,canScan:true,lastCompletedScanStarted:0.14))
        XCTAssertFalse(plan.takeDue(now:1.5,canScan:false,lastCompletedScanStarted:0.65))
        XCTAssertTrue(plan.takeDue(now:2,canScan:true,lastCompletedScanStarted:0.65))
        XCTAssertFalse(plan.takeDue(now:3,canScan:true,lastCompletedScanStarted:2))
        XCTAssertTrue(plan.deadlines.isEmpty)
        plan.replace(now:4); XCTAssertFalse(plan.takeDue(now:6,canScan:true,lastCompletedScanStarted:5.6))
        plan.replace(now:7); plan.cancel(); XCTAssertTrue(plan.deadlines.isEmpty)
    }
}
