import Foundation
import XCTest
@testable import PywalPick

final class MatugenCandidateTests: XCTestCase {
    func testReadableSemanticExtremeUsesBalancedTonalAlternative() throws {
        let output = try MatugenThemeConverter.makePywalScheme(
            from: Self.fixtureWithExtremeTertiary,
            wallpaperPath: "/fixture.jpg",
            mode: .light,
            schemeType: .schemeTonalSpot
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        let colors = try XCTUnwrap(object["colors"] as? [String: String])
        let background = try ThemeColor(hex: XCTUnwrap(object["special"] as? [String: String])["background"]!)
        let tertiary = try ThemeColor(hex: XCTUnwrap(colors["color2"]))

        XCTAssertNotEqual(tertiary.hex, "#000000")
        XCTAssertGreaterThanOrEqual(tertiary.contrastRatio(to: background), 4.5)
        XCTAssertLessThan(tertiary.relativeLuminance, 0.25)
    }

    func testCandidateChoicesExcludeExtremeColorsWhenSafeTonesExist() throws {
        let candidates = try MatugenThemeConverter.makeColorCandidates(
            from: Self.fixtureWithExtremeTertiary,
            mode: .light,
            schemeType: .schemeTonalSpot
        )
        let tertiary = try XCTUnwrap(candidates.choices["color2"])
        XCTAssertFalse(tertiary.contains(where: \.nearExtreme))
    }

    func testRemotePreferencesDropAvoidableDuplicateAssignments() throws {
        let background = try ThemeColor(hex: "#101010")
        let foreground = try ThemeColor(hex: "#f0f0f0")
        let red = MatugenColorCandidate(
            id: "red", hex: "#cc3344", family: "error", tone: 60,
            contrast: 5.7, chroma: 0.6, nearExtreme: false
        )
        let blue = MatugenColorCandidate(
            id: "blue", hex: "#4488cc", family: "primary", tone: 60,
            contrast: 5.1, chroma: 0.53, nearExtreme: false
        )
        let green = MatugenColorCandidate(
            id: "green", hex: "#44aa66", family: "secondary", tone: 60,
            contrast: 6.0, chroma: 0.45, nearExtreme: false
        )
        let candidates = MatugenThemeCandidateSet(
            mode: .dark,
            schemeType: .schemeTonalSpot,
            background: background,
            foreground: foreground,
            choices: ["color1": [red, blue], "color2": [blue, green]],
            cursorChoices: [blue],
            localColors: ["color1": red.hex, "color2": green.hex],
            localCursor: blue.hex
        )

        let accepted = candidates.acceptedPreferences([
            "color1": blue.hex,
            "color2": blue.hex,
        ])
        XCTAssertEqual(accepted["color1"], blue.hex)
        XCTAssertNil(accepted["color2"])
    }

    private static let fixtureWithExtremeTertiary: Data = {
        let colors: [String: Any] = [
            "surface": ["dark": ["color": "#101010"], "light": ["color": "#fefefe"]],
            "on_surface": ["dark": ["color": "#f0f0f0"], "light": ["color": "#202020"]],
            "on_background": ["dark": ["color": "#f0f0f0"], "light": ["color": "#202020"]],
            "on_surface_variant": ["dark": ["color": "#d0d0d0"], "light": ["color": "#303030"]],
            "primary": ["dark": ["color": "#80b0ff"], "light": ["color": "#355a8a"]],
            "on_primary": ["dark": ["color": "#001122"], "light": ["color": "#ffffff"]],
            "error": ["dark": ["color": "#ffb4ab"], "light": ["color": "#ba1a1a"]],
            "secondary": ["dark": ["color": "#b8c8df"], "light": ["color": "#445a76"]],
            // This is technically readable on a near-white surface, but it is
            // an obviously poor ANSI choice when the tonal family has options.
            "tertiary": ["dark": ["color": "#d0b8ff"], "light": ["color": "#000000"]],
        ]
        let object: [String: Any] = [
            "mode": "light",
            "colors": colors,
            "palettes": paletteObject(),
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }()

    private static func paletteObject() -> [String: Any] {
        let families = ["error", "neutral", "neutral_variant", "primary", "secondary", "tertiary"]
        let tones = stride(from: 0, through: 100, by: 10).map(String.init)
        var palettes: [String: Any] = [:]
        for family in families {
            var values: [String: Any] = [:]
            for tone in tones {
                let value = Int(tone) ?? 0
                let channel = min(255, max(0, value * 255 / 100))
                let tint: (Int, Int, Int) = family == "neutral" || family == "neutral_variant"
                    ? (0, 0, 0)
                    : family == "error" ? (20, -12, -12)
                    : family == "primary" ? (-12, 4, 24)
                    : family == "secondary" ? (10, 4, -10)
                    : (18, -8, 12)
                let red = min(255, max(0, channel + tint.0))
                let green = min(255, max(0, channel + tint.1))
                let blue = min(255, max(0, channel + tint.2))
                values[tone] = ["color": String(format: "#%02x%02x%02x", red, green, blue)]
            }
            palettes[family] = values
        }
        return palettes
    }
}
