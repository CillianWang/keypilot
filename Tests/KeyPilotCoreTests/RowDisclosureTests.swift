import XCTest
@testable import KeyPilotCore

final class RowDisclosureTests:XCTestCase {
    func fixture() -> MockReader {
        let r=MockReader()
        r.add(AXNode(id:1,role:"AXWindow",frame:Rect(0,0,1000,800)),children:[2,3])
        r.add(AXNode(id:2,role:"AXList",frame:Rect(0,50,240,700)),children:[10,20])
        r.add(AXNode(id:3,role:"AXButton",frame:Rect(800,20,50,30)))
        r.add(AXNode(id:10,role:"AXRow",frame:Rect(0,60,240,40)),children:[11,12])
        r.add(AXNode(id:11,role:"AXButton",frame:Rect(185,65,25,25)))
        r.add(AXNode(id:12,role:"AXCheckBox",frame:Rect(10,65,25,25)))
        r.add(AXNode(id:20,role:"AXRow",frame:Rect(0,110,240,40)),children:[21])
        r.add(AXNode(id:21,role:"AXButton",frame:Rect(185,115,25,25),visualVisibility:.visible))
        return r
    }
    func policy(_ snapshot:ScanSnapshot) -> RowDisclosure { RowDisclosure(targets:snapshot.targets,nodes:snapshot.nodes,regions:snapshot.regions) }
    func ids(_ targets:[Target]) -> Set<ElementID> { Set(targets.map(\.id)) }
    func testUnknownDoesNotMeanHiddenOrConfirmedVisible() {
        let r=fixture()
        r.add(AXNode(id:30,role:"AXButton",frame:Rect(500,20,30,30),hidden:true))
        r.edges[1]?.append(30); r.nodes[1]?.childCount += 1
        let snapshot=r.scan()
        XCTAssertTrue(r.nodes[30]!.operable); XCTAssertFalse(r.nodes[30]!.clickable)
        XCTAssertFalse(snapshot.targets.contains{$0.id == 30})
        XCTAssertEqual(snapshot.targets.first{$0.id == 11}?.visualVisibility,.unknown)
        XCTAssertEqual(snapshot.targets.first{$0.id == 21}?.visualVisibility,.visible)
        XCTAssertTrue(snapshot.targets.contains{$0.id == 3}) // Unknown standalone button stays usable.
    }
    func testFoldIsSeparateFromRawCandidatesAndAllRestoresEverything() {
        let snapshot=fixture().scan(),p=policy(snapshot)
        XCTAssertEqual(p.groups.count,2)
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false)),[3,10,12,20])
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:true)),ids(snapshot.targets))
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:false,expanded:nil,choosing:false,all:false)),ids(snapshot.targets))
        XCTAssertTrue(snapshot.targets.contains{$0.id == 11})
        XCTAssertTrue(snapshot.targets.contains{$0.id == 21}) // A presentation policy may also fold visible actions.
    }
    func testOnlyChosenRowExpandsAndChoosingShowsAnchors() {
        let snapshot=fixture().scan(),p=policy(snapshot)
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:10,choosing:false,all:false)),[3,10,11,12,20])
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:true,all:false)),[10,20])
        XCTAssertEqual(p.group(forAnchor:10)?.actions,[11])
    }
    func testWrappedListItemRetainsPrimaryLinkAndStandaloneToolbar() {
        let r=fixture()
        r.nodes[10]?.role="AXGroup"
        r.add(AXNode(id:13,role:"AXLink",frame:Rect(5,60,165,40)))
        r.edges[10]?.append(13); r.nodes[10]?.childCount += 1
        let snapshot=r.scan(),p=policy(snapshot)
        XCTAssertEqual(p.groups.first{$0.row.id == 10}?.anchor.id,13)
        let shown=p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false)
        XCTAssertTrue(ids(shown).contains(13)); XCTAssertFalse(ids(shown).contains(11)); XCTAssertTrue(ids(shown).contains(3))
    }
    func testNonClickableListItemGetsHoverAnchorButNeverBecomesClickable() {
        let r=fixture(); r.nodes[10]?.role="AXGroup"
        let snapshot=r.scan(),p=policy(snapshot)
        let group=p.groups.first{$0.row.id == 10}
        XCTAssertEqual(group?.anchor.id,10); XCTAssertEqual(group?.anchor.purpose,.rowDisclosure)
        XCTAssertFalse(snapshot.targets.contains{$0.id == 10})
        XCTAssertFalse(r.nodes[10]!.operable)
        XCTAssertTrue(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false).contains{$0.id == 10})
    }
    func testOverlaysAndUnstructuredButtonGroupsStayFullyAvailable() {
        let r=fixture()
        r.add(AXNode(id:40,frame:Rect(400,200,300,40)),children:[41,42])
        r.add(AXNode(id:41,role:"AXButton",frame:Rect(400,200,100,30)))
        r.add(AXNode(id:42,role:"AXButton",frame:Rect(520,200,100,30)))
        r.add(AXNode(id:50,role:"AXMenu",frame:Rect(400,300,200,200)),children:[51])
        r.add(AXNode(id:51,role:"AXRow",frame:Rect(410,310,180,40)),children:[52])
        r.add(AXNode(id:52,role:"AXButton",frame:Rect(550,315,25,25)))
        r.edges[1]! += [40,50]; r.nodes[1]?.childCount += 2
        let snapshot=r.scan(),p=policy(snapshot)
        let shown=ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false))
        XCTAssertTrue([41,42,51,52].allSatisfy{shown.contains($0)})
        XCTAssertFalse(p.groups.contains{$0.row.layer != nil})
    }
    func testNestedRowsHaveSeparateActionsAndNoDuplicateAnchors() {
        let r=fixture()
        r.edges[10]?.append(20); r.nodes[10]?.childCount += 1
        r.edges[2]=[10]; r.nodes[2]?.childCount=1
        r.nodes[10]?.frame=Rect(0,60,240,100)
        let snapshot=r.scan(),p=policy(snapshot)
        XCTAssertEqual(p.groups.first{$0.row.id == 10}?.actions,[11])
        XCTAssertEqual(p.groups.first{$0.row.id == 20}?.actions,[21])
        let shown=p.presented(snapshot.targets,fold:true,expanded:20,choosing:false,all:false)
        XCTAssertEqual(shown.count,ids(shown).count)
        XCTAssertTrue(ids(shown).contains(21)); XCTAssertFalse(ids(shown).contains(11))
    }
    func testCodesSurviveCollapseExpansionAndFullWindowScope() {
        let snapshot=fixture().scan(),p=policy(snapshot)
        var book=CodeBook()
        let full=book.publish(ids:snapshot.targets.map(\.id),alive:Set(snapshot.nodes.keys),final:true,exhaustive:true)
        for (expanded,all):(ElementID?,Bool) in [(nil,false),(10,false),(nil,true),(20,false)] {
            let shown=p.presented(snapshot.targets,fold:true,expanded:expanded,choosing:false,all:all)
            let codes=book.publish(ids:shown.map(\.id),alive:Set(snapshot.nodes.keys),final:true,exhaustive:true)
            for id in shown.map(\.id) { XCTAssertEqual(codes[id],full[id]) }
        }
    }
    func testOffscreenRowAnchorAndActionsAreNotResurrected() {
        let r=fixture(); r.nodes[10]?.frame?.y = -100; r.nodes[11]?.frame?.y = -90; r.nodes[12]?.frame?.y = -90
        let snapshot=r.scan(),p=policy(snapshot)
        XCTAssertFalse(p.groups.contains{$0.row.id == 10})
        XCTAssertFalse(p.presented(snapshot.targets,fold:true,expanded:10,choosing:false,all:false).contains{$0.id == 10 || $0.id == 11})
    }
    func testInlineContentLinksStayAvailableAndNoRowsDoesNotBlankLabels() {
        let r=fixture()
        r.add(AXNode(id:14,role:"AXLink",frame:Rect(45,65,60,25)))
        r.edges[10]?.append(14); r.nodes[10]?.childCount += 1
        let snapshot=r.scan(),p=policy(snapshot)
        XCTAssertTrue(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false)).contains(14))
        let standalone=snapshot.targets.filter{$0.id == 3}
        let empty=RowDisclosure(targets:standalone,nodes:snapshot.nodes,regions:snapshot.regions)
        XCTAssertEqual(ids(empty.presented(standalone,fold:true,expanded:nil,choosing:true,all:false)),[3])
    }

    func ordinaryRows() -> MockReader {
        let r=MockReader()
        r.add(AXNode(id:1,role:"AXWindow",frame:Rect(0,0,1000,800)),children:[2,3])
        r.add(AXNode(id:2,role:"AXScrollArea",frame:Rect(0,50,240,700)),children:[10,20])
        r.add(AXNode(id:3,role:"AXButton",frame:Rect(800,20,50,30)))
        for row:ElementID in [10,20] {
            let y=Double(row)*5+10
            r.add(AXNode(id:row,frame:Rect(0,y,240,40)),children:[row+1,row+2])
            r.add(AXNode(id:row+1,role:"AXLink",frame:Rect(5,y,170,40)))
            r.add(AXNode(id:row+2,role:"AXButton",frame:Rect(195,y+5,25,25)))
        }
        return r
    }
    func testOrdinaryGroupsWithoutAnyListRoleFoldSecondaryButtons() {
        let snapshot=ordinaryRows().scan(),p=policy(snapshot)
        XCTAssertEqual(Set(p.groups.map(\.anchor.id)),[11,21])
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false)),[3,11,21])
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:10,choosing:false,all:false)),[3,11,12,21])
    }
    func testClickableContainersOwnNestedActionsWithoutListSemantics() {
        let r=ordinaryRows()
        for row:ElementID in [10,20] {
            r.nodes[row]?.role="AXButton"; r.edges[row]=[row+2]; r.nodes[row]?.childCount=1
        }
        let snapshot=r.scan(),p=policy(snapshot)
        XCTAssertEqual(Set(p.groups.map(\.anchor.id)),[10,20])
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false)),[3,10,20])
    }
    func testFlattenedSiblingRowsKeepPrimaryAndFoldOnlyAlignedActions() {
        let r=ordinaryRows()
        r.edges[2]=[11,12,21,22,30]; r.nodes[2]?.childCount=5
        r.add(AXNode(id:30,role:"AXButton",frame:Rect(195,180,25,25)))
        let snapshot=r.scan(),p=policy(snapshot)
        XCTAssertEqual(Set(p.groups.map(\.anchor.id)),[11,21])
        XCTAssertEqual(p.group(forAnchor:11)?.actions,[12])
        XCTAssertEqual(p.group(forAnchor:21)?.actions,[22])
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false)),[3,11,21,30])
    }
    func contentBlocks() -> MockReader {
        let r=ordinaryRows()
        r.nodes[2]?.frame=Rect(0,50,700,700)
        for row:ElementID in [10,20] {
            let y=row == 10 ? 60.0:320.0
            r.add(AXNode(id:row,frame:Rect(20,y,660,210)),children:[row+1,row+2,row+3])
            r.add(AXNode(id:row+1,role:"AXStaticText",frame:Rect(25,y+5,620,130)))
            r.add(AXNode(id:row+2,role:"AXButton",frame:Rect(30,y+170,26,26)))
            r.add(AXNode(id:row+3,role:"AXLink",frame:Rect(120,y+80,80,25)))
        }
        return r
    }
    func testRepeatedContentBlocksWithTextAndActionsGetDisclosureAnchors() {
        let snapshot=contentBlocks().scan(),p=policy(snapshot)
        XCTAssertEqual(Set(p.groups.map(\.row.id)),[10,20])
        XCTAssertTrue(p.groups.allSatisfy{$0.anchor.purpose == .rowDisclosure})
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false)),[3,10,13,20,23])
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:10,choosing:false,all:false)),[3,10,12,13,20,23])
    }
    func testTransparentWrappersAndActionToolbarsDoNotBreakContentGrouping() {
        let r=contentBlocks()
        r.add(AXNode(id:40),children:[10]); r.add(AXNode(id:50),children:[20])
        r.edges[2]=[40,50]
        for row:ElementID in [10,20] {
            r.add(AXNode(id:row+4,role:"AXToolbar",frame:r.nodes[row+2]?.frame),children:[row+2])
            r.edges[row]=[row+1,row+3,row+4]
        }
        let p=policy(r.scan())
        XCTAssertEqual(Set(p.groups.map(\.row.id)),[10,20])
        XCTAssertEqual(p.group(forAnchor:10)?.actions,[12])
    }
    func testRepeatedFormsAndStandaloneToolbarsStayAvailable() {
        let r=contentBlocks()
        for row:ElementID in [10,20] {
            r.add(AXNode(id:row+4,role:"AXTextField",frame:Rect(25,r.nodes[row]!.frame!.y+140,200,25)))
            r.edges[row]?.append(row+4); r.nodes[row]?.childCount += 1
        }
        r.add(AXNode(id:40,role:"AXToolbar",frame:Rect(700,200,300,40)),children:[41,42])
        r.add(AXNode(id:41,role:"AXLink",frame:Rect(700,200,200,40)))
        r.add(AXNode(id:42,role:"AXButton",frame:Rect(950,205,25,25)))
        r.edges[1]?.append(40); r.nodes[1]?.childCount += 1
        let snapshot=r.scan(),p=policy(snapshot)
        XCTAssertTrue(p.groups.isEmpty)
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false)),ids(snapshot.targets))
    }
    func testRepeatedEqualButtonsAndTheirTextAreNotContentRows() {
        let r=ordinaryRows()
        for row:ElementID in [10,20] {
            r.nodes[row+1]?.role="AXButton"; r.nodes[row+1]?.frame?.width=90
            r.nodes[row+2]?.frame?.width=90; r.nodes[row+2]?.frame?.x=130
            r.add(AXNode(id:row+3,role:"AXStaticText",frame:Rect(10,r.nodes[row]!.frame!.y+5,70,25)))
            r.edges[row+1]=[row+3]; r.nodes[row+1]?.childCount=1
        }
        let snapshot=r.scan(),p=policy(snapshot)
        XCTAssertTrue(p.groups.isEmpty)
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false)),ids(snapshot.targets))
    }
    func testGenericGroupingRespectsScopeAndDoesNotResurrectOtherRows() {
        let snapshot=ordinaryRows().scan()
        let scoped=snapshot.targets.filter{$0.id == 11 || $0.id == 12}
        let p=RowDisclosure(targets:scoped,nodes:snapshot.nodes,regions:snapshot.regions)
        XCTAssertEqual(Set(p.groups.map(\.row.id)),[10])
        XCTAssertEqual(ids(p.presented(scoped,fold:true,expanded:nil,choosing:false,all:false)),[11])
        XCTAssertEqual(ids(p.presented(scoped,fold:true,expanded:nil,choosing:false,all:true)),[11,12])
    }
    func testSamePrimaryThroughNestedWrappersHasOneExpansionEntry() {
        let r=ordinaryRows()
        r.add(AXNode(id:30,frame:Rect(0,60,240,40)),children:[10,31])
        r.add(AXNode(id:31,role:"AXButton",frame:Rect(220,65,18,25)))
        r.edges[2]=[30,20]
        let snapshot=r.scan(),p=policy(snapshot)
        XCTAssertEqual(p.groups.filter{$0.anchor.id == 11}.count,1)
        let group=p.group(forAnchor:11)
        XCTAssertEqual(group?.actions,[12,31])
        let shown=p.presented(snapshot.targets,fold:true,expanded:group?.row.id,choosing:false,all:false)
        XCTAssertTrue([11,12,31].allSatisfy{ids(shown).contains($0)})
        XCTAssertFalse(ids(shown).contains(22))
    }
    func testRepeatedBlocksDoNotFoldAnOffscreenActionOrCrossFloatingLayers() {
        let r=contentBlocks()
        r.nodes[12]?.frame?.y = -100
        r.add(AXNode(id:30,role:"AXMenu",frame:Rect(20,550,200,150)),children:[31])
        r.add(AXNode(id:31,role:"AXButton",frame:Rect(30,560,25,25)))
        r.edges[20]?.append(30); r.nodes[20]?.childCount += 1
        let snapshot=r.scan(),p=policy(snapshot)
        XCTAssertFalse(p.groups.contains{$0.actions.contains(12) || $0.actions.contains(31)})
        XCTAssertTrue(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false)).contains(31))
    }
    func testSemanticRowsFoldPressActionsExposedAsGroupsOrImages() {
        let r=fixture()
        r.nodes[11]?.role="AXGroup"; r.nodes[11]?.pressable=true
        r.nodes[21]?.role="AXImage"; r.nodes[21]?.pressable=true
        let snapshot=r.scan(),p=policy(snapshot)
        XCTAssertEqual(p.group(forAnchor:10)?.actions,[11])
        XCTAssertEqual(p.group(forAnchor:20)?.actions,[21])
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false)),[3,10,12,20])
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:10,choosing:false,all:false)),[3,10,11,12,20])
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:true)),ids(snapshot.targets))
    }
    func testListGroupsKeepPrimaryAndFoldGenericPressActions() {
        let r=ordinaryRows(); r.nodes[2]?.role="AXList"
        for row:ElementID in [10,20] {
            r.nodes[row+1]?.role="AXButton"
            r.nodes[row+2]?.role="AXGroup"; r.nodes[row+2]?.pressable=true
        }
        let snapshot=r.scan(),p=policy(snapshot)
        XCTAssertEqual(Set(p.groups.map(\.anchor.id)),[11,21])
        XCTAssertEqual(p.group(forAnchor:11)?.actions,[12])
        XCTAssertEqual(p.group(forAnchor:21)?.actions,[22])
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false)),[3,11,21])
    }
    func testRepeatedContentAndFlatRowsFoldIndependentPressActions() {
        let content=contentBlocks()
        content.nodes[12]?.role="AXGroup"; content.nodes[12]?.pressable=true
        content.nodes[22]?.role="AXUnknown"; content.nodes[22]?.pressable=true
        let contentSnapshot=content.scan(),contentPolicy=policy(contentSnapshot)
        XCTAssertEqual(Set(contentPolicy.groups.map(\.row.id)),[10,20])
        XCTAssertEqual(ids(contentPolicy.presented(contentSnapshot.targets,fold:true,expanded:nil,choosing:false,all:false)),[3,10,13,20,23])
        let flat=ordinaryRows()
        flat.edges[2]=[11,12,21,22]; flat.nodes[2]?.childCount=4
        for id:ElementID in [12,22] { flat.nodes[id]?.role="AXGroup"; flat.nodes[id]?.pressable=true }
        let flatSnapshot=flat.scan(),flatPolicy=policy(flatSnapshot)
        XCTAssertEqual(Set(flatPolicy.groups.map(\.anchor.id)),[11,21])
        XCTAssertEqual(ids(flatPolicy.presented(flatSnapshot.targets,fold:true,expanded:nil,choosing:false,all:false)),[3,11,21])
    }
    func testPressActionsDoNotOverrideLinkTextAndFormSemantics() {
        let r=fixture()
        for (id,role) in [(ElementID(13),"AXLink"),(14,"AXStaticText"),(15,"AXTextField"),(16,"AXDisclosureTriangle")] {
            r.add(AXNode(id:id,role:role,frame:Rect(45,65,25,25),pressable:true))
            r.edges[10]?.append(id); r.nodes[10]?.childCount += 1
        }
        r.nodes[12]?.pressable=true // Checkboxes also advertise AXPress.
        let snapshot=r.scan(),p=policy(snapshot)
        let shown=ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false))
        XCTAssertTrue([12,13,14,15,16].allSatisfy{shown.contains($0)})
        XCTAssertFalse(shown.contains(11))
    }
    func testWidePressableTextIsPrimaryRatherThanTheSecondaryButton() {
        let r=ordinaryRows()
        for row:ElementID in [10,20] {
            r.nodes[row+1]?.role="AXStaticText"; r.nodes[row+1]?.pressable=true
            r.nodes[row+2]?.role="AXGroup"; r.nodes[row+2]?.pressable=true
        }
        let snapshot=r.scan(),p=policy(snapshot)
        XCTAssertEqual(Set(p.groups.map(\.anchor.id)),[11,21])
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false)),[3,11,21])
    }
    func testActionRolesWithoutPressDoNotBecomeNewRawCandidates() {
        let r=ordinaryRows()
        r.nodes[12]?.role="AXGroup"; r.nodes[22]?.role="AXImage"
        let snapshot=r.scan(),p=policy(snapshot)
        XCTAssertFalse(ids(snapshot.targets).contains(12)); XCTAssertFalse(ids(snapshot.targets).contains(22))
        XCTAssertTrue(p.groups.isEmpty)
        XCTAssertEqual(ids(p.presented(snapshot.targets,fold:true,expanded:nil,choosing:false,all:false)),[3,11,21])
    }
}
