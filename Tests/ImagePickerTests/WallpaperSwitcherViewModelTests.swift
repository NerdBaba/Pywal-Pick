import XCTest
@testable import ImagePicker

@MainActor
final class WallpaperSwitcherViewModelTests: XCTestCase {
    
    func testHighlightedIndexResetsOnSearchQueryChange() {
        let viewModel = WallpaperSwitcherViewModel()
        viewModel.highlightedIndex = 5
        
        viewModel.searchQuery = "test"
        
        XCTAssertNil(viewModel.highlightedIndex, "highlightedIndex should be nil after searchQuery changes")
    }

    func testCustomScriptPathDefaultIsEmpty() {
        let config = AppConfig.default
        XCTAssertEqual(config.customScriptPath, "", "customScriptPath should default to empty string")
    }

    func testCustomScriptPathCodable() throws {
        var config = AppConfig.default
        config.customScriptPath = "/usr/local/bin/my-script.sh"

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded.customScriptPath, "/usr/local/bin/my-script.sh", "customScriptPath should survive encode/decode round-trip")
    }
}
