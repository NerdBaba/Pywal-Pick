import XCTest
@testable import PywalPick

private actor StubWallhavenAPI: WallhavenSearching {
    enum Result: Sendable {
        case success(WallhavenSearchResponse)
        case failure(WallhavenError)
    }

    private(set) var requests: [WallhavenSearchParams] = []
    private let result: Result

    init(result: Result) {
        self.result = result
    }

    func search(params: WallhavenSearchParams, apiKey: String?) async throws -> WallhavenSearchResponse {
        requests.append(params)
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    func requestCount() -> Int {
        requests.count
    }
}

private actor DelayedWallhavenAPI: WallhavenSearching {
    private let responses: [String: WallhavenSearchResponse]
    private let delayedQuery: String

    init(responses: [String: WallhavenSearchResponse], delayedQuery: String) {
        self.responses = responses
        self.delayedQuery = delayedQuery
    }

    func search(params: WallhavenSearchParams, apiKey: String?) async throws -> WallhavenSearchResponse {
        if params.query == delayedQuery {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        return responses[params.query] ?? responses[""]!
    }
}

private actor PagingWallhavenAPI: WallhavenSearching {
    private let pages: [Int: WallhavenSearchResponse]
    private(set) var requests: [WallhavenSearchParams] = []

    init(firstPage: WallhavenSearchResponse, secondPage: WallhavenSearchResponse) {
        pages = [1: firstPage, 2: secondPage]
    }

    init(pages: [Int: WallhavenSearchResponse]) {
        self.pages = pages
    }

    func search(params: WallhavenSearchParams, apiKey: String?) async throws -> WallhavenSearchResponse {
        requests.append(params)
        return pages[params.page] ?? pages[1]!
    }
}

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

    func testSearchQueryDoesNotRequestUntilSubmitted() async {
        let api = StubWallhavenAPI(result: .success(makeWallhavenResponse()))
        let viewModel = WallhavenViewModel(api: api)

        viewModel.searchQuery = "cats"

        let countBeforeSubmit = await api.requestCount()
        XCTAssertEqual(countBeforeSubmit, 0)
        await viewModel.submitSearch()
        let countAfterSubmit = await api.requestCount()
        XCTAssertEqual(countAfterSubmit, 1)
        XCTAssertEqual(viewModel.results.map(\.id), ["abc"])
    }

    func testSubmitSearchTrimsQueryBeforeRequest() async {
        let api = StubWallhavenAPI(result: .success(makeWallhavenResponse()))
        let viewModel = WallhavenViewModel(api: api)

        viewModel.searchQuery = "  cats and dogs  "
        await viewModel.submitSearch()

        let requests = await api.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].query, "cats and dogs")
        XCTAssertEqual(viewModel.searchQuery, "cats and dogs")
    }

    func testWhitespaceQueryIsSentAsBrowseRequestWithoutQueryParameter() async {
        var params = WallhavenSearchParams()
        params.query = " \n\t "

        let queryItem = params.buildQueryItems().first { $0.name == "q" }

        XCTAssertNil(queryItem)
    }

    func testWallhavenResponseDecodesStringQueryMetadata() throws {
        let data = Data(
            """
            {
              "data": [],
              "meta": {
                "current_page": 1,
                "last_page": 14,
                "per_page": 24,
                "total": 334,
                "query": "doom",
                "seed": null
              }
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(WallhavenSearchResponse.self, from: data)

        XCTAssertEqual(response.meta.query, "doom")
    }

    func testSearchErrorClearsLoadingAndSurfacesMessage() async {
        let api = StubWallhavenAPI(result: .failure(.rateLimited))
        let viewModel = WallhavenViewModel(api: api)
        viewModel.searchQuery = "cats"

        await viewModel.submitSearch()

        XCTAssertTrue(viewModel.hasError)
        XCTAssertEqual(viewModel.errorMessage, WallhavenError.rateLimited.localizedDescription)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isLoadingMore)
    }

    func testNewSubmittedQueryCannotBeOverwrittenByOlderResponse() async {
        let api = DelayedWallhavenAPI(
            responses: [
                "old": makeWallhavenResponse(id: "old"),
                "new": makeWallhavenResponse(id: "new")
            ],
            delayedQuery: "old"
        )
        let viewModel = WallhavenViewModel(api: api)

        viewModel.searchQuery = "old"
        let oldSearch = Task { await viewModel.submitSearch() }
        try? await Task.sleep(nanoseconds: 25_000_000)

        viewModel.searchQuery = "new"
        await viewModel.submitSearch()
        await oldSearch.value

        XCTAssertEqual(viewModel.results.map(\.id), ["new"])
        XCTAssertFalse(viewModel.isLoading)
    }

    func testPaginationKeepsSubmittedQueryAndAppendsResults() async {
        let api = PagingWallhavenAPI(
            firstPage: makeWallhavenResponse(id: "first", currentPage: 1, lastPage: 2, total: 2),
            secondPage: makeWallhavenResponse(id: "second", currentPage: 2, lastPage: 2, total: 2)
        )
        let viewModel = WallhavenViewModel(api: api)
        viewModel.searchQuery = "cats"

        await viewModel.submitSearch()
        await viewModel.loadNextPage()

        let requests = await api.requests
        XCTAssertEqual(requests.map(\.page), [1, 2])
        XCTAssertEqual(requests.map(\.query), ["cats", "cats"])
        XCTAssertEqual(viewModel.results.map(\.id), ["first", "second"])
        XCTAssertFalse(viewModel.hasMorePages)
    }

    func testPrefetchLoadsOnePagePerLoadedPage() async {
        let api = PagingWallhavenAPI(pages: [
            1: makeWallhavenResponse(id: "first", currentPage: 1, lastPage: 3, total: 3),
            2: makeWallhavenResponse(id: "second", currentPage: 2, lastPage: 3, total: 3),
            3: makeWallhavenResponse(id: "third", currentPage: 3, lastPage: 3, total: 3)
        ])
        let viewModel = WallhavenViewModel(api: api)
        viewModel.searchQuery = "cats"

        await viewModel.submitSearch()
        await viewModel.prefetchNextPageIfNeeded(for: 1)
        await viewModel.prefetchNextPageIfNeeded(for: 1)

        var requests = await api.requests
        XCTAssertEqual(requests.map(\.page), [1, 2])
        XCTAssertEqual(viewModel.results.map(\.id), ["first", "second"])

        await viewModel.prefetchNextPageIfNeeded(for: 2)

        requests = await api.requests
        XCTAssertEqual(requests.map(\.page), [1, 2, 3])
        XCTAssertEqual(viewModel.results.map(\.id), ["first", "second", "third"])
        XCTAssertFalse(viewModel.hasMorePages)
    }

    func testPrefetchTriggerStartsTwoRowsBeforeEnd() {
        XCTAssertEqual(
            WallhavenViewModel.prefetchTriggerIndex(resultCount: 24, columns: 4),
            16
        )
        XCTAssertEqual(
            WallhavenViewModel.prefetchTriggerIndex(resultCount: 48, columns: 6),
            36
        )
    }

    func testClearSearchReloadsBrowseResults() async {
        let api = StubWallhavenAPI(result: .success(makeWallhavenResponse()))
        let viewModel = WallhavenViewModel(api: api)
        viewModel.searchQuery = "cats"

        viewModel.clearSearch()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let requestCount = await api.requestCount()
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(viewModel.searchQuery.isEmpty)
        XCTAssertEqual(viewModel.results.map(\.id), ["abc"])
    }

    private func makeWallhavenResponse(
        id: String = "abc",
        currentPage: Int = 1,
        lastPage: Int = 1,
        total: Int = 1
    ) -> WallhavenSearchResponse {
        WallhavenSearchResponse(
            data: [
                WallhavenWallpaper(
                    id: id,
                    url: "https://wallhaven.cc/w/\(id)",
                    shortUrl: "https://w.wallhaven.cc/\(id)",
                    views: 1,
                    favorites: 1,
                    source: nil,
                    purity: "sfw",
                    category: "general",
                    dimensionX: 1920,
                    dimensionY: 1080,
                    resolution: "1920x1080",
                    ratio: "16x9",
                    fileSize: 100,
                    fileType: "image/jpeg",
                    createdAt: "2026-01-01 00:00:00",
                    colors: ["#000000"],
                    path: "https://w.wallhaven.cc/full/\(id).jpg",
                    thumbs: WallhavenThumbs(
                        large: "https://th.wallhaven.cc/lg/\(id).jpg",
                        original: "https://w.wallhaven.cc/full/\(id).jpg",
                        small: "https://th.wallhaven.cc/sm/\(id).jpg"
                    )
                )
            ],
            meta: WallhavenMeta(
                currentPage: currentPage,
                lastPage: lastPage,
                perPage: 24,
                total: total,
                query: nil,
                seed: nil
            )
        )
    }
}
