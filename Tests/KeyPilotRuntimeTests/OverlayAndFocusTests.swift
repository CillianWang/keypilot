import XCTest
import AppKit
import KeyPilotCore
@testable import KeyPilot

final class OverlayAndFocusTests:XCTestCase {
    func testRowHoverSendsOnlyMotionAndRestoresOriginalHover() {
        let original=CGPoint(x:45,y:65)
        var pointer=original,events:[CGEvent]=[]
        let poster=InputPoster(queue:DispatchQueue(label:"hover-test"),emit:{events.append($0)},pointer:{pointer},warp:{pointer=$0})
        poster.hover(point:Point(200,300))
        XCTAssertEqual(pointer,CGPoint(x:200,y:300))
        XCTAssertEqual(events.map(\.type),[.mouseMoved])
        XCTAssertEqual(events.first?.getIntegerValueField(.eventSourceUserData),postedEventMarker)
        poster.restorePointer()
        XCTAssertEqual(pointer,original)
        XCTAssertEqual(events.map(\.type),[.mouseMoved,.mouseMoved])
        XCTAssertEqual(events.last?.location,original)
    }
    func testRowHoverNeverRestoresOverUsersOwnPointerMovement() {
        var pointer=CGPoint(x:45,y:65),events:[CGEvent]=[]
        let poster=InputPoster(queue:DispatchQueue(label:"hover-movement-test"),emit:{events.append($0)},pointer:{pointer},warp:{pointer=$0})
        poster.hover(point:Point(200,300))
        pointer=CGPoint(x:500,y:600)
        poster.restorePointer()
        XCTAssertEqual(pointer,CGPoint(x:500,y:600)); XCTAssertEqual(events.count,1)
    }
    func testFreshKeyboardApplicationIdentityAcrossRefreshesAndSwitches() {
        var keyboardPID:pid_t?=431
        let reader=SystemAXReader(pid:431,registry:AXRegistry(),keyboardApplicationPID:{keyboardPID})
        // Repeated post-scroll/post-click validations keep the same application's session.
        for _ in 0..<8 { reader.begin(); XCTAssertTrue(reader.frontmostMatches()) }
        // A real switch and a temporarily unknown keyboard receiver must reject actions.
        keyboardPID=433; XCTAssertFalse(reader.frontmostMatches())
        keyboardPID=nil; XCTAssertFalse(reader.frontmostMatches())
        keyboardPID=0; XCTAssertNil(reader.frontmostPID())
        keyboardPID=431; XCTAssertTrue(reader.frontmostMatches())
        XCTAssertEqual(reader.calls,0) // No AX focus IPC or AX permission needed for this check.
    }
    func testOverlayCannotTakeKeyboardFocusOrMouseInput() {
        _=NSApplication.shared
        let panel=OverlayPanel(screenFrame:NSRect(x:0,y:0,width:300,height:200))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeKey); XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.ignoresMouseEvents); XCTAssertFalse(panel.hidesOnDeactivate)
        panel.close()
    }
    func testGlassLabelReusesMaterialAndHonorsReducedTransparency() {
        _=NSApplication.shared
        let label=GlassLabelView(),frame=NSRect(x:20,y:20,width:35,height:23)
        var style=LabelAppearance(code:"SS",fontSize:13,prefix:"S",selected:false,region:false,reduceTransparency:false)
        label.update(frame:frame,appearance:style)
        let effect=label.effect
        XCTAssertEqual(effect.blendingMode,.behindWindow); XCTAssertEqual(effect.state,.active)
        XCTAssertFalse(effect.isHidden); XCTAssertNotNil(effect.maskImage)
        XCTAssertNil(label.hitTest(.zero))
        style.code="AA"; style.selected=true; label.update(frame:frame,appearance:style)
        XCTAssertTrue(effect === label.effect)
        style.reduceTransparency=true; label.update(frame:frame,appearance:style)
        XCTAssertTrue(effect.isHidden); XCTAssertEqual(label.appearanceValue?.tintAlpha,1)
        style.style = .dark; label.update(frame:frame,appearance:style)
        XCTAssertEqual(label.appearance?.name,.darkAqua)
        style.style = .system; label.update(frame:frame,appearance:style)
        XCTAssertNil(label.appearance)
    }
}
