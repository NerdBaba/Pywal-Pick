import Foundation
import XCTest
@testable import PywalPick

final class MatugenPaletteExplorerTests: XCTestCase {
    func testSearchIncludesMatchingSemanticRolesAndTonalFamilies() throws {
        let document = try MatugenPaletteDocument(data: Self.fixture)

        let semantic = MatugenPaletteExplorer.filteredSemanticColors(
            in: document,
            query: "primary"
        )
        let tonal = MatugenPaletteExplorer.filteredTonalPalettes(
            in: document,
            query: "primary"
        )

        XCTAssertEqual(semantic.map(\.id), ["on_primary", "primary"])
        XCTAssertEqual(Set(tonal.keys), Set(["primary"]))
    }

    @MainActor
    func testExplorerExposesExactlyThreePaletteGroups() throws {
        let document = try MatugenPaletteDocument(data: Self.fixture)
        let model = MatugenPaletteExplorerModel(document: document)

        XCTAssertEqual(model.sectionCount, 3)
        XCTAssertEqual(model.filteredSemanticColors.count, 2)
        XCTAssertEqual(model.filteredBase16Colors.count, 1)
        XCTAssertEqual(model.filteredTonalPalettes.count, 2)
    }

    @MainActor
    func testMissingCacheProducesAnActionableState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pywalpick-explorer-missing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = MatugenPaletteExplorerModel(directory: directory)
        model.reload()

        XCTAssertNil(model.snapshot)
        XCTAssertTrue(model.errorMessage?.contains("No generated Matugen palette") == true)
    }

    @MainActor
    func testMalformedCacheProducesAnActionableState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pywalpick-explorer-invalid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(
            to: directory.appendingPathComponent(MatugenPaletteCache.rawColorsFileName)
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = MatugenPaletteExplorerModel(directory: directory)
        model.reload()

        XCTAssertNil(model.snapshot)
        XCTAssertTrue(model.errorMessage?.contains("could not be read") == true)
    }

    private static let fixture: Data = {
        let object: [String: Any] = [
            "mode": "dark",
            "colors": [
                "primary": ["dark": ["color": "#112233"], "light": ["color": "#aabbcc"]],
                "on_primary": ["dark": ["color": "#ffffff"], "light": ["color": "#000000"]],
            ],
            "base16": [
                "base00": ["dark": ["color": "#101010"]],
            ],
            "palettes": [
                "primary": ["10": ["color": "#223344"]],
                "neutral": ["10": ["color": "#334455"]],
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }()
}
