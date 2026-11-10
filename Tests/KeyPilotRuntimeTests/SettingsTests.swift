import XCTest
import AppKit
@testable import KeyPilot

final class SettingsTests:XCTestCase {
    func testSliderKeyboardAndAccessibilityShareBoundedSteps() {
        _=NSApplication.shared
        let slider=SteppedSettingsSlider()
        slider.minValue=300; slider.maxValue=2000; slider.increment=50; slider.doubleValue=900
        let right=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:124)!
        slider.keyDown(with:right); XCTAssertEqual(slider.doubleValue,950)
        XCTAssertTrue(slider.accessibilityPerformDecrement()); XCTAssertEqual(slider.doubleValue,900)
        slider.doubleValue=2000; XCTAssertFalse(slider.accessibilityPerformIncrement()); XCTAssertEqual(slider.doubleValue,2000)
        slider.doubleValue=300; XCTAssertFalse(slider.accessibilityPerformDecrement()); XCTAssertEqual(slider.doubleValue,300)
    }
    func testIsolatedSettingsPersistEditsWithoutResettingExistingPreferences() {
        let suite="KeyPilotTests.\(UUID().uuidString)"
        // Use the same explicit domain for both readers; never mutate .standard.
        let isolated=UserDefaults(suiteName:suite)!
        defer { isolated.removePersistentDomain(forName:suite) }
        isolated.set(1250.0,forKey:"speed"); isolated.set(false,forKey:"foldRowActions"); isolated.set("tea",forKey:"glassStyle")
        let original=Settings(defaults:isolated,observeSystem:false)
        original.values.fontSize=17
        let reopened=Settings(defaults:isolated,observeSystem:false)
        XCTAssertEqual(reopened.values.fontSize,17); XCTAssertEqual(reopened.values.speed,1250)
        XCTAssertFalse(reopened.values.foldRowActions); XCTAssertEqual(reopened.values.glassStyle,.tea)
    }
}
