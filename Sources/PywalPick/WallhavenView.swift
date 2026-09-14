import SwiftUI

struct WallhavenView: View {
    @ObservedObject var viewModel: WallhavenViewModel
    @ObservedObject var settingsManager: SettingsManager

    @State private var columns = 4
    @State private var highlightedIndex: Int = -1
    @State private var scrollToID: String?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isGridFocused: Bool

    private let spacing: CGFloat = 12

    private var wallhavenDefaultsKey: String {
        let config = settingsManager.config
        return [
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

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider().opacity(0.45)
            contentArea
        }
        .onAppear {
            viewModel.markViewAppeared()
            viewModel.applyDefaults(from: settingsManager.config)
            viewModel.updateWallpaperFolderPath(settingsManager.config.wallpaperFolderPath)
            if viewModel.results.isEmpty && viewModel.searchQuery.isEmpty {
                Task { await viewModel.search() }
            }
            restoreGridFocus()
        }
        .onDisappear {
            viewModel.markViewDisappeared()
        }
        .onChange(of: settingsManager.config.wallpaperFolderPath) { _, newFolder in
            viewModel.updateWallpaperFolderPath(newFolder)
        }
        .onChange(of: settingsManager.config.wallhavenAPIKey) { _, newKey in
            viewModel.apiKey = newKey
        }
        .onChange(of: wallhavenDefaultsKey) { _, _ in
            Task { await viewModel.refreshDefaults(from: settingsManager.config) }
        }
        .onChange(of: viewModel.currentPage) { _, _ in
            restoreGridFocus()
        }
        .onChange(of: viewModel.results.count) { _, _ in
            if highlightedIndex == -1 && !viewModel.results.isEmpty {
                highlightedIndex = 0
            }
            highlightedIndex = min(highlightedIndex, max(viewModel.results.count - 1, 0))
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "f"), phases: .down) { press in
            if press.modifiers.contains(.command) {
                isSearchFocused = true
                return .handled
            }
            return .ignored
        }
    }

    private func restoreGridFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if !viewModel.showPreview {
                isGridFocused = true
            }
        }
    }

    private func moveHighlight(_ direction: NavigationDirection, columns: Int) {
        let count = viewModel.results.count
        guard count > 0 else { return }
        guard columns > 0 else { return }
        let current = highlightedIndex < 0 ? 0 : highlightedIndex
        let next: Int
        switch direction {
        case .left:
            next = max(0, current - 1)
        case .right:
            next = min(count - 1, current + 1)
        case .up:
            next = max(0, current - columns)
        case .down:
            if current + columns >= count, viewModel.hasMorePages {
                Task { await viewModel.loadNextPage() }
            }
            next = min(count - 1, current + columns)
        }
        highlightedIndex = next
        if next < viewModel.results.count {
            scrollToID = viewModel.results[next].id
        }
    }

    private func openHighlighted() {
        guard highlightedIndex >= 0, highlightedIndex < viewModel.results.count else { return }
        viewModel.preview(viewModel.results[highlightedIndex])
    }

    private var searchHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search wallhaven.cc…  (⌘F to focus)", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onSubmit {
                            Task { await viewModel.submitSearch() }
                        }
                        .submitLabel(.search)
                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    Task { await viewModel.submitSearch() }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
                .help("Search Wallhaven (Return)")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showFilters.toggle()
                    }
                } label: {
                    Label("Filters", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .tint(viewModel.showFilters ? Color.accentColor : .secondary)

                Menu {
                    ForEach(WallhavenSorting.allCases) { sorting in
                        Button {
                            viewModel.setSorting(sorting)
                        } label: {
                            Label(sorting.displayName, systemImage: viewModel.params.sorting == sorting ? "checkmark" : "")
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .buttonStyle(.bordered)
            }

            if viewModel.showFilters {
                filtersPanel
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var filtersPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Categories")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(WallhavenCategory.allCases) { category in
                            Toggle(isOn: Binding(
                                get: { viewModel.params.categories.contains(category) },
                                set: { enabled in
                                    var next = viewModel.params.categories
                                    if enabled { next.insert(category) } else { next.remove(category) }
                                    viewModel.setCategories(next)
                                }
                            )) {
                                Label(category.displayName, systemImage: category.icon)
                            }
                            .toggleStyle(.button)
                            .controlSize(.small)
                        }
                    }
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Purity")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(WallhavenPurity.allCases) { purity in
                            let isDisabled = purity == .nsfw && viewModel.apiKey.isEmpty
                            Toggle(isOn: Binding(
                                get: { viewModel.params.purity.contains(purity) },
                                set: { enabled in
                                    viewModel.togglePurity(purity)
                                }
                            )) {
                                Label(purity.displayName, systemImage: purity.icon)
                            }
                            .toggleStyle(.button)
                            .controlSize(.small)
                            .disabled(isDisabled)
                            .help(isDisabled ? "NSFW requires API key in Settings" : "")
                        }
                    }
                }
            }

            if viewModel.params.sorting == .toplist {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Toplist Range")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(WallhavenToplistRange.allCases) { range in
                                Toggle(isOn: Binding(
                                    get: { viewModel.params.topRange == range },
                                    set: { enabled in
                                        if enabled {
                                            viewModel.setTopRange(range)
                                        }
                                    }
                                )) {
                                    Text(range.displayName)
                                }
                                .toggleStyle(.button)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Minimum Resolution")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(["1920x1080", "2560x1440", "3840x2160"], id: \.self) { res in
                            Toggle(isOn: Binding(
                                get: { viewModel.params.atLeast == res },
                                set: { enabled in
                                    viewModel.setAtLeast(enabled ? res : nil)
                                }
                            )) {
                                Text(res)
                                    .font(.caption.monospaced())
                            }
                            .toggleStyle(.button)
                            .controlSize(.small)
                        }
                        if viewModel.params.atLeast != nil {
                            Button("Clear") {
                                viewModel.setAtLeast(nil)
                            }
                            .buttonStyle(.plain)
                            .controlSize(.small)
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Color")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if viewModel.params.color != nil {
                        Button("Clear") {
                            viewModel.setColor(nil)
                        }
                        .buttonStyle(.plain)
                        .controlSize(.small)
                        .foregroundStyle(Color.accentColor)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 16), spacing: 2) {
                    ForEach(WallhavenColor.allCases) { color in
                        Button {
                            viewModel.setColor(viewModel.params.color == color ? nil : color)
                        } label: {
                            Rectangle()
                                .fill(color.color)
                                .frame(width: 24, height: 18)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(viewModel.params.color == color ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                                .frame(minWidth: 32, minHeight: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.displayName)
                        .accessibilityAddTraits(viewModel.params.color == color ? .isSelected : [])
                        .help(color.displayName)
                    }
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aspect Ratio")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        ForEach(WallhavenRatio.allCases) { ratio in
                            Toggle(isOn: Binding(
                                get: { viewModel.params.ratios.contains(ratio.ratioString) },
                                set: { enabled in
                                    viewModel.toggleRatio(ratio)
                                }
                            )) {
                                Text(ratio.displayName)
                                    .font(.caption.monospaced())
                            }
                            .toggleStyle(.button)
                            .controlSize(.small)
                        }
                    }
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Relevance Sorting")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(WallhavenSorting.allCases) { sorting in
                            Toggle(isOn: Binding(
                                get: { viewModel.params.sorting == sorting },
                                set: { enabled in
                                    if enabled {
                                        viewModel.setSorting(sorting)
                                    }
                                }
                            )) {
                                Text(sorting.displayName)
                            }
                            .toggleStyle(.button)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.results.isEmpty && !viewModel.hasError {
            emptyState
        } else if viewModel.hasError && viewModel.results.isEmpty {
            errorState
        } else {
            VStack(spacing: 0) {
                if viewModel.hasError {
                    paginationErrorBanner
                }
                resultsGrid
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
                Text("Searching Wallhaven…")
                    .font(.headline)
                Text("Fetching the latest wallpapers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(viewModel.searchQuery.isEmpty ? "Search wallhaven.cc" : "No results found")
                    .font(.headline)
                Text(viewModel.searchQuery.isEmpty ?
                    "Enter a search term and press Return" :
                    "Try another search or adjust your filters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !viewModel.searchQuery.isEmpty {
                    Button("Clear search") {
                        viewModel.clearSearch()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.headline)
            Text(viewModel.errorMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            Button("Retry") {
                Task { await viewModel.search() }
            }
            .buttonStyle(.borderedProminent)
            Button("Clear search") {
                viewModel.clearSearch()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var paginationErrorBanner: some View {
        HStack(spacing: 8) {
            Label("Couldn’t load more wallpapers", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Spacer()
            Button("Retry") {
                Task { await viewModel.loadNextPage() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .font(.caption)
        .padding(.horizontal, spacing)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.08))
    }

    private var resultsGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
                    spacing: spacing
                ) {
                ForEach(viewModel.results.indices, id: \.self) { index in
                    let wallpaper = viewModel.results[index]
                    WallhavenThumbnailCard(
                        wallpaper: wallpaper,
                        isDownloaded: viewModel.downloadedIds.contains(wallpaper.id),
                        isDownloadAnimating: viewModel.downloadAnimationIDs.contains(wallpaper.id),
                        downloadProgress: viewModel.downloadProgress[wallpaper.id],
                        isHighlighted: index == highlightedIndex,
                        onTap: {
                            highlightedIndex = index
                            viewModel.preview(wallpaper)
                        },
                        onDownload: {
                            highlightedIndex = index
                            Task {
                                _ = await viewModel.download(wallpaper, to: settingsManager.config.wallpaperFolderPath)
                            }
                        },
                        onSetWallpaper: {
                            highlightedIndex = index
                            Task {
                                if let _ = await viewModel.downloadAndSet(
                                    wallpaper,
                                    to: settingsManager.config.wallpaperFolderPath
                                ) {
                                    // Handled by parent view
                                }
                            }
                        }
                    )
                    .id(wallpaper.id)
                }

                if viewModel.hasMorePages {
                    let remaining = max(viewModel.totalResults - viewModel.results.count, 0)
                    HStack(spacing: 8) {
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading more…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(remaining > 0 ? "Load more (\(remaining) remaining)" : "Load more") {
                                Task { await viewModel.loadNextPage() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .onAppear {
                        Task { await viewModel.prefetchNextPageIfNeeded() }
                    }
                    .onDisappear {
                        viewModel.prefetchSentinelDidDisappear()
                    }
                }
            }
            .padding(spacing)
            .overlay {
                if viewModel.isLoading && viewModel.results.isEmpty {
                    ProgressView()
                }
            }
            }
            .onChange(of: scrollToID) { _, id in
                if let id {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .focusable()
        .focused($isGridFocused)
        .focusEffectDisabled(true)
        .onTapGesture { isGridFocused = true }
        .onKeyPress(.leftArrow) {
            guard gridHandlesKeys else { return .ignored }
            moveHighlight(.left, columns: columns)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard gridHandlesKeys else { return .ignored }
            moveHighlight(.right, columns: columns)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard gridHandlesKeys else { return .ignored }
            moveHighlight(.up, columns: columns)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard gridHandlesKeys else { return .ignored }
            moveHighlight(.down, columns: columns)
            return .handled
        }
        .onKeyPress(.return) {
            guard gridHandlesKeys else { return .ignored }
            openHighlighted()
            return .handled
        }
        .onKeyPress(.escape) {
            if viewModel.showPreview {
                viewModel.closePreview()
                restoreGridFocus()
            }
            return .handled
        }
    }

    private var gridHandlesKeys: Bool {
        isGridFocused && !isSearchFocused && !viewModel.showPreview
    }
}

private struct DownloadSuccessOverlay: View {
    let cornerRadius: CGFloat
    let iconSize: CGFloat

    @State private var overlayOpacity = 0.0
    @State private var checkmarkScale = 0.35

    var body: some View {
        ZStack {
            Color.green.opacity(0.88)

            Image(systemName: "checkmark")
                .font(.system(size: iconSize, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                .scaleEffect(checkmarkScale)
        }
        .opacity(overlayOpacity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.12)) {
                overlayOpacity = 1
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62).delay(0.06)) {
                checkmarkScale = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.92) {
                withAnimation(.easeOut(duration: 0.25)) {
                    overlayOpacity = 0
                    checkmarkScale = 1.1
                }
            }
        }
    }
}

struct WallhavenThumbnailCard: View {
    let wallpaper: WallhavenWallpaper
    let isDownloaded: Bool
    let isDownloadAnimating: Bool
    let downloadProgress: Double?
    let isHighlighted: Bool
    let onTap: () -> Void
    let onDownload: () -> Void
    let onSetWallpaper: () -> Void

    @State private var thumbnailImage: Image?
    @State private var fullImage: Image?
    @State private var isHovered = false
    @State private var fullImageTask: Task<Void, Never>?
    @State private var cancelImageTask: Task<Void, Never>?

    var showActions: Bool { isHovered || isHighlighted }
    private var isDownloading: Bool { downloadProgress != nil }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary.opacity(0.15))
                .aspectRatio(wallpaper.aspectRatio, contentMode: .fit)

            if let fullImage {
                fullImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else if let thumbnailImage {
                thumbnailImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            if showActions {
                Color.black.opacity(0.3)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 8) {
                    Button(action: onDownload) {
                        Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloaded || isDownloading)
                    .accessibilityLabel(isDownloaded ? "Downloaded" : isDownloading ? "Downloading" : "Download")
                    .help(isDownloaded ? "Downloaded" : isDownloading ? "Downloading" : "Download")

                    Button(action: onSetWallpaper) {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set as wallpaper")
                    .help("Set as wallpaper")
                }
            }

            VStack {
                Spacer()
                HStack {
                    Text(wallpaper.resolution)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())

                    Spacer()

                    Image(systemName: wallpaper.purityEnum.icon)
                        .font(.caption)
                        .foregroundStyle(wallpaper.purityEnum.color)
                }
                .padding(6)

                if let progress = downloadProgress, progress > 0 && progress < 1 {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .background(.ultraThinMaterial)
                }
            }

            if isDownloaded && !showActions {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .background(.ultraThinMaterial, in: Circle())
                            .accessibilityLabel("Downloaded")
                    }
                    Spacer()
                }
                .padding(6)
            }

            if isDownloadAnimating {
                DownloadSuccessOverlay(cornerRadius: 10, iconSize: 76)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isHighlighted ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                scheduleFullImageLoad()
            } else if !isHighlighted {
                cancelFullImageLoad()
            }
        }
        .onChange(of: isHighlighted) { _, highlighted in
            if highlighted {
                scheduleFullImageLoad()
            } else if !isHovered {
                cancelFullImageLoad()
            }
        }
        .onDisappear {
            cancelFullImageLoad()
            fullImage = nil
        }
        .contextMenu {
            Button("Preview", systemImage: "eye") { onTap() }
            Button(isDownloaded ? "Downloaded" : "Download", systemImage: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle") {
                onDownload()
            }
            .disabled(isDownloaded || isDownloading)
            Button("Set as Wallpaper", systemImage: "photo") { onSetWallpaper() }
            Divider()
            Button("Open on Wallhaven", systemImage: "safari") {
                if let url = URL(string: wallpaper.url) {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Copy URL", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(wallpaper.url, forType: .string)
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        if let image = await WallhavenImageLoader.shared.load(urlString: wallpaper.thumbs.large, maxPixelSize: 512) {
            thumbnailImage = Image(nsImage: image)
        }
    }

    private func scheduleFullImageLoad() {
        guard fullImage == nil, fullImageTask == nil else { return }
        let originalURL = wallpaper.thumbs.original
        let largeURL = wallpaper.thumbs.large
        fullImageTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            if let image = await WallhavenImageLoader.shared.load(urlString: originalURL, maxPixelSize: 1024) {
                fullImage = Image(nsImage: image)
            } else if let image = await WallhavenImageLoader.shared.load(urlString: largeURL, maxPixelSize: 1024) {
                fullImage = Image(nsImage: image)
            }
            fullImageTask = nil
        }
    }

    private func cancelFullImageLoad() {
        fullImageTask?.cancel()
        fullImageTask = nil
        cancelImageTask?.cancel()
        let originalURL = wallpaper.thumbs.original
        let largeURL = wallpaper.thumbs.large
        cancelImageTask = Task {
            await WallhavenImageLoader.shared.cancel(urlString: originalURL, maxPixelSize: 1024)
            guard !Task.isCancelled else { return }
            await WallhavenImageLoader.shared.cancel(urlString: largeURL, maxPixelSize: 1024)
            cancelImageTask = nil
        }
    }

}

struct WallhavenPreviewView: View {
    let wallpaper: WallhavenWallpaper
    let isDownloaded: Bool
    let isDownloadAnimating: Bool
    let downloadProgress: Double?
    let feedbackMessage: String?
    let feedbackIsError: Bool
    let onDownload: () -> Void
    let onSetWallpaper: () -> Void
    let onDismiss: () -> Void

    @State private var previewImage: Image?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 20) {
                ZStack {
                    if let previewImage {
                        previewImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 900, maxHeight: 550)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 20)
                    } else {
                        ProgressView()
                            .controlSize(.large)
                            .frame(width: 200, height: 200)
                    }

                    if isDownloadAnimating, previewImage != nil {
                        DownloadSuccessOverlay(cornerRadius: 12, iconSize: 124)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        Label(wallpaper.resolution, systemImage: "aspectratio")
                        Label(formatFileSize(wallpaper.fileSize), systemImage: "doc")
                        Label("\(wallpaper.views) views", systemImage: "eye")
                        Label("\(wallpaper.favorites) favorites", systemImage: "heart")
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: wallpaper.purityEnum.icon)
                            Text(wallpaper.purityEnum.displayName)
                        }
                        .foregroundStyle(wallpaper.purityEnum.color)
                        Text(wallpaper.categoryEnum.displayName)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary.opacity(0.3))
                            .clipShape(Capsule())
                    }
                    .font(.caption)

                    if let progress = downloadProgress, progress > 0 && progress < 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                            Text("Downloading… \(Int(progress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if isDownloaded {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }

                    if let feedbackMessage {
                        Label(
                            feedbackMessage,
                            systemImage: feedbackIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(feedbackIsError ? .red : .green)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    HStack(spacing: 4) {
                        ForEach(Array(wallpaper.colors.enumerated()), id: \.offset) { _, colorHex in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(hexToColor(colorHex))
                                .frame(width: 28, height: 28)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 600)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 12) {
                    if downloadProgress != nil {
                        Label("Downloading…", systemImage: "arrow.down.circle")
                            .foregroundStyle(.secondary)
                            .controlSize(.large)
                    } else if isDownloaded {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .controlSize(.large)
                    } else {
                        Button("Download", systemImage: "arrow.down.circle") {
                            onDownload()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Button("Set as Wallpaper", systemImage: "photo") {
                        onSetWallpaper()
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Open in Browser", systemImage: "safari") {
                        if let url = URL(string: wallpaper.url) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button("Close", systemImage: "xmark") {
                        onDismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding(24)
        }
        .task {
            await loadPreviewImage()
        }
    }

    private func loadPreviewImage() async {
        let loader = WallhavenImageLoader.shared
        let width = Int(NSScreen.main?.frame.width ?? 1920)
        let target = min(max(width, 1024), 2560)
        if let image = await loader.load(urlString: wallpaper.path, maxPixelSize: target) {
            previewImage = Image(nsImage: image)
            return
        }
        if let image = await loader.load(urlString: wallpaper.thumbs.original, maxPixelSize: target) {
            previewImage = Image(nsImage: image)
            return
        }
        if let image = await loader.load(urlString: wallpaper.thumbs.large, maxPixelSize: 1024) {
            previewImage = Image(nsImage: image)
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func hexToColor(_ hex: String) -> Color {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
