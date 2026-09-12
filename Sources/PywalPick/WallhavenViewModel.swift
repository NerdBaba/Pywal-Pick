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
    @Published var toastMessage: String?
    @Published var showToast = false

    @Published var selectedWallpaper: WallhavenWallpaper?
    @Published var showPreview: Bool = false

    @Published var apiKey: String = ""

    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let api = WallhavenAPI.shared
    private let downloader = WallhavenDownloader.shared

    private var isPrefetching = false
    private var defaultsSignature: String?

    init() {
        setupDebounce()
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

    private func setupDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.search() }
            }
            .store(in: &cancellables)
    }

    private func resetPaginationLocked() {
        currentPage = 1
        params.page = 1
        hasMorePages = false
        isPrefetching = false
    }

    func search() async {
        searchTask?.cancel()

        searchTask = Task {
            isLoading = true
            isLoadingMore = false
            hasError = false
            resetPaginationLocked()

            do {
                var requestParams = params
                requestParams.query = searchQuery
                requestParams.page = 1
                let response = try await api.search(
                    params: requestParams,
                    apiKey: apiKey.isEmpty ? nil : apiKey
                )

                if Task.isCancelled { return }

                results = response.data
                hasMorePages = response.meta.currentPage < response.meta.lastPage
                currentPage = response.meta.currentPage
                totalResults = response.meta.total

                await checkDownloadedStatus()
            } catch {
                if Task.isCancelled { return }
                hasError = true
                errorMessage = error.localizedDescription
            }

            isLoading = false
            isLoadingMore = false
        }

        await searchTask?.value
    }

    func loadNextPage() async {
        guard hasMorePages, !isPrefetching else { return }

        isPrefetching = true
        isLoadingMore = true
        let nextPage = currentPage + 1

        do {
            var requestParams = params
            requestParams.query = searchQuery
            requestParams.page = nextPage
            let response = try await api.search(
                params: requestParams,
                apiKey: apiKey.isEmpty ? nil : apiKey
            )

            if Task.isCancelled { return }

            if nextPage > 1, let seed = response.meta.seed, !seed.isEmpty, requestParams.seed == nil {
                params.seed = seed
            }
            var seen = Set(results.map(\.id))
            let fresh = response.data.filter { seen.insert($0.id).inserted }
            results.append(contentsOf: fresh)
            currentPage = response.meta.currentPage
            params.page = currentPage
            hasMorePages = response.meta.currentPage < response.meta.lastPage

            await checkDownloadedStatus()
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
        }

        isPrefetching = false
        isLoadingMore = false
    }

    func refresh() async {
        await search()
    }

    private func applyFilterChange() {
        searchTask?.cancel()
        currentPage = 1
        params.page = 1
        params.seed = nil
        Task { await search() }
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
            downloadProgress.removeValue(forKey: wallpaper.id)
            showFeedback("Downloaded wallhaven-\(wallpaper.id).\(wallpaper.fileExtension)")
            return url
        } catch {
            downloadProgress.removeValue(forKey: wallpaper.id)
            showFeedback("Download failed: \(error.localizedDescription)")
            return nil
        }
    }

    func reportSetWallpaper(_ wallpaper: WallhavenWallpaper) {
        showFeedback("Set \(wallpaper.resolution) wallpaper from Wallhaven")
    }

    private func showFeedback(_ message: String) {
        toastMessage = message
        showToast = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self else { return }
            self.showToast = false
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
        selectedWallpaper = wallpaper
        showPreview = true
    }

    func closePreview() {
        showPreview = false
        selectedWallpaper = nil
    }

    func clearSearch() {
        searchQuery = ""
        results = []
        hasError = false
        hasMorePages = false
        totalResults = 0
    }

    private func checkDownloadedStatus() async {
        // This would check against the wallpaper folder
        // For now, we'll rely on the downloader's isDownloaded method
    }

    func markAsDownloaded(_ wallpaperId: String) {
        downloadedIds.insert(wallpaperId)
    }
}
