import XCTest
@testable import PywalPick

final class WallpaperThemeChoiceTests: XCTestCase {
    func testAllChoicesGroupExistingBackendsAndEveryMatugenScheme() {
        let pywalChoices = WallpaperThemeChoice.all.filter { $0.section == .pywal }
        let matugenChoices = WallpaperThemeChoice.all.filter { $0.section == .matugen }

        XCTAssertEqual(
            pywalChoices.map(\.backend),
            WalBackend.allCases.filter { !$0.isMatugen }
        )
        XCTAssertEqual(
            matugenChoices.map(\.schemeType),
            MatugenSchemeType.allCases
        )
    }

    func testMatugenChoiceUpdatesBackendAndSchemeWithoutChangingModeOrContrast() {
        var config = AppConfig.default
        config.matugenMode = .light
        config.matugenContrast = 0.35

        WallpaperThemeChoice.matugen(.schemeExpressive).apply(to: &config)

        XCTAssertEqual(config.selectedBackend, .matugen)
        XCTAssertEqual(config.matugenSchemeType, .schemeExpressive)
        XCTAssertEqual(config.matugenMode, .light)
        XCTAssertEqual(config.matugenContrast, 0.35)
    }

    func testBackendChoiceUsesBackendAndLeavesMatugenSettingsAlone() {
        var config = AppConfig.default
        config.matugenSchemeType = .schemeRainbow
        config.matugenMode = .light
        config.matugenContrast = -0.2

        WallpaperThemeChoice.backend(.colorz).apply(to: &config)

        XCTAssertEqual(config.selectedBackend, .colorz)
        XCTAssertEqual(config.matugenSchemeType, .schemeRainbow)
        XCTAssertEqual(config.matugenMode, .light)
        XCTAssertEqual(config.matugenContrast, -0.2)
    }

    func testKeyboardNavigatorMovesByGridAndReturnsFocusedChoice() {
        let choices: [WallpaperThemeChoice] = [
            .backend(.haishoku),
            .backend(.wal),
            .backend(.colorz),
            .matugen(.schemeExpressive),
            .matugen(.schemeMonochrome),
        ]
        var navigator = WallpaperThemeChoiceNavigator(
            choices: choices,
            selectedChoice: .backend(.wal)
        )

        XCTAssertEqual(navigator.focusedChoice, .backend(.wal))
        XCTAssertEqual(navigator.move(.down, columns: 3), .matugen(.schemeMonochrome))
        XCTAssertEqual(navigator.move(.left, columns: 3), .matugen(.schemeExpressive))
        XCTAssertEqual(navigator.move(.right, columns: 3), .matugen(.schemeMonochrome))
        XCTAssertEqual(navigator.move(.up, columns: 3), .backend(.wal))
        XCTAssertEqual(navigator.activate(), .backend(.wal))
    }

    func testNativeKeyCodesMapToPickerActions() {
        XCTAssertEqual(WallpaperThemeChoiceKeyAction(keyCode: 123), .move(.left))
        XCTAssertEqual(WallpaperThemeChoiceKeyAction(keyCode: 124), .move(.right))
        XCTAssertEqual(WallpaperThemeChoiceKeyAction(keyCode: 126), .move(.up))
        XCTAssertEqual(WallpaperThemeChoiceKeyAction(keyCode: 125), .move(.down))
        XCTAssertEqual(WallpaperThemeChoiceKeyAction(keyCode: 36), .activate)
        XCTAssertEqual(WallpaperThemeChoiceKeyAction(keyCode: 76), .activate)
        XCTAssertEqual(WallpaperThemeChoiceKeyAction(keyCode: 49), .activate)
        XCTAssertEqual(WallpaperThemeChoiceKeyAction(keyCode: 53), .dismiss)
        XCTAssertNil(WallpaperThemeChoiceKeyAction(keyCode: 0))
    }

    func testBrowserFocusTargetTracksTheActiveViewMode() {
        XCTAssertEqual(WallpaperBrowserFocusTarget(viewMode: .grid), .grid)
        XCTAssertEqual(WallpaperBrowserFocusTarget(viewMode: .carousel), .carousel)
    }

    func testEachChoiceUsesANameAppropriateFontStyle() {
        XCTAssertEqual(
            WallpaperThemeChoice.backend(.fastColorthief).fontStyle,
            .monospaced
        )
        XCTAssertEqual(
            WallpaperThemeChoice.backend(.wal).fontStyle,
            .monospaced
        )
        XCTAssertEqual(
            WallpaperThemeChoice.backend(.haishoku).fontStyle,
            .serif
        )
        XCTAssertEqual(
            WallpaperThemeChoice.matugen(.schemeExpressive).fontStyle,
            .serif
        )
        XCTAssertEqual(
            WallpaperThemeChoice.matugen(.schemeMonochrome).fontStyle,
            .monospaced
        )

        XCTAssertEqual(
            Set(WallpaperThemeChoice.all.map(\.fontStyle)),
            Set(WallpaperThemeChoiceFontStyle.allCases)
        )
    }
}
