import XCTest
@testable import KeyPilotCore

final class NavigationTests:XCTestCase {
    func press(_ key:Key,_ machine:inout NavigationMachine,flags:Modifiers=[],time:Double=1) -> KeyResult {
        let result=machine.key(code:key.rawValue,down:true,modifiers:flags,time:time)
        _=machine.key(code:key.rawValue,down:false,modifiers:flags,time:time+0.01); return result
    }
    func configured() -> NavigationMachine {
        var m=NavigationMachine(); m.activate(); m.regions=[1,2,3,4]; m.selectedRegion=1; m.buttons=[(10,"SS"),(11,"SJG"),(12,"AK")]; return m
    }
    func testEscInputAndToggleSemantics() {
        var m=configured()
        XCTAssertEqual(press(.i,&m).effects,[.scroll(0,false),.input]); XCTAssertEqual(m.mode,.input)
        XCTAssertFalse(press(.a,&m).swallow)
        XCTAssertEqual(press(.escape,&m).effects,[.resume]); XCTAssertEqual(m.mode,.navigation)
        _=press(.s,&m)
        XCTAssertEqual(press(.escape,&m).effects,[.exit]); XCTAssertEqual(m.mode,.inactive)
        XCTAssertEqual(press(.j,&m,flags:[.command,.shift]).effects,[.enter])
        XCTAssertEqual(press(.j,&m,flags:[.command,.shift]).effects,[])
        XCTAssertEqual(press(.space,&m,flags:[.command,.shift]).effects,[.exit])
    }
    func testExactMatchOnlyAndClickKeepsNavigation() {
        var m=configured()
        _=press(.a,&m); XCTAssertEqual(m.buttonPrefix,"A"); XCTAssertEqual(m.mode,.navigation)
        XCTAssertEqual(press(.k,&m).effects,[.click(12,.left)]); XCTAssertEqual(m.mode,.navigation)
        m.automaticClick=false
        _=press(.s,&m); XCTAssertEqual(press(.s,&m).effects,[.redraw]); XCTAssertEqual(m.selectedButton,10)
        XCTAssertEqual(press(.enter,&m,flags:.command).effects,[.click(10,.command)])
    }
    func testJKGInsidePrefixNeverScrollOrRefreshOnUp() {
        var m=configured(); _=press(.s,&m)
        let down=m.key(code:Key.j.rawValue,down:true,time:1)
        XCTAssertEqual(down.effects,[.redraw]); XCTAssertEqual(m.buttonPrefix,"SJ"); XCTAssertEqual(m.scrollDirection,0)
        XCTAssertTrue(m.key(code:Key.j.rawValue,down:false,time:2).effects.isEmpty)
        XCTAssertEqual(press(.g,&m).effects,[.click(11,.left)])
    }
    func testOpposingScrollAndImmediateRelease() {
        var m=configured()
        XCTAssertEqual(m.key(code:38,down:true,time:0).effects,[.scroll(1,false)])
        XCTAssertEqual(m.key(code:40,down:true,time:0).effects,[.scroll(0,false)])
        XCTAssertEqual(m.key(code:38,down:false,time:0).effects,[.scroll(-1,false)])
        XCTAssertEqual(m.key(code:40,down:false,time:0).effects,[.scroll(0,false)])
    }
    func testRepeatedScrollPressesAfterReleaseAndHiddenLabels() {
        var m=configured()
        for (index,key) in [Key.j,.j,.k,.j,.k].enumerated() {
            let time=Double(index)*2
            XCTAssertEqual(m.key(code:key.rawValue,down:true,time:time).effects,[.scroll(key == .j ? 1:-1,false)])
            // The controller hides buttons during scrolling and while refreshing them.
            m.buttons=[]
            XCTAssertEqual(m.key(code:key.rawValue,down:true,repeat:true,time:time+0.2).effects,[])
            XCTAssertEqual(m.key(code:key.rawValue,down:false,time:time+0.5).effects,[.scroll(0,false)])
            XCTAssertFalse(m.hasHeldScrollKeys)
            XCTAssertFalse(m.hasSwallowedKeys)
            XCTAssertEqual(m.mode,.navigation)
        }
    }
    func testPairOwnershipAcrossInputTransitions() {
        var m=configured()
        XCTAssertTrue(m.key(code:Key.i.rawValue,down:true,time:0).swallow)
        XCTAssertTrue(m.key(code:Key.i.rawValue,down:false,time:0).swallow)
        XCTAssertFalse(m.key(code:Key.a.rawValue,down:true,time:0).swallow)
        _=press(.escape,&m)
        XCTAssertFalse(m.key(code:Key.a.rawValue,down:false,time:0).swallow)
        XCTAssertTrue(m.key(code:Key.j.rawValue,down:true,time:0).swallow)
        _=press(.i,&m)
        XCTAssertTrue(m.key(code:Key.j.rawValue,down:false,time:0).swallow)
    }
    func testAutorepeatDoesNotIssueLabelActionAgain() {
        var m=configured()
        _=m.key(code:Key.w.rawValue,down:true,time:0)
        XCTAssertEqual(m.regionPrefix,"W")
        XCTAssertEqual(m.key(code:Key.w.rawValue,down:true,repeat:true,time:0.2).effects,[])
        XCTAssertEqual(m.regionPrefix,"W")
    }
    func testChooseRowExpandsWithoutActivatingAndRequiresCompleteCode() {
        var m=configured(); m.expandableRows=[10]
        XCTAssertEqual(press(.semicolon,&m).effects,[.scroll(0,false),.rowActions])
        XCTAssertTrue(m.choosingRow)
        _=press(.s,&m)
        XCTAssertTrue(press(.enter,&m).effects.isEmpty)
        XCTAssertEqual(press(.s,&m).effects,[.expandRow(10)])
        XCTAssertFalse(m.choosingRow); XCTAssertEqual(m.mode,.navigation)
        _=press(.s,&m)
        XCTAssertEqual(press(.s,&m).effects,[.click(10,.left)]) // Normal row activation remains unchanged.
    }
    func testChooseRowIgnoresNonRowAndSyntheticAnchorNeverClicks() {
        var m=configured(); m.expandableRows=[10]; m.disclosureTargets=[10]
        _=press(.semicolon,&m); _=press(.a,&m)
        XCTAssertFalse(press(.k,&m).effects.contains(.click(12,.left)))
        m.cancelRowSelection()
        _=press(.s,&m); XCTAssertEqual(press(.s,&m).effects,[.expandRow(10)])
        m.automaticClick=false
        _=press(.s,&m); _=press(.s,&m)
        XCTAssertEqual(press(.enter,&m,flags:.command).effects,[.expandRow(10)])
    }
    func testRowSelectionCancelsOnScopeInputAndExitWithoutKeyPairLeaks() {
        for key in [Key.space,.tab,.i,.escape,.j] {
            var m=configured(); m.expandableRows=[10]
            XCTAssertTrue(m.key(code:Key.semicolon.rawValue,down:true,time:0).swallow)
            XCTAssertTrue(m.key(code:Key.semicolon.rawValue,down:true,repeat:true,time:0.1).effects.isEmpty)
            XCTAssertTrue(m.key(code:Key.semicolon.rawValue,down:false,time:0.2).swallow)
            _=press(key,&m)
            XCTAssertFalse(m.choosingRow); XCTAssertFalse(m.hasSwallowedKeys)
        }
        var m=configured()
        XCTAssertFalse(press(.semicolon,&m,flags:.command).swallow)
        _=press(.i,&m); XCTAssertFalse(press(.semicolon,&m).swallow)
    }
    func testIncompleteRegionNeverClicksDefault() {
        var m=configured(); _=press(.s,&m); _=press(.w,&m)
        XCTAssertEqual(m.buttonPrefix,""); XCTAssertEqual(m.regionPrefix,"W")
        XCTAssertEqual(press(.enter,&m).effects,[])
        XCTAssertEqual(press(.e,&m).effects,[.selectRegion(4)])
    }
    func testTabAcrossNineAndBack() {
        var m=configured(); m.regions=Array(1...12).map(UInt64.init); m.selectedRegion=9
        XCTAssertEqual(press(.tab,&m).effects,[.selectRegion(10)])
        XCTAssertEqual(RegionCodes.group(regions:m.regions,selected:m.selectedRegion).map{$0.1},["W","E","R"])
        XCTAssertEqual(press(.tab,&m,flags:.shift).effects,[.selectRegion(9)])
    }
    func testDoubleGDeadlineAndShortcuts() {
        var m=configured()
        XCTAssertTrue(press(.g,&m,time:0).effects.isEmpty)
        XCTAssertTrue(press(.g,&m,time:0.71).effects.isEmpty)
        XCTAssertEqual(press(.g,&m,time:1).effects,[.jump(true)])
        XCTAssertEqual(press(.g,&m,flags:.shift).effects,[.jump(false)])
        XCTAssertFalse(press(.a,&m,flags:.command).swallow)
        XCTAssertEqual(press(.a,&m,flags:.command).effects,[.refreshShortcut])
    }
    func testHiddenPageCannotClickOldSelectedTarget() {
        var m=configured(); m.automaticClick=false; _=press(.s,&m); _=press(.s,&m)
        m.buttons=[(12,"AK")]
        XCTAssertEqual(press(.enter,&m).effects,[])
    }
    func testPartialButtonReturnCannotReusePreviousSelection() {
        var m=configured(); m.automaticClick=false
        _=press(.s,&m); _=press(.s,&m); _=press(.backspace,&m)
        XCTAssertEqual(m.buttonPrefix,"S"); XCTAssertEqual(press(.enter,&m).effects,[])
    }
    func testHeldIntentClearedByInterruptAndExit() {
        var m=configured(); _=m.key(code:38,down:true,time:0)
        XCTAssertEqual(m.scrollDirection,1); m.interruptScroll(); XCTAssertEqual(m.scrollDirection,0)
        _=m.key(code:38,down:false,time:1); _=m.key(code:40,down:true,time:2); m.deactivate(); m.activate(); XCTAssertEqual(m.scrollDirection,0)
    }
    func testBackoffAndTapRecovery() {
        var retry=RetryBackoff(); XCTAssertEqual((0..<8).map{_ in retry.next()},[0.1,0.2,0.4,0.8,1.6,2,2,2]); retry.reset(); XCTAssertEqual(retry.next(),0.1)
        var recovery=TapRecovery()
        XCTAssertFalse(recovery.shouldRecover(now:0,alreadyEnabled:true,timeout:true,sameSession:true,trusted:true))
        XCTAssertTrue(recovery.shouldRecover(now:0,alreadyEnabled:false,timeout:true,sameSession:true,trusted:true))
        XCTAssertTrue(recovery.shouldRecover(now:1,alreadyEnabled:false,timeout:true,sameSession:true,trusted:true))
        XCTAssertFalse(recovery.shouldRecover(now:2,alreadyEnabled:false,timeout:true,sameSession:true,trusted:true))
        XCTAssertTrue(recovery.shouldRecover(now:11,alreadyEnabled:false,timeout:true,sameSession:true,trusted:true))
        XCTAssertFalse(recovery.shouldRecover(now:12,alreadyEnabled:false,timeout:false,sameSession:true,trusted:true))
    }
    func testIdleDisableAndLateNotificationsNeverRequestAnotherDisable() {
        let effects=(0..<10000).filter{_ in TapRecovery.shouldHandleDisabledEvent(mode:.inactive,currentlyEnabled:false)}
        XCTAssertTrue(effects.isEmpty)
        XCTAssertFalse(TapRecovery.shouldHandleDisabledEvent(mode:.navigation,currentlyEnabled:true))
        XCTAssertTrue(TapRecovery.shouldHandleDisabledEvent(mode:.navigation,currentlyEnabled:false))
    }
}
