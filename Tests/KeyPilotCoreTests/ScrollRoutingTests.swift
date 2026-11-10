import XCTest
@testable import KeyPilotCore

final class ScrollRoutingTests:XCTestCase {
    private func sidebar() -> MockReader {
        let r=MockReader()
        r.add(AXNode(id:1,role:"AXWindow",frame:Rect(0,0,1000,800)),children:[2,3])
        r.add(AXNode(id:2,subrole:"AXLandmarkNavigation",frame:Rect(0,50,240,700)),children:[4,5,6])
        r.add(AXNode(id:3,role:"AXScrollArea",frame:Rect(260,50,740,700)))
        r.add(AXNode(id:4,role:"AXButton",frame:Rect(20,70,40,30))) // Fixed header.
        r.add(AXNode(id:5,role:"AXList",frame:Rect(0,180,240,400)),children:[7])
        r.add(AXNode(id:6,role:"AXList",frame:Rect(0,600,240,500)),children:[8])
        r.add(AXNode(id:7,role:"AXRow",frame:Rect(10,200,220,30)))
        r.add(AXNode(id:8,role:"AXRow",frame:Rect(10,620,220,30)))
        return r
    }
    private func point(_ snapshot:ScanSnapshot) throws -> Point {
        let region=try XCTUnwrap(snapshot.regions.first{$0.id == 2})
        return try XCTUnwrap(ScrollRoute.point(in:region,snapshot:snapshot))
    }
    func testFixedHeaderIsNotScrollDestinationAndSectionsCanChange() throws {
        let r=sidebar(),before=r.scan()
        let first=try point(before)
        XCTAssertTrue(Rect(0,180,240,400).contains(first),"Wheel must land inside the visible list, below the fixed header")
        // The same logical sidebar survives a different section becoming dominant.
        for id:ElementID in [5,6,7,8] { r.nodes[id]?.frame?.y -= 430 }
        let after=r.scan(),second=try point(after)
        XCTAssertEqual(before.regions.map(\.id),after.regions.map(\.id))
        XCTAssertTrue(Rect(0,170,240,500).contains(second))
    }
    func testForeignAndFloatingListsCannotStealSidebarRoute() throws {
        let r=sidebar()
        r.add(AXNode(id:3,role:"AXList",frame:Rect(0,0,1000,800)))
        r.edges[2]?.append(9); r.nodes[2]?.childCount += 1
        r.add(AXNode(id:9,role:"AXMenu",frame:Rect(500,0,500,800)),children:[10])
        r.add(AXNode(id:10,role:"AXList",frame:Rect(500,0,500,800)))
        XCTAssertTrue(Rect(0,180,240,400).contains(try point(r.scan())))
    }
    func testSmallNestedScrollControlCannotCaptureMainListWheel() throws {
        let r=sidebar()
        r.edges[5]?.append(9); r.nodes[5]?.childCount += 1
        r.add(AXNode(id:9,role:"AXScrollArea",frame:Rect(60,300,120,160)))
        let destination=try point(r.scan())
        XCTAssertTrue(Rect(0,180,240,400).contains(destination))
        XCTAssertFalse(Rect(60,300,120,160).contains(destination))
    }
    func testExistingNativeViewportAndClippingRemainUsable() throws {
        let r=sidebar()
        r.nodes[2]?.role="AXScrollArea"
        r.nodes[5]?.frame=Rect(0,-500,240,1600)
        let destination=try point(r.scan())
        XCTAssertTrue(Rect(0,50,240,700).contains(destination))
        XCTAssertFalse(try XCTUnwrap(r.nodes[4]?.frame).contains(destination))
    }
    func testPartialPanelScanWaitsForContentInsteadOfCancellingTraversal() throws {
        let complete=sidebar().scan()
        let region=try XCTUnwrap(complete.regions.first{$0.id == 2})
        var partial=complete
        partial.final=false
        partial.nodes=complete.nodes.filter{[1,2,3,4].contains($0.key)}
        partial.targets=complete.targets.filter{$0.id == 4}
        XCTAssertNil(ScrollRoute.point(in:region,snapshot:partial))
        XCTAssertNotNil(ScrollRoute.point(in:region,snapshot:complete))
        // A completed scan without semantic lists still permits generic scrolling.
        partial.final=true
        XCTAssertNotNil(ScrollRoute.point(in:region,snapshot:partial))
    }
    func testSmallDocumentListDoesNotReplaceWebScrollingSurface() throws {
        let r=MockReader(),window=Rect(0,0,1000,800),list=Rect(400,30,200,100)
        r.add(AXNode(id:1,role:"AXWebArea",frame:window),children:[2])
        r.add(AXNode(id:2,role:"AXList",frame:list))
        let snapshot=r.scan(),region=try XCTUnwrap(snapshot.regions.first)
        let destination=try XCTUnwrap(ScrollRoute.point(in:region,snapshot:snapshot))
        XCTAssertTrue(window.contains(destination))
        XCTAssertFalse(list.contains(destination))
    }
}
