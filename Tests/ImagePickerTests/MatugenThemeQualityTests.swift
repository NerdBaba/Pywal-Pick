import Foundation
import XCTest
@testable import PywalPick

final class MatugenThemeQualityTests: XCTestCase {
    func testEverySchemeAndModeProducesReadableCanonicalPalette() throws {
        for mode in MatugenMode.allCases {
            for scheme in MatugenSchemeType.allCases {
                let data = Self.fixtureData()
                let output = try MatugenThemeConverter.makePywalScheme(
                    from: data,
                    wallpaperPath: "/fixture.jpg",
                    mode: mode,
                    schemeType: scheme
                )
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
                let colors = try XCTUnwrap(object["colors"] as? [String: String])
                let special = try XCTUnwrap(object["special"] as? [String: String])
                XCTAssertEqual(Set(colors.keys), Set((0..<16).map { "color\($0)" }), "\(mode)/\(scheme)")

                let background = try ThemeColor(hex: XCTUnwrap(special["background"]))
                XCTAssertEqual(colors["color0"], background.hex)
                for slot in 1..<16 {
                    let color = try ThemeColor(hex: XCTUnwrap(colors["color\(slot)"]))
                    XCTAssertGreaterThanOrEqual(
                        color.contrastRatio(to: background),
                        4.5,
                        "color\(slot) failed for \(mode)/\(scheme)"
                    )
                }
                let foreground = try ThemeColor(hex: XCTUnwrap(special["foreground"]))
                XCTAssertGreaterThanOrEqual(foreground.contrastRatio(to: background), 4.5)
                let cursor = try ThemeColor(hex: XCTUnwrap(special["cursor"]))
                XCTAssertGreaterThanOrEqual(cursor.contrastRatio(to: background), 3)
            }
        }
    }

    func testMonochromeAndNeutralUseNeutralTonalFamily() throws {
        let data = Self.fixtureData()
        let monochrome = try Self.colors(from: MatugenThemeConverter.makePywalScheme(
            from: data, wallpaperPath: "/fixture.jpg", mode: .dark, schemeType: .schemeMonochrome
        ))
        let neutral = try Self.colors(from: MatugenThemeConverter.makePywalScheme(
            from: data, wallpaperPath: "/fixture.jpg", mode: .dark, schemeType: .schemeNeutral
        ))
        let expressive = try Self.colors(from: MatugenThemeConverter.makePywalScheme(
            from: data, wallpaperPath: "/fixture.jpg", mode: .dark, schemeType: .schemeExpressive
        ))
        XCTAssertEqual(monochrome["color4"], neutral["color4"])
        XCTAssertNotEqual(monochrome["color4"], expressive["color4"])
        for value in monochrome.values {
            let rgb = try ThemeColor(hex: value).hex
            XCTAssertLessThanOrEqual(Set([rgb.dropFirst().prefix(2), rgb.dropFirst(2).prefix(2), rgb.dropFirst(4).prefix(2)]).count, 2)
        }
    }

    func testRequestedModeCannotUseOppositeModeColor() throws {
        let object: [String: Any] = [
            "colors": [
                "surface": ["dark": ["color": "#101010"]],
                "on_surface": ["dark": ["color": "#f0f0f0"]],
                "on_background": ["dark": ["color": "#f0f0f0"]],
                "primary": ["dark": ["color": "#80b0ff"]],
                "on_primary": ["dark": ["color": "#001122"]],
                "on_surface_variant": ["dark": ["color": "#d0d0d0"]],
            ],
            "base16": ["base00": ["dark": ["color": "#101010"]]],
            "palettes": Self.paletteObject(),
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try MatugenThemeConverter.makePywalScheme(
            from: data, wallpaperPath: "/fixture.jpg", mode: .light, schemeType: .schemeTonalSpot
        )) { error in
            guard case MatugenThemeError.missingColor("surface") = error else {
                return XCTFail("Expected missing light surface, got \(error)")
            }
        }
    }

    func testSystemAccentReadsMaterialPrimaryInsteadOfANSIColor7() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("matugen-accent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.fixtureData().write(to: directory.appendingPathComponent("matugen-colors.json"))

        XCTAssertEqual(
            try MatugenSystemAccent.primary(in: directory, mode: .dark),
            "#80b0ff"
        )
    }

    private static func colors(from data: Data) throws -> [String: String] {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["colors"] as? [String: String])
    }

    private static func fixtureData() -> Data {
        let colors: [String: Any] = [
            "surface": ["dark": ["color": "#101010"], "light": ["color": "#fefefe"]],
            "on_surface": ["dark": ["color": "#f0f0f0"], "light": ["color": "#101010"]],
            "on_background": ["dark": ["color": "#f0f0f0"], "light": ["color": "#101010"]],
            "primary": ["dark": ["color": "#80b0ff"], "light": ["color": "#355a8a"]],
            "on_primary": ["dark": ["color": "#001122"], "light": ["color": "#ffffff"]],
            "on_surface_variant": ["dark": ["color": "#d0d0d0"], "light": ["color": "#303030"]],
        ]
        let object: [String: Any] = [
            "mode": "dark",
            "colors": colors,
            "base16": ["base00": ["dark": ["color": "#101010"]]],
            "palettes": paletteObject(),
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }

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
