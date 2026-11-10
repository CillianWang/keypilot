import XCTest
@testable import KeyPilotCore

final class CodeLayoutTests:XCTestCase {
    func ids(_ count:Int) -> [ElementID] { (1...count).map(UInt64.init) }
    func assertFree(_ codes:[String],file:StaticString=#filePath,line:UInt=#line) {
        for i in codes.indices { for j in (i+1)..<codes.count { XCTAssertFalse(CodeBook.conflict(codes[i],codes[j]),"\(codes[i]) conflicts with \(codes[j])",file:file,line:line) } }
    }
    func testFreshRepeatPriorityBalancedAndTwoLetters() {
        var book=CodeBook(); let map=book.publish(ids:ids(52),alive:Set(ids(52)),final:true,exhaustive:true)
        XCTAssertEqual(ids(6).compactMap{map[$0]},CodeBook.repeats)
        XCTAssertTrue(map.values.allSatisfy{$0.count == 2}); assertFree(Array(map.values))
        let counts=CodeBook.heads.map{head in map.values.filter{$0.hasPrefix(head)}.count}
        XCTAssertLessThanOrEqual(counts.max()!-counts.min()!,1)
    }
    func testIncrementalEight54Ninety132NoAvoidablePaging() {
        for count in [8,54,90,132] {
            var book=CodeBook()
            var preview:[ElementID:String]=[:]
            for n in stride(from:8,through:count,by:8) { preview=book.publish(ids:ids(min(n,count)),alive:Set(ids(min(n,count))),final:false,exhaustive:false); XCTAssertLessThanOrEqual(preview.count,6) }
            let final=book.publish(ids:ids(count),alive:Set(ids(count)),final:true,exhaustive:true)
            XCTAssertEqual(final.count,count); for (id,code) in preview { XCTAssertEqual(final[id],code) }
            assertFree(Array(final.values)); XCTAssertTrue(final.values.allSatisfy{(2...3).contains($0.count)})
            if count <= 54 { XCTAssertTrue(final.values.allSatisfy{$0.count == 2}) }
        }
    }
    func testFinalEmptyBatchStillAllocatesAndPreservesThreeLettersInSmallScope() {
        var book=CodeBook(); _=book.publish(ids:ids(90),alive:Set(ids(90)),final:false,exhaustive:false)
        let full=book.publish(ids:ids(90),alive:Set(ids(90)),final:true,exhaustive:true)
        let long=full.first{$0.value.count == 3}!
        let small=book.publish(ids:[long.key],alive:Set(ids(90)),final:true,exhaustive:true)
        XCTAssertEqual(small[long.key],long.value)
    }
    func testStableAcrossScopesAndReordering() {
        var book=CodeBook(); let original=book.publish(ids:ids(36),alive:Set(ids(70)),final:true,exhaustive:true)
        _=book.publish(ids:Array(ids(70).suffix(34)),alive:Set(ids(70)),final:true,exhaustive:true)
        let combined=book.publish(ids:ids(70).reversed(),alive:Set(ids(70)),final:true,exhaustive:true)
        for (id,code) in original { XCTAssertEqual(combined[id],code) }; assertFree(Array(combined.values))
    }
    func testReleaseTwentyBeforeReplacementAllocation() {
        var book=CodeBook(); let old=book.publish(ids:ids(52),alive:Set(ids(52)),final:true,exhaustive:true)
        let newIDs=Array(ids(52).dropFirst(20))+(100...119).map(UInt64.init)
        let final=book.publish(ids:newIDs,alive:Set(newIDs),final:true,exhaustive:true)
        for id in 21...52 { XCTAssertEqual(final[UInt64(id)],old[UInt64(id)]) }
        XCTAssertEqual(final.count,52); assertFree(Array(final.values)); XCTAssertTrue(final.values.allSatisfy{$0.count == 2})
    }
    func testIncompleteScanNeverReleasesUnseenIdentity() {
        var book=CodeBook(); let old=book.publish(ids:ids(12),alive:Set(ids(12)),final:true,exhaustive:true)
        _=book.publish(ids:[1],alive:[1],final:true,exhaustive:false)
        XCTAssertEqual(book.mapping,old)
    }
    func testExistingFullShortCodeSpacePagesInsteadOfRenaming() {
        var book=CodeBook(); let old=book.publish(ids:ids(54),alive:Set(ids(54)),final:true,exhaustive:true)
        let new=book.publish(ids:ids(60),alive:Set(ids(60)),final:true,exhaustive:true)
        for (id,code) in old { XCTAssertEqual(new[id],code) }
        let geometry=[ids(60).map{Placement(target:Target(id:$0,frame:Rect(Double($0)*50,0,40,25)),rect:Rect(Double($0)*50,0,35,23),screen:1)}]
        let pages=LabelPages(geometry:geometry,codes:new)
        XCTAssertEqual(pages.geometry.count,1); XCTAssertEqual(pages.display.count,2)
        let next=LabelPages(geometry:pages.geometry,codes:new)
        XCTAssertEqual(next.geometry.count,1); XCTAssertEqual(next.display.count,2)
        for page in next.display { assertFree(page.map{new[$0.target.id]!}) }
    }
    func testTwentyWideRowsAndFortySmallButtonsFitOnePage() {
        var targets:[Target]=[]
        for row in 0..<20 {
            let y=Double(row)*38+50, id=UInt64(row*3+1)
            targets += [Target(id:id,frame:Rect(50,y,750,32),role:"AXRow"),Target(id:id+1,frame:Rect(55,y+3,24,24)),Target(id:id+2,frame:Rect(90,y+3,24,24))]
        }
        let pages=LabelLayout.layout(targets:targets,screens:[Screen(id:1,frame:Rect(0,0,1000,900))],reserved:[],size:Point(36,23))
        XCTAssertEqual(pages.count,1); XCTAssertEqual(pages.flatMap{$0}.count,60)
        for p in pages[0] where p.target.role == "AXRow" { XCTAssertTrue(p.target.frame.contains(p.rect.center)) }
    }
    func testDenseTargetsAllRemainReachableAndCancellation() {
        let targets=ids(100).map{Target(id:$0,frame:Rect(100,100,10,10))}
        let pages=LabelLayout.layout(targets:targets,screens:[Screen(id:1,frame:Rect(0,0,400,400))],reserved:[],size:Point(36,23))
        XCTAssertGreaterThan(pages.count,1); XCTAssertEqual(Set(pages.flatMap{$0}.map{$0.target.id}),Set(ids(100)))
        XCTAssertEqual(LabelLayout.layout(targets:targets,screens:[],reserved:[],size:Point(36,23),cancelled:{true}).count,0)
    }
    func testMultiDisplayAndConversion() {
        let screens=[Screen(id:1,frame:Rect(0,0,1000,800)),Screen(id:2,frame:Rect(-800,100,800,600))]
        XCTAssertEqual(Screen.owner(of:Rect(-300,150,400,200),screens:screens)?.id,2)
        let rect=Rect(-100,100,200,300).appKit(mainScreenHeight:800)
        XCTAssertEqual(rect.origin.y,400); XCTAssertEqual(rect.origin.x,-100)
        let targets=[Target(id:1,frame:Rect(-300,150,400,200))]
        XCTAssertEqual(LabelLayout.layout(targets:targets,screens:screens,reserved:[],size:Point(36,23)).flatMap{$0}.count,1)
    }
    func testEndpointsOnlyFromReliableRangeAndRouteAvoidsControls() {
        XCTAssertEqual(ScrollExtent(value:0,minimum:0,maximum:1).endpoint(direction:-1),.top)
        XCTAssertEqual(ScrollExtent(value:1,minimum:0,maximum:1).endpoint(direction:1),.bottom)
        XCTAssertNil(ScrollExtent(value:0,minimum:0,maximum:0).endpoint(direction:-1))
        XCTAssertNil(ScrollExtent(value:1,minimum:0,maximum:1).endpoint(direction:0))
        let region=Rect(0,0,500,500),buttons=[Target(id:1,frame:Rect(200,200,100,100))]
        let point=ScrollRoute.point(in:region,targets:buttons)
        XCTAssertTrue(region.contains(point)); XCTAssertFalse(buttons[0].frame.contains(point))
    }
}
