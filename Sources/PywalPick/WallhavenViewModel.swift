import Foundation
import SwiftUI
import Combine

@MainActor
final class WallhavenViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var results: [WallhavenWallpaper] = []
    @Published var isLoading: Bool = false
    @Published var hasError: Bool = false
    @Published var errorMessage: String = ""
    @Published var hasMorePages: Bool = false
    @Published var currentPage: Int = 1
    @Published var totalResults: Int = 0
    @Published var isLoadingMore = false

    @Published var params = WallhavenSearchParams()
    @Published var showFilters: Bool = false

    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadedIds: Set<String> = []
    @Published private(set) var downloadAnimationIDs: Set<String> = []
    @Published var toastMessage: String?
    @Published var showToast = false
    @Published var toastIsError = false

    @Published var selectedWallpaper: WallhavenWallpaper?
    @Published var showPreview: Bool = false

    @Published var apiKey: String = ""

    private var searchTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let api: any WallhavenSearching
    private let downloader = WallhavenDownloader.shared

    private var isPrefetching = false
    private var lastPrefetchedPage: Int?
    private var activeSearchID: UUID?
    private var activeSearchQuery = ""
    private var defaultsSignature: String?
    private var filterDebounceTask: Task<Void, Never>?
    private var downloadedScanTask: Task<Void, Never>?
    private var lastScannedFolder = ""
    private var lastScanDate = Date.distantPast
    private var viewActive = true
    private var downloadAnimationTasks: [String: Task<Void, Never>] = [:]

    init(api: any WallhavenSearching = WallhavenAPI.shared) {
        self.api = api
        setupQueryChangeHandling()
        let config = AppConfig.load()
        apiKey = config.wallhavenAPIKey
        params = Self.params(from: config)
        defaultsSignature = Self.signature(from: config)
    }

    private static func signature(from config: AppConfig) -> String {
        [
            config.wallhavenAPIKey,
            config.wallhavenDefaultCategories.sorted().joined(separator: ","),
            config.wallhavenDefaultPurity.sorted().joined(separator: ","),
            config.wallhavenDefaultSorting,
            config.wallhavenDefaultOrder,
            config.wallhavenDefaultTopRange,
            config.wallhavenDefaultAtLeast,
            config.wallhavenDefaultRatios.sorted().joined(separator: ","),
            config.wallhavenDefaultColor
        ].joined(separator: "|")
    }

    private static func params(from config: AppConfig) -> WallhavenSearchParams {
        var next = WallhavenSearchParams()
        next.categories = Set(config.wallhavenDefaultCategories.compactMap(WallhavenCategory.init(rawValue:)))
        if next.categories.isEmpty { next.categories = [.general, .anime, .people] }
        next.purity = Set(config.wallhavenDefaultPurity.compactMap(WallhavenPurity.init(rawValue:)))
        if next.purity.isEmpty { next.purity = [.sfw] }
        next.sorting = WallhavenSorting(rawValue: config.wallhavenDefaultSorting) ?? .dateAdded
        next.order = config.wallhavenDefaultOrder.isEmpty ? "desc" : config.wallhavenDefaultOrder
        next.topRange = WallhavenToplistRange(rawValue: config.wallhavenDefaultTopRange) ?? .oneMonth
        next.atLeast = config.wallhavenDefaultAtLeast.isEmpty ? nil : config.wallhavenDefaultAtLeast
        next.ratios = config.wallhavenDefaultRatios
        next.color = config.wallhavenDefaultColor.isEmpty ? nil : WallhavenColor(rawValue: config.wallhavenDefaultColor)
        next.page = 1
        next.seed = nil
        return next
    }

    func applyDefaults(from config: AppConfig) {
        apiKey = config.wallhavenAPIKey
        let signature = Self.signature(from: config)
        guard signature != defaultsSignature else { return }
        defaultsSignature = signature
        params = Self.params(from: config)
    }

    /// Re-read defaults (e.g. after Settings changes) and refresh if they changed.
    func refreshDefaults(from config: AppConfig) async {
        let before = defaultsSignature
        applyDefaults(from: config)
        if before != defaultsSignature {
            await search()
        }
    }

    private func setupQueryChangeHandling() {
        $searchQuery
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.cancelSearchForQueryEdit()
            }
            .store(in: &cancellables)
    }

    private func resetPaginationLocked() {
        prefetchTask?.cancel()
        prefetchTask = nil
        currentPage = 1
        params.page = 1
        hasMorePages = false
        isPrefetching = false
        lastPrefetchedPage = nil
    }

    func submitSearch() async {
        let normalizedQuery = normalizeSearchQuery(searchQuery)
        if searchQuery != normalizedQuery {
            searchQuery = normalizedQuery
        }
        guard !(isLoading && activeSearchQuery == normalizedQuery) else { return }
        await performSearch(query: normalizedQuery)
    }

    func search() async {
        await performSearch(query: normalizeSearchQuery(searchQuery))
    }

    private func performSearch(query: String) async {
        searchTask?.cancel()
        let searchID = UUID()
        activeSearchID = searchID
        activeSearchQuery = query

        resetPaginationLocked()
        results = []
        totalResults = 0
        hasError = false
        errorMessage = ""

        let task = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled, activeSearchID == searchID else { return }
            isLoading = true
            isLoadingMore = false

            defer {
                if activeSearchID == searchID {
                    isLoading = false
                    isLoadingMore = false
                }
            }

            do {
                var requestParams = params
                requestParams.query = query
                requestParams.page = 1
                let response = try await api.search(
                    params: requestParams,
                    apiKey: apiKey.isEmpty ? nil : apiKey
                )

                guard !Task.isCancelled, activeSearchID == searchID else { return }

                results = response.data
                hasMorePages = response.meta.currentPage < response.meta.lastPage
                currentPage = response.meta.currentPage
                totalResults = response.meta.total

                checkDownloadedStatus()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, activeSearchID == searchID else { return }
                hasError = true
                errorMessage = error.localizedDescription
            }
        }

        searchTask = task
        await task.value
        if activeSearchID == searchID {
            searchTask = nil
        }
    }

    func loadNextPage() async {
        await loadNextPage(isPrefetch: false)
    }

    /// Returns the first item index in the last two grid rows.
    static func prefetchTriggerIndex(resultCount: Int, columns: Int) -> Int? {
        guard resultCount > 0, columns > 0 else { return nil }
        return max(resultCount - columns * 2, 0)
    }

    /// Prefetch one page when the two-row-ahead trigger becomes visible.
    ///
    /// The source page prevents a trigger from an already-visible row from
    /// cascading into another page after the response appends new results.
    func prefetchNextPageIfNeeded(for sourcePage: Int) async {
        guard sourcePage == currentPage,
              lastPrefetchedPage != sourcePage,
              hasMorePages,
              !isPrefetching,
              activeSearchID != nil
        else { return }

        lastPrefetchedPage = sourcePage
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadNextPage(isPrefetch: true)
        }
        prefetchTask = task
        await task.value

        if prefetchTask != nil {
            prefetchTask = nil
        }
    }

    private func loadNextPage(isPrefetch: Bool) async {
        guard hasMorePages, !isPrefetching, let searchID = activeSearchID else { return }

        isPrefetching = true
        isLoadingMore = true
        defer {
            isPrefetching = false
            isLoadingMore = false
        }
        let nextPage = currentPage + 1

        do {
            var requestParams = params
            requestParams.query = normalizeSearchQuery(searchQuery)
            requestParams.page = nextPage
            let response = try await api.search(
                params: requestParams,
                apiKey: apiKey.isEmpty ? nil : apiKey
            )

            guard !Task.isCancelled, activeSearchID == searchID else { return }

            if nextPage > 1, let seed = response.meta.seed, !seed.isEmpty, requestParams.seed == nil {
                params.seed = seed
            }
            var seen = Set(results.map(\.id))
            let fresh = response.data.filter { seen.insert($0.id).inserted }
            results.append(contentsOf: fresh)
            currentPage = response.meta.currentPage
            params.page = currentPage
            hasMorePages = response.meta.currentPage < response.meta.lastPage

            checkDownloadedStatus()
        } catch is CancellationError {
            if isPrefetch {
                lastPrefetchedPage = nil
            }
            return
        } catch {
            guard !Task.isCancelled, activeSearchID == searchID else { return }
            hasError = true
            errorMessage = error.localizedDescription
            if isPrefetch {
                lastPrefetchedPage = nil
            }
        }
    }

    func refresh() async {
        await search()
    }

    private func applyFilterChange() {
        cancelActiveSearch()
        filterDebounceTask?.cancel()
        currentPage = 1
        params.page = 1
        params.seed = nil
        results = []
        hasMorePages = false
        hasError = false
        filterDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled, self.viewActive else { return }
            await self.search()
        }
    }

    func setSorting(_ sorting: WallhavenSorting) {
        params.sorting = sorting
        if sorting != .random { params.seed = nil }
        applyFilterChange()
    }

    func togglePurity(_ purity: WallhavenPurity) {
        if params.purity.contains(purity) {
            params.purity.remove(purity)
        } else {
            params.purity.insert(purity)
        }
        applyFilterChange()
    }

    func toggleCategory(_ category: WallhavenCategory) {
        if params.categories.contains(category) {
            params.categories.remove(category)
        } else {
            params.categories.insert(category)
        }
        applyFilterChange()
    }

    func setColor(_ color: WallhavenColor?) {
        params.color = color
        applyFilterChange()
    }

    func setAtLeast(_ resolution: String?) {
        params.atLeast = resolution
        applyFilterChange()
    }

    func setTopRange(_ range: WallhavenToplistRange) {
        params.topRange = range
        applyFilterChange()
    }

    func toggleRatio(_ ratio: WallhavenRatio) {
        if params.ratios.contains(ratio.ratioString) {
            params.ratios.removeAll { $0 == ratio.ratioString }
        } else {
            params.ratios.append(ratio.ratioString)
        }
        applyFilterChange()
    }

    func setCategories(_ categories: Set<WallhavenCategory>) {
        params.categories = categories
        applyFilterChange()
    }

    func download(_ wallpaper: WallhavenWallpaper, to folder: String) async -> URL? {
        guard !folder.isEmpty else {
            showFeedback("Set a wallpaper folder in Settings first", isError: true)
            return nil
        }
        guard downloadProgress[wallpaper.id] == nil else { return nil }
        do {
            downloadProgress[wallpaper.id] = 0

            let url = try await downloader.download(
                wallpaper: wallpaper,
                to: folder
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress[wallpaper.id] = progress.fractionCompleted
                }
            }

            downloadedIds.insert(wallpaper.id)
            showDownloadAnimation(for: wallpaper.id)
            downloadProgress.removeValue(forKey: wallpaper.id)
            return url
        } catch is CancellationError {
            downloadProgress.removeValue(forKey: wallpaper.id)
            return nil
        } catch {
            downloadProgress.removeValue(forKey: wallpaper.id)
            showFeedback("Download failed: \(error.localizedDescription)", isError: true)
            return nil
        }
    }

    func reportSetWallpaper(_ wallpaper: WallhavenWallpaper) {
        showFeedback("Set \(wallpaper.resolution) wallpaper from Wallhaven")
    }

    func showDownloadAnimation(for wallpaperID: String) {
        downloadAnimationTasks[wallpaperID]?.cancel()
        downloadAnimationIDs.insert(wallpaperID)
        downloadAnimationTasks[wallpaperID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            guard !Task.isCancelled else { return }
            self?.dismissDownloadAnimation(for: wallpaperID)
        }
    }

    func dismissDownloadAnimation(for wallpaperID: String) {
        downloadAnimationTasks[wallpaperID]?.cancel()
        downloadAnimationTasks.removeValue(forKey: wallpaperID)
        downloadAnimationIDs.remove(wallpaperID)
    }

    private var toastTask: Task<Void, Never>?

    private func showFeedback(_ message: String, isError: Bool = false) {
        toastTask?.cancel()
        toastMessage = message
        toastIsError = isError
        showToast = true
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.showToast = false
            self.toastTask = nil
        }
    }

    func downloadAndSet(_ wallpaper: WallhavenWallpaper, to folder: String) async -> ImageFile? {
        guard let localURL = await download(wallpaper, to: folder) else { return nil }
        return ImageFile(url: localURL)
    }

    func cancelDownload(_ wallpaperId: String) {
        downloader.cancelDownload(wallpaperId)
        downloadProgress.removeValue(forKey: wallpaperId)
    }

    func preview(_ wallpaper: WallhavenWallpaper) {
        guard results.contains(where: { $0.id == wallpaper.id }) else { return }
        selectedWallpaper = wallpaper
        showPreview = true
    }

    func closePreview() {
        showPreview = false
        selectedWallpaper = nil
    }

    func clearSearch() {
        cancelActiveSearch()
        filterDebounceTask?.cancel()
        downloadedScanTask?.cancel()
        currentPage = 1
        params.page = 1
        params.seed = nil
        searchQuery = ""
        results = []
        isLoading = false
        isLoadingMore = false
        hasError = false
        hasMorePages = false
        totalResults = 0
        Task { [weak self] in
            await self?.search()
        }
    }

    private func cancelSearchForQueryEdit() {
        cancelActiveSearch()
        hasError = false
        errorMessage = ""
        hasMorePages = false
    }

    private func cancelActiveSearch() {
        searchTask?.cancel()
        searchTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        activeSearchID = nil
        activeSearchQuery = ""
        isLoading = false
        isLoadingMore = false
        isPrefetching = false
        lastPrefetchedPage = nil
    }

    private static func normalizedSearchQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeSearchQuery(_ query: String) -> String {
        Self.normalizedSearchQuery(query)
    }

    @Published var wallpaperFolderPath: String = ""

    func updateWallpaperFolderPath(_ path: String) {
        guard wallpaperFolderPath != path else { return }
        wallpaperFolderPath = path
        lastScannedFolder = ""
        lastScanDate = .distantPast
        checkDownloadedStatus()
    }

    private func checkDownloadedStatus() {
        guard !wallpaperFolderPath.isEmpty else { return }
        let folder = wallpaperFolderPath
        downloadedScanTask?.cancel()
        downloadedScanTask = Task { [weak self] in
            guard let self else { return }
            guard folder != self.lastScannedFolder ||
                    Date().timeIntervalSince(self.lastScanDate) >= 30
            else { return }
            let known = await Task.detached {
                WallhavenDownloader.downloadedIdsStatic(in: folder)
            }.value
            guard !Task.isCancelled else { return }
            self.downloadedIds.formUnion(known)
            self.lastScannedFolder = folder
            self.lastScanDate = Date()
        }
    }

    func markViewAppeared() {
        viewActive = true
    }

    func markViewDisappeared() {
        viewActive = false
        cancelActiveSearch()
        filterDebounceTask?.cancel()
        downloadedScanTask?.cancel()
        downloadAnimationTasks.values.forEach { $0.cancel() }
        downloadAnimationTasks.removeAll()
        downloadAnimationIDs.removeAll()
    }

    func markAsDownloaded(_ wallpaperId: String) {
        downloadedIds.insert(wallpaperId)
    }
}
