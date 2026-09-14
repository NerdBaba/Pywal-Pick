import XCTest
@testable import PywalPick

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

    func testDeleteWallpaperRemovesFileAndUpdatesCollections() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let fileURL = folder.appendingPathComponent("wallpaper.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: fileURL)
        let wallpaper = ImageFile(url: fileURL)
        let viewModel = WallpaperSwitcherViewModel()
        viewModel.wallpapers = [wallpaper]
        viewModel.updateFilteredWallpapers()
        viewModel.currentWallpaper = wallpaper
        viewModel.highlightedIndex = 0

        try viewModel.deleteWallpaper(wallpaper)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(viewModel.wallpapers.isEmpty)
        XCTAssertTrue(viewModel.filteredWallpapers.isEmpty)
        XCTAssertNil(viewModel.currentWallpaper)
        XCTAssertNil(viewModel.highlightedIndex)
    }

    func testDownloadProgressClampsToUnitInterval() {
        XCTAssertEqual(
            DownloadProgress(bytesDownloaded: 150, totalBytes: 100).fractionCompleted,
            1.0
        )
        XCTAssertEqual(
            DownloadProgress(bytesDownloaded: -1, totalBytes: 100).fractionCompleted,
            0.0
        )
    }

    func testDownloadedIdsStaticIgnoresDirectories() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        try Data([0xFF]).write(to: folder.appendingPathComponent("wallhaven-abc.jpg"))
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("wallhaven-not-a-file"),
            withIntermediateDirectories: false
        )

        let ids = WallhavenDownloader.downloadedIdsStatic(in: folder.path)

        XCTAssertEqual(ids, ["abc"])
    }

    func testDownloadAnimationStateCanBeShownAndDismissed() {
        let viewModel = WallhavenViewModel()

        viewModel.showDownloadAnimation(for: "abc")
        XCTAssertTrue(viewModel.downloadAnimationIDs.contains("abc"))

        viewModel.dismissDownloadAnimation(for: "abc")
        XCTAssertFalse(viewModel.downloadAnimationIDs.contains("abc"))
    }
}
