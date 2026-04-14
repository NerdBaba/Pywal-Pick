// Import shared types
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// Thumbnail caching utilities
enum ThumbnailSize: String {
    case small = "128"
    case medium = "256"
    case large = "512"

    var pixelSize: NSSize {
        switch self {
        case .small: return NSSize(width: 128, height: 72)  // 16:9 ratio
        case .medium: return NSSize(width: 256, height: 144)
        case .large: return NSSize(width: 512, height: 288)
        }
    }
}

class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cacheDir: URL
    private let cacheQueue = DispatchQueue(
        label: "com.imagepicker.thumbnailcache", attributes: .concurrent)

    // Optimize cache access with concurrent protection
    private let cacheLock = NSLock()
    private let fileManager = FileManager.default

    // In-memory cache for instant access
    private var memoryCache: [String: NSImage] = [:]
    private let maxMemoryCacheSize = 100
    private var cacheAccessOrder: [String] = []

    var cacheDirectory: URL {
        cacheDir
    }

    private init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = cachesDir.appendingPathComponent("PywalPick/Thumbnails")

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // Performance tracking
    private var totalCacheHits = 0
    private var totalCacheMisses = 0
    private var totalGenerationTime: TimeInterval = 0

    func printStats() {
        print(
            "📊 Thumbnail Cache Stats: \(totalCacheHits) hits, \(totalCacheMisses) misses, Avg gen time: \(totalGenerationTime / Double(max(1, totalCacheHits + totalCacheMisses)))s"
        )
    }

    private func updateMemoryCacheAccessOrder(for key: String) {
        cacheAccessOrder.removeAll { $0 == key }
        cacheAccessOrder.append(key)

        if cacheAccessOrder.count > maxMemoryCacheSize {
            let oldestKey = cacheAccessOrder.removeFirst()
            memoryCache.removeValue(forKey: oldestKey)
        }
    }

    func cachedThumbnailURL(for imageURL: URL, size: ThumbnailSize) -> URL {
        let imagePathHash = String(imageURL.path.hashValue)
        let filename = "\(imagePathHash)_\(size.rawValue).jpg"
        return cacheDirectory.appendingPathComponent(filename)
    }

    func hasCachedThumbnail(for imageURL: URL, size: ThumbnailSize) -> Bool {
        let cacheURL = cachedThumbnailURL(for: imageURL, size: size)
        return fileManager.fileExists(atPath: cacheURL.path)
    }

    func getCachedThumbnailImage(for imageURL: URL, size: ThumbnailSize) -> NSImage? {
        let cacheKey = "\(imageURL.path.hashValue)_\(size.rawValue)"

        cacheLock.lock()
        if let cachedImage = memoryCache[cacheKey] {
            updateMemoryCacheAccessOrder(for: cacheKey)
            totalCacheHits += 1
            cacheLock.unlock()
            return cachedImage
        }
        cacheLock.unlock()

        // Check disk cache
        let cacheURL = cachedThumbnailURL(for: imageURL, size: size)
        if hasCachedThumbnail(for: imageURL, size: size) {
            do {
                let cachedData = try Data(contentsOf: cacheURL)
                if let cachedImage = NSImage(data: cachedData) {
                    cacheLock.lock()
                    memoryCache[cacheKey] = cachedImage
                    updateMemoryCacheAccessOrder(for: cacheKey)
                    totalCacheHits += 1
                    cacheLock.unlock()
                    return cachedImage
                }
            } catch {
                // Fall back to generation
            }
        }

        cacheLock.lock()
        totalCacheMisses += 1
        cacheLock.unlock()

        return nil
    }

    func generateAndCacheThumbnail(for imageURL: URL, size: ThumbnailSize) -> URL? {
        return generateAndCacheThumbnailAsync(for: imageURL, size: size, synchronous: true)
    }

    private func generateAndCacheThumbnailAsync(
        for imageURL: URL, size: ThumbnailSize, synchronous: Bool = false
    ) -> URL? {
        let startTime = CFAbsoluteTimeGetCurrent()
        let cacheURL = cachedThumbnailURL(for: imageURL, size: size)

        // Check if already cached to avoid duplicate work
        if hasCachedThumbnail(for: imageURL, size: size) {
            return cacheURL
        }

        let workItem = DispatchWorkItem {
            do {
                let imageData = try Data(contentsOf: imageURL)
                guard let nsImage = NSImage(data: imageData), nsImage.isValid else {
                    return
                }

                // Calculate target size maintaining 16:9 aspect ratio
                let targetSize = size.pixelSize

                // Create thumbnail with better performance
                let resizedImage = NSImage(size: targetSize)
                resizedImage.lockFocus()

                let ctx = NSGraphicsContext.current!.cgContext
                ctx.interpolationQuality = .medium  // Medium for better performance

                nsImage.draw(
                    in: NSRect(origin: .zero, size: targetSize),
                    from: NSRect(origin: .zero, size: nsImage.size),
                    operation: .copy, fraction: 1.0)
                resizedImage.unlockFocus()

                // Save as JPEG to cache with better compression
                if let tiffData = resizedImage.tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: tiffData),
                    let jpegData = bitmap.representation(
                        using: .jpeg, properties: [.compressionFactor: 0.75])
                {
                    try jpegData.write(to: cacheURL, options: .atomic)

                    // Cache in memory for instant access
                    let cacheKey = "\(imageURL.path.hashValue)_\(size.rawValue)"
                    self.cacheLock.lock()
                    self.memoryCache[cacheKey] = resizedImage
                    self.updateMemoryCacheAccessOrder(for: cacheKey)
                    self.totalGenerationTime += (CFAbsoluteTimeGetCurrent() - startTime)
                    self.cacheLock.unlock()

                    let generationTime = CFAbsoluteTimeGetCurrent() - startTime
                    print(
                        "⚡ Generated thumbnail in \(String(format: "%.3f", generationTime))s for \(imageURL.lastPathComponent)"
                    )
                }

            } catch {
                print("Failed to generate thumbnail for \(imageURL.lastPathComponent): \(error)")
            }
        }

        if synchronous {
            workItem.perform()
            return hasCachedThumbnail(for: imageURL, size: size) ? cacheURL : nil
        } else {
            cacheQueue.async(execute: workItem)
            return cacheURL
        }
    }
}

public struct WallpaperSwitcherView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel = WallpaperSwitcherViewModel()
    @State private var currentWallpaper: String?
    @State private var lastSelectedWallpaperURL: URL?
    @State private var toastMessage: String?
    @State private var showToast = false
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isGridFocused: Bool
    @FocusState private var isCarouselFocused: Bool
    @State private var carouselScrollPosition: String?
    @State private var carouselScrollTarget: Int?
    @State private var carouselRefreshID = UUID()

    public init() {}

    // Thumbnail cache for better performance
    @State private var thumbnailCache: [URL: Image] = [:]

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 16) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Pywal Pick")
                        .font(.custom("Nunito Sans ExtraBold", size: 28))
                        .foregroundStyle(.primary)

                    Spacer()

                    HStack(spacing: 8) {
                        Button(action: {
                            viewModel.isShowingRandomOverlay = true
                        }) {
                            Label("Random", systemImage: "shuffle")
                        }
                        .buttonStyle(.borderedProminent)
                        .help("Select Random Wallpaper")

                        Button(action: {
                            openWindow(id: "settings")
                        }) {
                            Label("Settings", systemImage: "gear")
                        }
                        .buttonStyle(.bordered)
                        .help("Open Settings")

                        Button(action: {
                            viewModel.loadWallpapers(
                                from: settingsManager.config.wallpaperFolderPath)
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Refresh Wallpapers")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                if settingsManager.config.wallpaperFolderPath.isEmpty {
                    // No folder configured
                    VStack(spacing: 20) {
                        Spacer()

                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)

                        VStack(spacing: 12) {
                            Text("No Wallpaper Folder Configured")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("Please configure a wallpaper folder in Settings to get started.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        Button("Open Settings") {
                            openWindow(id: "settings")
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading wallpapers...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.wallpapers.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()

                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)

                        VStack(spacing: 12) {
                            Text("No Wallpapers Found")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text(
                                "The configured folder doesn't contain any image files, or the path is invalid."
                            )
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        }

                        HStack(spacing: 12) {
                            Button("Check Settings") {
                                openWindow(id: "settings")
                            }
                            .buttonStyle(.bordered)

                            Button("Refresh") {
                                viewModel.loadWallpapers(
                                    from: settingsManager.config.wallpaperFolderPath)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Simplified container with clean liquid glass
                    GeometryReader { geometry in

                        VStack(spacing: 0) {
                            // Search and sorting controls
                            VStack(spacing: 24) {
                                // Search section
                                HStack(spacing: 16) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundStyle(.secondary)
                                            .font(.system(size: 16, weight: .medium))
                                        TextField(
                                            "Search wallpapers...", text: $viewModel.searchQuery
                                        )
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 16, weight: .regular, design: .rounded))
                                        .foregroundStyle(.primary)
                                        .frame(minWidth: 250, maxWidth: 350)
                                        .focused($isSearchFocused)
                                        if !viewModel.searchQuery.isEmpty {
                                            Button(action: {
                                                viewModel.searchQuery = ""
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.secondary)
                                                    .font(.system(size: 16, weight: .medium))
                                            }
                                            .buttonStyle(.plain)
                                            .help("Clear search")
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(.ultraThinMaterial)
                                    .background(Color.white.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .onTapGesture {
                                        isSearchFocused = true
                                    }

                                    Spacer()

                                    Text("\(viewModel.filteredWallpapers.count) wallpapers")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary.opacity(0.9))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }

                                // Sorting section
                                HStack(spacing: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.up.arrow.down")
                                            .foregroundStyle(.secondary)
                                            .font(.system(size: 14, weight: .medium))
                                        Text("Sort by:")
                                            .font(
                                                .system(size: 14, weight: .medium, design: .rounded)
                                            )
                                            .foregroundStyle(.primary)
                                    }

                                    Picker("", selection: $viewModel.sortOption) {
                                        ForEach(SortOption.allCases, id: \.self) { option in
                                            Text(option.rawValue)
                                                .font(
                                                    .system(
                                                        size: 14, weight: .regular, design: .rounded
                                                    )
                                                )
                                                .tag(option)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .fixedSize()
                                    .onChange(of: viewModel.sortOption) { _, _ in
                                        // Sorting happens automatically in filteredWallpapers
                                    }

                                    Button(action: {
                                        viewModel.sortOrderAscending.toggle()
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(
                                                systemName: viewModel.sortOrderAscending
                                                    ? "arrow.up" : "arrow.down"
                                            )
                                            .font(.system(size: 14, weight: .medium))
                                            Text(viewModel.sortOrderLabel)
                                                .font(
                                                    .system(
                                                        size: 13, weight: .regular, design: .rounded
                                                    ))
                                        }
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                    .fixedSize()
                                    .help("Toggle sort order")

                                    Spacer(minLength: 16)

                                    Picker("", selection: $viewModel.viewMode) {
                                        ForEach(ViewMode.allCases) { mode in
                                            Image(systemName: mode.icon)
                                                .tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .fixedSize()
                                    .help("Toggle view mode")

                                    Spacer(minLength: 16)
                                    
                                    // Color filter bar inline
                                    ColorFilterBar(
                                        selectedGroup: $viewModel.selectedColorFilter,
                                        colorCounts: viewModel.colorCounts,
                                        totalCount: viewModel.filteredWallpapers.count
                                    )
                                    .layoutPriority(2)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            .onChange(of: viewModel.selectedColorFilter) { _, newFilter in
                                print("🎨 Color filter changed to: \(newFilter?.rawValue ?? "none")")
                                viewModel.highlightedIndex = nil
                                carouselScrollPosition = nil
                                carouselScrollTarget = nil
                                viewModel.updateFilteredWallpapers()
                                carouselRefreshID = UUID()
                                print("📊 Carousel filtered count: \(viewModel.filteredWallpapers.count)")
                            }

                            if viewModel.viewMode == .carousel {
                                carouselContentView
                            } else {
                                gridContentView
                            }
                        }
                        .contentShape(Rectangle())
                        .focusable()
                        .focused(viewModel.viewMode == .carousel ? $isCarouselFocused : $isGridFocused)
                        .focusEffectDisabled(true)
                        .onTapGesture {
                            if viewModel.viewMode == .carousel {
                                isCarouselFocused = true
                            } else {
                                isGridFocused = true
                            }
                        }
                        .onKeyPress(.leftArrow) {
                            handleLeftArrow()
                            return .handled
                        }
                        .onKeyPress(.rightArrow) {
                            handleRightArrow()
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            if viewModel.viewMode != .carousel {
                                viewModel.moveSelection(
                                    direction: .up, columns: settingsManager.config.gridColumns)
                            }
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            if viewModel.viewMode != .carousel {
                                viewModel.moveSelection(
                                    direction: .down, columns: settingsManager.config.gridColumns)
                            }
                            return .handled
                        }
                        .onKeyPress(.return) {
                            if let index = viewModel.highlightedIndex,
                                index < viewModel.filteredWallpapers.count
                            {
                                let wallpaper = viewModel.filteredWallpapers[index]
                                let isReselect = lastSelectedWallpaperURL == wallpaper.url
                                if isReselect {
                                    cycleBackendAndSet(wallpaper)
                                } else {
                                    lastSelectedWallpaperURL = wallpaper.url
                                    viewModel.setCurrentWallpaper(wallpaper)
                                    setWallpaper(wallpaper)
                                }
                            }
                            return .handled
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                    .onKeyPress(characters: CharacterSet(charactersIn: "f"), phases: .down) {
                        press in
                        if press.modifiers.contains(.command) {
                            isSearchFocused = true
                            return .handled
                        }
                        return .ignored
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                viewModel.sortOption = settingsManager.config.defaultSortOption
                viewModel.sortOrderAscending = settingsManager.config.defaultSortOrder
                viewModel.viewMode = settingsManager.config.viewMode
                if !settingsManager.config.wallpaperFolderPath.isEmpty {
                    viewModel.loadWallpapers(from: settingsManager.config.wallpaperFolderPath)
                    viewModel.cleanupOldCache()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if viewModel.viewMode == .carousel {
                        isCarouselFocused = true
                    } else {
                        isGridFocused = true
                    }
                    restoreLastWallpaper()
                    if viewModel.highlightedIndex == nil && !viewModel.filteredWallpapers.isEmpty {
                        viewModel.highlightedIndex = 0
                        if viewModel.viewMode == .carousel {
                            carouselScrollPosition = "0"
                        }
                    }
                }
            }
            .onChange(of: settingsManager.config.wallpaperFolderPath) { _, newPath in
                if !newPath.isEmpty {
                    viewModel.loadWallpapers(from: newPath)
                }
            }
            .onChange(of: viewModel.viewMode) { _, newMode in
                settingsManager.config.viewMode = newMode
            }
            .onChange(of: viewModel.sortOption) { _, _ in
                print("🔄 Sort option changed - refreshing carousel")
                DispatchQueue.main.async {
                    self.carouselRefreshID = UUID()
                }
            }
            .onChange(of: viewModel.sortOrderAscending) { _, _ in
                print("🔄 Sort order changed - refreshing carousel")
                DispatchQueue.main.async {
                    self.carouselRefreshID = UUID()
                }
            }
            .onChange(of: viewModel.filteredWallpapers) { _, _ in
                if viewModel.viewMode == .carousel {
                    print("🔄 Filtered wallpapers changed - refreshing carousel")
                    DispatchQueue.main.async {
                        self.carouselRefreshID = UUID()
                    }
                }
            }
            
            if viewModel.isShowingRandomOverlay {
                randomOverlay
            }

            if showToast {
                toastOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridContentView: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 12),
                            count: settingsManager.config.gridColumns),
                        spacing: 12
                    ) {
                        ForEach(
                            Array(viewModel.filteredWallpapers.enumerated()),
                            id: \.element.id
                        ) { index, wallpaper in
                            WallpaperCardView(
                                wallpaper: wallpaper,
                                isSelected: viewModel.currentWallpaper?.id == wallpaper.id,
                                isHighlighted: viewModel.highlightedIndex == index,
                                availableWidth: geometry.size.width - 24,
                                columns: settingsManager.config.gridColumns,
                                onSelect: {
                                    let isReselect = lastSelectedWallpaperURL == wallpaper.url
                                    if isReselect {
                                        cycleBackendAndSet(wallpaper)
                                    } else {
                                        lastSelectedWallpaperURL = wallpaper.url
                                        viewModel.setCurrentWallpaper(wallpaper)
                                        setWallpaper(wallpaper)
                                    }
                                    viewModel.highlightedIndex = index
                                    isGridFocused = true
                                }
                            )
                            .id(index)
                        }
                    }
                    .padding(12)
                    .id(viewModel.gridRefreshID)
                }
            }
            .scrollIndicators(.visible)
            .onChange(of: viewModel.highlightedIndex) { _, newIndex in
                if let index = newIndex, index < viewModel.filteredWallpapers.count {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    private var carouselContentView: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: max(min(geometry.size.width * 0.06, 72), 24)) {
                        ForEach(Array(viewModel.filteredWallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                            CarouselCardView(
                                wallpaper: wallpaper,
                                isSelected: viewModel.currentWallpaper?.id == wallpaper.id,
                                isCentered: viewModel.highlightedIndex == index,
                                cardWidth: min(max(geometry.size.width * 0.55, 480), 960),
                                onSelect: {
                                    let isReselect = lastSelectedWallpaperURL == wallpaper.url
                                    if isReselect {
                                        cycleBackendAndSet(wallpaper)
                                    } else {
                                        lastSelectedWallpaperURL = wallpaper.url
                                        viewModel.highlightedIndex = index
                                        viewModel.setCurrentWallpaper(wallpaper)
                                        setWallpaper(wallpaper)
                                    }
                                    isCarouselFocused = true
                                }
                            )
                            .id("\(index)")
                        }
                    }
                    .padding(.horizontal, max(40, geometry.size.width * 0.2))
                    .padding(.top, 80)
                    .padding(.bottom, 60)
                }
                .scrollClipDisabled(true)
                .scrollPosition(id: $carouselScrollPosition)
                .scrollIndicators(.visible)
                .scrollIndicatorsFlash(onAppear: true)
                .onChange(of: carouselScrollPosition) { _, newPosition in
                    if let position = newPosition, let index = Int(position) {
                        viewModel.highlightedIndex = index
                    }
                }
                .onChange(of: viewModel.highlightedIndex) { _, newIndex in
                    if let index = newIndex {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo("\(index)", anchor: .center)
                        }
                    }
                }
                .onChange(of: carouselScrollTarget) { _, newTarget in
                    if let target = newTarget {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo("\(target)", anchor: .center)
                        }
                        carouselScrollTarget = nil
                    }
                }
            }
        }
        .id("carousel-\(carouselRefreshID.uuidString)")
    }

    private func handleLeftArrow() {
        if viewModel.viewMode == .carousel {
            if let currentIndex = viewModel.highlightedIndex {
                let newIndex = max(0, currentIndex - 1)
                viewModel.highlightedIndex = newIndex
                carouselScrollTarget = newIndex
            } else if !viewModel.filteredWallpapers.isEmpty {
                viewModel.highlightedIndex = 0
                carouselScrollTarget = 0
            }
        } else {
            viewModel.moveSelection(direction: .left, columns: settingsManager.config.gridColumns)
        }
    }

    private func handleRightArrow() {
        if viewModel.viewMode == .carousel {
            if let currentIndex = viewModel.highlightedIndex {
                let newIndex = min(viewModel.filteredWallpapers.count - 1, currentIndex + 1)
                viewModel.highlightedIndex = newIndex
                carouselScrollTarget = newIndex
            } else if !viewModel.filteredWallpapers.isEmpty {
                viewModel.highlightedIndex = 0
                carouselScrollTarget = 0
            }
        } else {
            viewModel.moveSelection(direction: .right, columns: settingsManager.config.gridColumns)
        }
    }

    private var toastOverlay: some View {
        BackendToastView(message: toastMessage!)
            .zIndex(90)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: showToast)
    }

    private var randomOverlay: some View {
        RandomOverlayView(
            viewModel: viewModel,
            isShowing: $viewModel.isShowingRandomOverlay,
            setWallpaper: { wallpaper in setWallpaper(wallpaper) }
        )
        .zIndex(100)
        .transition(
            .asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .opacity
            )
        )
    }

    private func setWallpaper(_ wallpaper: ImageFile, backend: WalBackend? = nil) {
        currentWallpaper = wallpaper.name
        let usedBackend = backend ?? settingsManager.config.selectedBackend

        Task {
            do {
                // Copy selected image to dummy file (overwriting it)
                let fileManager = FileManager.default
                let dummyFileURL = URL(fileURLWithPath: settingsManager.config.dummyWallpaperFile)
                let dummyFilePath = dummyFileURL.path

                // Log to file for debugging
                let logPath = "/tmp/wallpaper_switcher.log"
                let timestamp = DateFormatter.localizedString(
                    from: Date(), dateStyle: .short, timeStyle: .medium)

                let logMessage = """
                    === Wallpaper Switcher Debug Log - \(timestamp) ===
                    Setting wallpaper: \(wallpaper.name)
                    Dummy file path: \(dummyFilePath)
                    Wal binary path: \(settingsManager.config.walBinaryPath)
                    Current working directory: \(fileManager.currentDirectoryPath)
                    Home directory: \(NSHomeDirectory())
                    PATH: \(ProcessInfo.processInfo.environment["PATH"] ?? "Not set")

                    """

                do {
                    if fileManager.fileExists(atPath: logPath) {
                        if var existingContent = try? String(
                            contentsOfFile: logPath, encoding: .utf8)
                        {
                            existingContent += "\n" + logMessage
                            try existingContent.write(
                                toFile: logPath, atomically: true, encoding: .utf8)
                        }
                    } else {
                        try logMessage.write(toFile: logPath, atomically: true, encoding: .utf8)
                    }
                } catch {
                    print("Could not write to log: \(error)")
                }

                print("Setting wallpaper: \(wallpaper.name)")
                print("Dummy file path: \(dummyFilePath)")
                print("Wal binary path: \(settingsManager.config.walBinaryPath)")
                print("Current working directory: \(fileManager.currentDirectoryPath)")
                print("Home directory: \(NSHomeDirectory())")
                print("PATH: \(ProcessInfo.processInfo.environment["PATH"] ?? "Not set")")

                // Check if wal binary exists
                print(
                    "Checking wal binary at configured path: \(settingsManager.config.walBinaryPath)"
                )
                if !fileManager.fileExists(atPath: settingsManager.config.walBinaryPath) {
                    print(
                        "WARNING: Wal binary not found at configured path: \(settingsManager.config.walBinaryPath)"
                    )

                    // Try common wal locations
                    let commonWalPaths = [
                        "/usr/local/bin/wal",
                        "/opt/homebrew/bin/wal",
                        "/usr/bin/wal",
                        "/Volumes/NightSky/babaisalive/.local/bin/wal",
                        NSHomeDirectory() + "/.local/bin/wal",
                        NSHomeDirectory() + "/bin/wal",
                    ]

                    var foundWal = false
                    for path in commonWalPaths {
                        if fileManager.fileExists(atPath: path) {
                            print("✓ Found wal at: \(path)")
                            settingsManager.config.walBinaryPath = path
                            foundWal = true
                            break
                        }
                    }

                    if !foundWal {
                        print("ERROR: Could not find wal binary in common locations")
                        return
                    }
                } else {
                    print(
                        "✓ Wal binary found at configured path: \(settingsManager.config.walBinaryPath)"
                    )
                }

                // Check if wal is executable
                do {
                    let attributes = try fileManager.attributesOfItem(
                        atPath: settingsManager.config.walBinaryPath)
                    if let permissions = attributes[.posixPermissions] as? NSNumber {
                        let isExecutable = permissions.intValue & 0o111 != 0
                        print(
                            "Wal permissions: \(String(format: "%o", permissions.intValue)), executable: \(isExecutable)"
                        )
                        if !isExecutable {
                            print("WARNING: Wal binary is not executable!")
                        }
                    }
                } catch {
                    print("Could not check wal permissions: \(error)")
                }

                // Copy the wallpaper file to the dummy location
                if fileManager.fileExists(atPath: dummyFilePath) {
                    try fileManager.removeItem(at: dummyFileURL)
                }
                try fileManager.copyItem(at: wallpaper.url, to: dummyFileURL)

                // Kill WallpaperAgent to force macOS to reload wallpaper
                let _ = await runShellCommand("killall WallpaperAgent")

                // Run wal command with the selected wallpaper using configured backend
                let walCommand =
                    "\(settingsManager.config.walBinaryPath) -i \"\(dummyFilePath)\" -n --backend \(usedBackend.rawValue)"
                print("Running wal command: \(walCommand)")
                let walSuccess = await runShellCommand(walCommand)

                if walSuccess {
                    print("✓ Wal command completed successfully")
                    // Wait a moment for wal to finish writing files
                    try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

                    // Verify wal actually worked by checking if colors file was updated
                    let walCachePath = NSHomeDirectory() + "/.cache/wal/colors"
                    if fileManager.fileExists(atPath: walCachePath) {
                        do {
                            let colorsContent = try String(
                                contentsOfFile: walCachePath, encoding: .utf8)
                            let colorLines = colorsContent.components(separatedBy: .newlines).filter
                            { !$0.isEmpty && $0.hasPrefix("#") }
                            print("✓ Wal updated colors file with \(colorLines.count) colors")

                            // Set system accent color from wal colors
                            await setAccentColorFromWal()

                            // Run pywalfox update if enabled
                            if settingsManager.config.runPywalfox {
                                print("Running pywalfox update...")
                                let pywalfoxSuccess = await runShellCommand("pywalfox update")
                                if pywalfoxSuccess {
                                    print("✓ Pywalfox update completed successfully")
                                } else {
                                    print("✗ Pywalfox update failed")
                                }
                            }

                            // Run custom shell script if configured
                            if !settingsManager.config.customScriptPath.isEmpty {
                                print("Running custom script: \(settingsManager.config.customScriptPath)")
                                let scriptSuccess = await runShellCommand(settingsManager.config.customScriptPath)
                                if scriptSuccess {
                                    print("✓ Custom script completed successfully")
                                } else {
                                    print("✗ Custom script failed")
                                }
                            }
                        } catch {
                            print("Error reading wal colors: \(error)")
                        }
                    } else {
                        print("WARNING: Wal colors file not found after command")
                    }

                    await MainActor.run {
                        settingsManager.config.lastSelectedWallpaperPath = wallpaper.url.path

                        let finalMessage = """
                            === Process Completed ===
                            ✓ File copied to: \(dummyFilePath)
                            ✓ WallpaperAgent killed
                            ✓ Wal command executed
                            ✓ Accent color updated from wal colors
                            ===============================
                            """

                        print("Wallpaper switching process completed")
                        print("✓ File copied to: \(dummyFilePath)")
                        print("✓ WallpaperAgent killed")
                        print("✓ Wal command executed")
                        print("✓ Accent color updated from wal colors")
                        print("===============================")

                        // Log completion to file
                        do {
                            let logPath = "/tmp/wallpaper_switcher.log"
                            if var existingContent = try? String(
                                contentsOfFile: logPath, encoding: .utf8)
                            {
                                existingContent += "\n" + finalMessage
                                try existingContent.write(
                                    toFile: logPath, atomically: true, encoding: .utf8)
                            }
                        } catch {
                            print("Could not write completion to log: \(error)")
                        }
                    }
                } else {
                    print("✗ Wal command failed")
                }
            } catch {
                print("Error setting wallpaper: \(error)")
            }
        }
    }

    private func restoreLastWallpaper() {
        let savedPath = settingsManager.config.lastSelectedWallpaperPath
        guard !savedPath.isEmpty else { return }
        let savedURL = URL(fileURLWithPath: savedPath)

        if let index = viewModel.filteredWallpapers.firstIndex(where: { $0.url == savedURL }) {
            lastSelectedWallpaperURL = savedURL
            viewModel.highlightedIndex = index
            viewModel.setCurrentWallpaper(viewModel.filteredWallpapers[index])
            if viewModel.viewMode == .carousel {
                carouselScrollTarget = index
            }
        }
    }

    private func cycleBackendAndSet(_ wallpaper: ImageFile) {
        let allBackends = WalBackend.allCases
        guard let currentIndex = allBackends.firstIndex(where: { $0.rawValue == settingsManager.config.selectedBackend.rawValue }) else { return }
        let nextIndex = (currentIndex + 1) % allBackends.count
        let nextBackend = allBackends[nextIndex]
        settingsManager.config.selectedBackend = nextBackend
        lastSelectedWallpaperURL = wallpaper.url
        viewModel.setCurrentWallpaper(wallpaper)
        setWallpaper(wallpaper, backend: nextBackend)
        showBackendToast(nextBackend)
    }

    private func showBackendToast(_ backend: WalBackend) {
        withAnimation(.easeInOut(duration: 0.2)) {
            toastMessage = "Backend: \(backend.displayName)"
            showToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showToast = false
                }
            }
        }
    }

    private func runShellCommand(_ command: String) async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        var environment = ProcessInfo.processInfo.environment
        // Add common paths that might be missing
        if let existingPath = environment["PATH"] {
            environment["PATH"] =
                existingPath
                + ":/Volumes/NightSky/babaisalive/.local/bin:/usr/local/bin:/opt/homebrew/bin"
        }
        task.environment = environment

        do {
            try task.run()
            let data = try pipe.fileHandleForReading.readToEnd()
            if let output = String(data: data ?? Data(), encoding: .utf8) {
                print("Command output: \(output)")
            }
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            print("Error running command: \(error)")
            return false
        }
    }

    private func setAccentColorFromWal() async {
        let walCachePath = NSHomeDirectory() + "/.cache/wal/colors"
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: walCachePath) {
            print("Wal colors file not found at \(walCachePath)")
            return
        }

        do {
            let colorsContent = try String(contentsOfFile: walCachePath, encoding: .utf8)
            let colorLines = colorsContent.components(separatedBy: .newlines).filter {
                !$0.isEmpty && $0.hasPrefix("#")
            }

            if colorLines.count >= 8 {
                // Use the 8th color (index 7) as the accent color
                let accentColorHex = colorLines[7].trimmingCharacters(in: .whitespacesAndNewlines)

                if colorFromHexString(accentColorHex) != nil {
                    let colorName = mapHexToSystemColorName(accentColorHex)
                    print("Setting accent color from wal: \(accentColorHex) -> \(colorName)")

                    // Set the accent color using defaults
                    let accentCommand = "defaults write -g AppleAccentColor -string '\(colorName)'"
                    let _ = await runShellCommand(accentCommand)

                    // Also try setting highlight color
                    let highlightCommand =
                        "defaults write -g AppleHighlightColor -string '\(accentColorHex)'"
                    let _ = await runShellCommand(highlightCommand)

                    // Restart system services to apply changes
                    let _ = await runShellCommand("killall Dock")
                    let _ = await runShellCommand("killall ControlCenter")
                }
            } else {
                print("Not enough colors found in wal colors file")
            }
        } catch {
            print("Error reading wal colors file: \(error)")
        }
    }

    private func colorFromHexString(_ hexString: String) -> NSColor? {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove # if present
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }

        // Ensure it's 6 characters (RGB)
        if hex.count == 3 {
            // Expand 3-digit hex to 6-digit
            let r = hex[hex.startIndex]
            let g = hex[hex.index(after: hex.startIndex)]
            let b = hex[hex.index(hex.startIndex, offsetBy: 2)]

            hex = "\(r)\(r)\(g)\(g)\(b)\(b)"
        } else if hex.count != 6 {
            return nil
        }

        var rgb: UInt64 = 0
        let scanner = Scanner(string: hex)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "0x")
        scanner.scanHexInt64(&rgb)

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0

        return NSColor(red: red, green: green, blue: blue, alpha: 1.0)
    }

    private func mapHexToSystemColorName(_ hexColor: String) -> String {
        // macOS system accent color names that can be set via defaults
        // Map the hex color to the closest system color
        guard let nsColor = colorFromHexString(hexColor),
            let rgbColor = nsColor.usingColorSpace(.sRGB)
        else {
            return "0"  // Default to blue
        }

        let hue = rgbColor.hueComponent
        let saturation = rgbColor.saturationComponent

        // Convert hue to degrees (0-360)
        let hueDegrees = hue * 360

        // Map to system color indices (0-7)
        // 0 = Blue, 1 = Purple, 2 = Pink, 3 = Red, 4 = Orange, 5 = Yellow, 6 = Green, 7 = Graphite
        if saturation < 0.3 { return "7" }  // Low saturation = graphite

        if hueDegrees >= 330 || hueDegrees < 15 { return "3" }  // Red
        if hueDegrees >= 15 && hueDegrees < 45 { return "4" }  // Orange
        if hueDegrees >= 45 && hueDegrees < 75 { return "5" }  // Yellow
        if hueDegrees >= 75 && hueDegrees < 165 { return "6" }  // Green
        if hueDegrees >= 165 && hueDegrees < 225 { return "0" }  // Blue
        if hueDegrees >= 225 && hueDegrees < 285 { return "1" }  // Purple
        if hueDegrees >= 285 && hueDegrees < 330 { return "2" }  // Pink

        return "0"  // Default to blue
    }
}

@MainActor
public class WallpaperSwitcherViewModel: ObservableObject {
    @Published public var wallpapers: [ImageFile] = []
    @Published public var currentWallpaper: ImageFile?
    @Published public var highlightedIndex: Int? = nil
    @Published public var sortOption: SortOption = .name {
        didSet {
            let log = "🔄 Sort option changed to: \(sortOption)"
            print(log)
            logToFile(log)
            updateFilteredWallpapers()
        }
    }
    @Published public var sortOrderAscending: Bool = true {
        didSet {
            let log = "🔄 Sort order changed to: \(sortOrderAscending ? "ascending" : "descending")"
            print(log)
            logToFile(log)
            updateFilteredWallpapers()
        }
    }
    @Published public var searchQuery: String = "" {
        didSet {
            highlightedIndex = nil
            updateFilteredWallpapers()
        }
    }
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var filteredWallpapers: [ImageFile] = []
    @Published public var gridRefreshID = UUID()
    @Published public var isShowingRandomOverlay = false
    @Published public var viewMode: ViewMode = .grid {
        didSet {
            highlightedIndex = nil
        }
    }
    @Published public var selectedColorFilter: ColorGroup?
    @Published public var colorCounts: [ColorGroup: Int] = [:]

    private var searchWorkItem: DispatchWorkItem?
    private var colorGroups: [URL: ColorGroup] = [:]

    public init() {}

    func updateFilteredWallpapers() {
        let log1 =
            "📊 Updating filtered wallpapers. Total: \(wallpapers.count), Sort: \(sortOption), Ascending: \(sortOrderAscending)"
        print(log1)
        logToFile(log1)

        var filtered =
            searchQuery.isEmpty
            ? wallpapers
            : wallpapers.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }

        if let selectedGroup = selectedColorFilter {
            filtered = filtered.filter { wallpaper in
                let group = colorGroups[wallpaper.url]
                return group == selectedGroup
            }
        }

        filteredWallpapers = filtered.sorted {
            switch sortOption {
            case .name:
                return $0.name.localizedCompare($1.name)
                    == (sortOrderAscending ? .orderedAscending : .orderedDescending)
            case .dateModified:
                return sortOrderAscending
                    ? $0.dateModified < $1.dateModified : $0.dateModified > $1.dateModified
            case .size:
                return sortOrderAscending ? $0.fileSize < $1.fileSize : $0.fileSize > $1.fileSize
            }
        }

        gridRefreshID = UUID()

        let log2 =
            "✅ Filtered wallpapers updated. Count: \(filteredWallpapers.count), RefreshID: \(gridRefreshID)"
        print(log2)
        logToFile(log2)
    }

    func computeAndStoreColorGroup(for wallpaper: ImageFile) async {
        guard let color = await DominantColorCache.shared.dominantColor(for: wallpaper.url) else { return }
        let group = color.colorGroup
        await MainActor.run {
            colorGroups[wallpaper.url] = group
            var counts: [ColorGroup: Int] = [:]
            for (_, g) in colorGroups {
                counts[g, default: 0] += 1
            }
            colorCounts = counts
            updateFilteredWallpapers()
        }
    }

    func computeAllColorGroups(for imageFiles: [ImageFile]) async -> [URL: ColorGroup] {
        print("🎨 Starting pre-computation of colors for \(imageFiles.count) images")
        var result: [URL: ColorGroup] = [:]

        await withTaskGroup(of: (URL, ColorGroup?).self) { group in
            for imageFile in imageFiles {
                group.addTask {
                    let color = DominantColorCache.shared.dominantColor(for: imageFile.url)
                    return (imageFile.url, color?.colorGroup)
                }
            }
            for await (url, group) in group {
                if let group { result[url] = group }
            }
        }
        print("✅ Pre-computed \(result.count) colors")
        return result
    }

    func loadCachedColors(for imageFiles: [ImageFile]) -> [URL: ColorGroup] {
        var result: [URL: ColorGroup] = [:]
        for imageFile in imageFiles {
            if let color = DominantColorCache.shared.dominantColor(for: imageFile.url) {
                result[imageFile.url] = color.colorGroup
            }
        }
        return result
    }

    func buildColorCounts(from colors: [URL: ColorGroup]) -> [ColorGroup: Int] {
        var counts: [ColorGroup: Int] = [:]
        for (_, group) in colors {
            counts[group, default: 0] += 1
        }
        return counts
    }

    func registerColorGroup(_ group: ColorGroup, for url: URL) {
        guard colorGroups[url] == nil else { return }
        colorGroups[url] = group
        print("🎨 Color registered: \(group.rawValue) for \(url.lastPathComponent) (total: \(colorGroups.count))")
        var counts: [ColorGroup: Int] = [:]
        for (_, g) in colorGroups {
            counts[g, default: 0] += 1
        }
        print("📊 Color counts: \(counts)")
        colorCounts = counts
        updateFilteredWallpapers()
    }

    private func logToFile(_ message: String) {
        let logDir = "/tmp/wallswitcherlogs"
        let logFile = "\(logDir)/app.log"

        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)

        let timestamp = DateFormatter.localizedString(
            from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)\n"

        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile) {
                if let fileHandle = FileHandle(forWritingAtPath: logFile) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logFile))
            }
        }
    }

    // Cache directory cleanup (call periodically)
    func cleanupOldCache() {
        let cache = ThumbnailCache.shared
        let cacheDir = cache.cacheDirectory

        DispatchQueue.global(qos: .background).async {
            do {
                let fm = FileManager.default
                let cacheContents = try fm.contentsOfDirectory(
                    at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey])
                let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)

                var deletedCount = 0
                for itemURL in cacheContents {
                    if let modDate = try? itemURL.resourceValues(forKeys: [
                        .contentModificationDateKey
                    ]).contentModificationDate,
                        modDate < thirtyDaysAgo
                    {
                        try? fm.removeItem(at: itemURL)
                        deletedCount += 1
                    }
                }

                if deletedCount > 0 {
                    print("🧹 Cleaned up \(deletedCount) old thumbnail cache files")
                }
            } catch {
                print("Failed to cleanup thumbnail cache: \(error)")
            }
        }
    }

    private let supportedImageTypes: [UTType] = [.jpeg, .png, .gif, .bmp, .tiff, .webP]

    var sortOrderLabel: String {
        switch sortOption {
        case .name:
            return sortOrderAscending ? "a-z" : "z-a"
        case .dateModified:
            return sortOrderAscending ? "earliest" : "recent"
        case .size:
            return sortOrderAscending ? "smallest" : "largest"
        }
    }

    func loadWallpapers(from folderPath: String) {
        guard !folderPath.isEmpty else {
            print("⚠️ loadWallpapers called with empty folderPath")
            wallpapers = []
            return
        }

        print("📂 Loading wallpapers from: \(folderPath)")
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let folderURL = URL(fileURLWithPath: folderPath)
                let enumerator = FileManager.default.enumerator(
                    at: folderURL,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )

                var imageFiles: [ImageFile] = []
                while let fileURL = enumerator?.nextObject() as? URL {
                    guard
                        let fileType = try? fileURL.resourceValues(forKeys: [.contentTypeKey])
                            .contentType,
                        supportedImageTypes.contains(fileType)
                    else {
                        continue
                    }
                    imageFiles.append(ImageFile(url: fileURL))
                }

                print("📷 Found \(imageFiles.count) image files")

                // Background thumbnail generation (simplified)
                DispatchQueue.global(qos: .utility).async {
                    for imageFile in imageFiles {
                        let _ = ThumbnailCache.shared.generateAndCacheThumbnail(
                            for: imageFile.url, size: .medium)
                    }
                    print("✓ Generated cached thumbnails for \(imageFiles.count) images")
                }

                // Load cached colors from disk instantly, compute new ones in background
                print("🎨 Loading cached colors for \(imageFiles.count) images")
                let cachedColors = self.loadCachedColors(for: imageFiles)
                print("🎨 Found \(cachedColors.count) cached colors")
                let newImageFiles = imageFiles.filter { cachedColors[$0.url] == nil }
                print("🎨 \(newImageFiles.count) new images to compute")

                print("🎨 About to update UI on MainActor")
                await MainActor.run {
                    self.wallpapers = imageFiles
                    self.colorGroups = cachedColors
                    self.colorCounts = self.buildColorCounts(from: cachedColors)
                    self.isLoading = false
                    self.updateFilteredWallpapers()
                    print("✅ Loaded \(imageFiles.count) wallpapers, \(cachedColors.count) colors from cache, \(newImageFiles.count) to compute")
                    print("📊 Color breakdown: \(self.colorCounts)")
                }

                // Compute colors for new wallpapers in background
                if !newImageFiles.isEmpty {
                    let newColors = await self.computeAllColorGroups(for: newImageFiles)
                    await MainActor.run {
                        self.colorGroups.merge(newColors) { _, new in new }
                        self.colorCounts = self.buildColorCounts(from: self.colorGroups)
                        self.updateFilteredWallpapers()
                        print("✅ Computed \(newColors.count) new colors")
                    }
                }

                // Clean up stale cache entries (deleted wallpapers)
                let validURLs = Set(imageFiles.map { $0.url })
                DominantColorCache.shared.cleanup(for: validURLs)
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load wallpapers: \(error.localizedDescription)"
                    self.wallpapers = []
                    self.isLoading = false
                }
            }
        }
    }

    func sortWallpapers() {
        wallpapers.sort { lhs, rhs in
            switch sortOption {
            case .name:
                return lhs.name.localizedCompare(rhs.name)
                    == (sortOrderAscending ? .orderedAscending : .orderedDescending)
            case .dateModified:
                return sortOrderAscending
                    ? lhs.dateModified < rhs.dateModified : lhs.dateModified > rhs.dateModified
            case .size:
                return sortOrderAscending
                    ? lhs.fileSize < rhs.fileSize : lhs.fileSize > rhs.fileSize
            }
        }
        objectWillChange.send()
    }

    func setCurrentWallpaper(_ wallpaper: ImageFile) {
        currentWallpaper = wallpaper
    }

    func randomizeWallpaper() {
        guard !wallpapers.isEmpty else { return }
        let randomIndex = Int.random(in: 0..<wallpapers.count)
        let randomWallpaper = wallpapers[randomIndex]
        setCurrentWallpaper(randomWallpaper)
        print("🎲 Selected random wallpaper: \(randomWallpaper.name)")
    }

    public func moveSelection(direction: NavigationDirection, columns: Int) {
        let count = filteredWallpapers.count
        guard count > 0 else { return }

        let currentIndex = highlightedIndex ?? -1

        var nextIndex: Int
        switch direction {
        case .left:
            if currentIndex == -1 {
                nextIndex = 0
            } else {
                nextIndex = max(0, currentIndex - 1)
            }
        case .right:
            if currentIndex == -1 {
                nextIndex = 0
            } else {
                nextIndex = min(count - 1, currentIndex + 1)
            }
        case .up:
            if currentIndex == -1 {
                nextIndex = 0
            } else {
                nextIndex = max(0, currentIndex - columns)
            }
        case .down:
            if currentIndex == -1 {
                nextIndex = 0
            } else {
                nextIndex = min(count - 1, currentIndex + columns)
            }
        }

        if nextIndex != highlightedIndex {
            highlightedIndex = nextIndex
        }
    }

    public func moveAndSelect(
        direction: NavigationDirection, columns: Int, setWallpaper: (ImageFile) -> Void
    ) {
        let count = filteredWallpapers.count
        guard count > 0 else { return }

        let currentIndex = highlightedIndex ?? -1

        var nextIndex: Int
        switch direction {
        case .left:
            nextIndex = currentIndex == -1 ? 0 : max(0, currentIndex - 1)
        case .right:
            nextIndex = currentIndex == -1 ? 0 : min(count - 1, currentIndex + 1)
        case .up:
            nextIndex = currentIndex == -1 ? 0 : max(0, currentIndex - columns)
        case .down:
            nextIndex = currentIndex == -1 ? 0 : min(count - 1, currentIndex + columns)
        }

        if nextIndex != highlightedIndex {
            highlightedIndex = nextIndex
            let wallpaper = filteredWallpapers[nextIndex]
            setCurrentWallpaper(wallpaper)
            setWallpaper(wallpaper)
        }
    }
}

struct WallpaperCardView: View {
    let wallpaper: ImageFile
    let isSelected: Bool
    let isHighlighted: Bool
    let availableWidth: CGFloat
    let columns: Int
    let onSelect: () -> Void

    @State private var thumbnailImage: Image?
    @State private var dominantColor: Color?

    private var cardWidth: CGFloat {
        (availableWidth - CGFloat(columns - 1) * 12 - 24) / CGFloat(columns)
    }

    private var imageHeight: CGFloat {
        cardWidth * 0.56
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let dominantColor = dominantColor {
                    dominantColor
                        .frame(width: cardWidth, height: imageHeight)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: cardWidth, height: imageHeight)
                }

                if let thumbnailImage = thumbnailImage {
                    thumbnailImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cardWidth, height: imageHeight)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, .blue)
                        .font(.title2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(wallpaper.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: cardWidth)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.tint, lineWidth: isHighlighted ? 2 : 0)
        )
        .onTapGesture { onSelect() }
        .task {
            if let nsImage = await OptimizedImageCache.shared.loadThumbnail(
                for: wallpaper.url,
                size: CGSize(width: cardWidth, height: imageHeight)
            ) {
                thumbnailImage = Image(nsImage: nsImage)
            }
            if let color = await DominantColorCache.shared.dominantColor(for: wallpaper.url) {
                dominantColor = Color(color)
            }
        }

    }
}

struct CarouselCardView: View {
    let wallpaper: ImageFile
    let isSelected: Bool
    let isCentered: Bool
    let cardWidth: CGFloat
    let onSelect: () -> Void

    @State private var thumbnailImage: Image?

    private var cardHeight: CGFloat {
        cardWidth * 9 / 16
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let thumbnailImage = thumbnailImage {
                    thumbnailImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if isCentered {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white, lineWidth: 1.5)
                            .opacity(0.45)
                    }
                }
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 40))
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, .blue)
                        .font(.title2)
                        .padding(8)
                }
            }

            Text(wallpaper.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: cardWidth)
        }
        .frame(width: cardWidth)
        .scaleEffect(isCentered ? 1.08 : 0.92)
        .opacity(isCentered ? 1.0 : 0.75)
        .shadow(
            color: isCentered ? .black.opacity(0.3) : .black.opacity(0.1),
            radius: isCentered ? 12 : 6,
            x: 0,
            y: isCentered ? 8 : 4
        )
        .animation(.easeInOut(duration: 0.3), value: isCentered)
        .onTapGesture { onSelect() }
        .task {
            if let nsImage = await OptimizedImageCache.shared.loadThumbnail(
                for: wallpaper.url,
                size: CGSize(width: cardWidth, height: cardHeight)
            ) {
                thumbnailImage = Image(nsImage: nsImage)
            }
        }
    }
}

/// Simple toast notification showing the active backend name.
struct BackendToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "paintpalette")
                .font(.system(size: 14, weight: .medium))
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
