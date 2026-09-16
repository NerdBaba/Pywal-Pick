import Foundation
import XCTest
@testable import PywalPick

final class MatugenPaletteDocumentTests: XCTestCase {
    func testDecodesModernLegacyAndDirectColorShapes() throws {
        var colors: [String: Any] = [:]
        for index in 0..<48 {
            colors["role\(index)"] = [
                "dark": ["color": String(format: "#%06x", index)],
                "light": String(format: "%06x", 0x100000 + index),
            ]
        }
        colors["primary"] = [
            "dark": ["color": "#112233"],
            "light": "aabbcc",
        ]
        colors["on_primary"] = "#ffffff"

        var base16: [String: Any] = [:]
        for index in 0..<16 {
            base16[String(format: "base%02x", index)] = [
                "dark": ["color": String(format: "#%06x", 0x200000 + index)],
                "light": String(format: "%06x", 0x300000 + index),
            ]
        }

        var palettes: [String: Any] = [:]
        for family in ["primary", "secondary", "tertiary", "neutral", "neutral_variant", "error"] {
            palettes[family] = [
                "0": ["color": "#000000"],
                "10": "ffffff",
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: [
            "mode": "light",
            "is_dark_mode": false,
            "image": "/tmp/wallpaper.png",
            "colors": colors,
            "base16": base16,
            "palettes": palettes,
        ])

        let document = try MatugenPaletteDocument(data: data)

        XCTAssertEqual(document.mode, .light)
        XCTAssertEqual(document.isDarkMode, false)
        XCTAssertEqual(document.imagePath, "/tmp/wallpaper.png")
        XCTAssertEqual(document.semanticColors.count, 50)
        XCTAssertEqual(document.base16Colors.count, 16)
        XCTAssertEqual(document.tonalPalettes.count, 6)
        XCTAssertEqual(document.semanticColors["primary"]?.value(for: .dark), "#112233")
        XCTAssertEqual(document.semanticColors["primary"]?.value(for: .light), "#aabbcc")
        XCTAssertEqual(document.semanticColors["on_primary"]?.value(for: .dark), "#ffffff")
        XCTAssertEqual(document.base16Colors["base00"]?.value(for: .light), "#300000")
        XCTAssertEqual(document.tonalPalettes["primary"]?["10"], "#ffffff")
    }

    func testFallsBackToAvailableModeValueWhenTheRequestedModeIsMissing() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "colors": [
                "dark_only": ["dark": ["color": "#112233"]],
                "light_only": ["light": ["color": "#aabbcc"]],
                "default_only": ["default": ["color": "#445566"]],
            ],
        ])

        let document = try MatugenPaletteDocument(data: data)

        XCTAssertEqual(document.semanticColors["dark_only"]?.value(for: .light), "#112233")
        XCTAssertEqual(document.semanticColors["light_only"]?.value(for: .dark), "#aabbcc")
        XCTAssertEqual(document.semanticColors["default_only"]?.value(for: .dark), "#445566")
    }

    func testDecodesGroupedLegacyThemeVariantsWithoutDroppingAmoled() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "colors": [
                "dark": [
                    "surface": "#101010",
                    "primary": "#112233",
                ],
                "light": [
                    "surface": "#fefefe",
                    "primary": "#445566",
                ],
                "amoled": [
                    "surface": "#000000",
                    "primary": "#aabbcc",
                ],
                "high_contrast": [
                    "surface": "#010101",
                    "primary": "#ffffff",
                ],
            ],
        ])

        let document = try MatugenPaletteDocument(data: data)

        XCTAssertEqual(document.semanticColors["surface"]?.value(for: .dark), "#101010")
        XCTAssertEqual(document.semanticColors["surface"]?.value(for: .light), "#fefefe")
        XCTAssertEqual(document.semanticColors["surface"]?.value(for: "amoled"), "#000000")
        XCTAssertEqual(document.semanticColors["primary"]?.value(for: "amoled"), "#aabbcc")
        XCTAssertEqual(document.semanticColors["surface"]?.value(for: "high_contrast"), "#010101")
        XCTAssertTrue(document.availableVariants.contains("amoled"))
        XCTAssertTrue(document.availableVariants.contains("high_contrast"))
    }

    func testDecodesValueWrappedColorsAndAStandaloneNamedVariantGroup() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "colors": [
                "amoled": [
                    "surface": ["value": "#000000"],
                    "primary": ["value": "112233"],
                ],
            ],
        ])

        let document = try MatugenPaletteDocument(data: data)

        XCTAssertEqual(document.semanticColors.count, 2)
        XCTAssertEqual(document.semanticColors["surface"]?.value(for: "amoled"), "#000000")
        XCTAssertEqual(document.semanticColors["primary"]?.value(for: "amoled"), "#112233")
        XCTAssertEqual(document.availableVariants, ["amoled"])
    }

    func testRejectsNonObjectJson() {
        XCTAssertThrowsError(try MatugenPaletteDocument(data: Data("[]".utf8)))
    }
}
