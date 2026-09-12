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

    @Published var params = WallhavenSearchParams()
    @Published var showFilters: Bool = false

    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadedIds: Set<String> = []
    @Published var toastMessage: String?
    @Published var showToast = false

    @Published var selectedWallpaper: WallhavenWallpaper?
    @Published var showPreview: Bool = false

    @Published var collections: [WallhavenCollection] = []
    @Published var isLoadingCollections: Bool = false
    @Published var selectedCollection: WallhavenCollection?

    @Published var apiKey: String = ""

    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let api = WallhavenAPI.shared
    private let downloader = WallhavenDownloader.shared

    init() {
        setupDebounce()
    }

    private func setupDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self else { return }
                if !query.isEmpty {
                    Task { await self.search() }
                }
            }
            .store(in: &cancellables)
    }

    func search() async {
        searchTask?.cancel()

        searchTask = Task {
            isLoading = true
            hasError = false
            currentPage = 1

            do {
                params.query = searchQuery
                let response = try await api.search(
                    params: params,
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
        }
    }

    func loadNextPage() async {
        guard hasMorePages && !isLoading else { return }

        isLoading = true
        currentPage += 1
        params.page = currentPage

        do {
            let response = try await api.search(
                params: params,
                apiKey: apiKey.isEmpty ? nil : apiKey
            )

            if Task.isCancelled { return }

            results.append(contentsOf: response.data)
            hasMorePages = response.meta.currentPage < response.meta.lastPage

            await checkDownloadedStatus()
        } catch {
            currentPage -= 1
            hasError = true
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        await search()
    }

    func setSorting(_ sorting: WallhavenSorting) {
        params.sorting = sorting
        Task { await search() }
    }

    func togglePurity(_ purity: WallhavenPurity) {
        if params.purity.contains(purity) {
            params.purity.remove(purity)
        } else {
            params.purity.insert(purity)
        }
        Task { await search() }
    }

    func toggleCategory(_ category: WallhavenCategory) {
        if params.categories.contains(category) {
            params.categories.remove(category)
        } else {
            params.categories.insert(category)
        }
        Task { await search() }
    }

    func setColor(_ color: WallhavenColor?) {
        params.color = color
        Task { await search() }
    }

    func setAtLeast(_ resolution: String?) {
        params.atLeast = resolution
        Task { await search() }
    }

    func toggleRatio(_ ratio: WallhavenRatio) {
        if params.ratios.contains(ratio.ratioString) {
            params.ratios.removeAll { $0 == ratio.ratioString }
        } else {
            params.ratios.append(ratio.ratioString)
        }
        Task { await search() }
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

    func loadCollections() async {
        guard !apiKey.isEmpty else { return }

        isLoadingCollections = true
        do {
            collections = try await api.getCollections(apiKey: apiKey)
        } catch {
            collections = []
        }
        isLoadingCollections = false
    }

    func loadCollectionWallpapers(_ collection: WallhavenCollection) async {
        selectedCollection = collection
        isLoading = true
        hasError = false

        do {
            let response = try await api.getCollectionWallpapers(
                username: "",
                collectionId: collection.id,
                apiKey: apiKey.isEmpty ? nil : apiKey
            )

            results = response.data
            hasMorePages = response.meta.currentPage < response.meta.lastPage
            currentPage = response.meta.currentPage
            totalResults = response.meta.total
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
