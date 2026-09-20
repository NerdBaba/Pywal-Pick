import XCTest
@testable import PywalPick

final class SettingsLayoutTests: XCTestCase {
    func testSettingsPagesUseTheSharedExpandedGroupRhythm() {
        XCTAssertEqual(UIStyle.settingsGroupSpacing, 28)
    }
}
