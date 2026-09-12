import SwiftUI

struct WallhavenView: View {
    @ObservedObject var viewModel: WallhavenViewModel
    @ObservedObject var settingsManager: SettingsManager

    @State private var columns = 4
    @State private var showColorPicker = false

    private let spacing: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider().opacity(0.45)
            contentArea
        }
        .onAppear {
            viewModel.apiKey = settingsManager.config.wallhavenAPIKey
            if viewModel.results.isEmpty && viewModel.searchQuery.isEmpty {
                Task { await viewModel.search() }
            }
        }
    }

    private var searchHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search wallhaven.cc…", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))

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
                                    viewModel.params.categories = enabled
                                        ? viewModel.params.categories.union([category])
                                        : viewModel.params.categories.subtracting([category])
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
                                            viewModel.params.topRange = range
                                            Task { await viewModel.search() }
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
                        Rectangle()
                            .fill(color.color)
                            .frame(width: 24, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(viewModel.params.color == color ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture {
                                viewModel.setColor(viewModel.params.color == color ? nil : color)
                            }
                            .help(color.displayName)
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
        if viewModel.results.isEmpty && !viewModel.isLoading && !viewModel.hasError {
            emptyState
        } else if viewModel.hasError && viewModel.results.isEmpty {
            errorState
        } else {
            resultsGrid
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(viewModel.searchQuery.isEmpty ? "Search wallhaven.cc" : "No results found")
                .font(.headline)
            Text(viewModel.searchQuery.isEmpty ?
                "Enter a search term to find wallpapers" :
                "Try adjusting your filters")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
                spacing: spacing
            ) {
                ForEach(viewModel.results) { wallpaper in
                    WallhavenThumbnailCard(
                        wallpaper: wallpaper,
                        isDownloaded: viewModel.downloadedIds.contains(wallpaper.id),
                        downloadProgress: viewModel.downloadProgress[wallpaper.id],
                        onTap: { viewModel.preview(wallpaper) },
                        onDownload: {
                            Task {
                                _ = await viewModel.download(wallpaper, to: settingsManager.config.wallpaperFolderPath)
                            }
                        },
                        onSetWallpaper: {
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
                }

                if viewModel.hasMorePages {
                    ProgressView()
                        .frame(height: 40)
                        .onAppear {
                            Task { await viewModel.loadNextPage() }
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
    }
}

struct WallhavenThumbnailCard: View {
    let wallpaper: WallhavenWallpaper
    let isDownloaded: Bool
    let downloadProgress: Double?
    let onTap: () -> Void
    let onDownload: () -> Void
    let onSetWallpaper: () -> Void

    @State private var thumbnailImage: Image?
    @State private var isHovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary.opacity(0.15))
                .aspectRatio(wallpaper.aspectRatio, contentMode: .fit)

            if let thumbnailImage {
                thumbnailImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            if isHovered {
                Color.black.opacity(0.3)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 8) {
                    Button(action: onDownload) {
                        Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button(action: onSetWallpaper) {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
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

            if isDownloaded && !isHovered {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding(6)
            }
        }
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Preview", systemImage: "eye") { onTap() }
            Button("Download", systemImage: "arrow.down.circle") { onDownload() }
            Button("Set as Wallpaper", systemImage: "photo") { onSetWallpaper() }
            Divider()
            Button("Open on Wallhaven", systemImage: "safari") {
                NSWorkspace.shared.open(URL(string: wallpaper.url)!)
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
        guard let url = URL(string: wallpaper.thumbs.large) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let nsImage = NSImage(data: data) {
                await MainActor.run {
                    thumbnailImage = Image(nsImage: nsImage)
                }
            }
        } catch {
            // Silently fail - show placeholder
        }
    }
}

struct WallhavenPreviewView: View {
    let wallpaper: WallhavenWallpaper
    let isDownloaded: Bool
    let downloadProgress: Double?
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
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
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
                    Button("Download", systemImage: "arrow.down.circle") {
                        onDownload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button("Set as Wallpaper", systemImage: "photo") {
                        onSetWallpaper()
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Open in Browser", systemImage: "safari") {
                        NSWorkspace.shared.open(URL(string: wallpaper.url)!)
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
        guard let url = URL(string: wallpaper.thumbs.original) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let nsImage = NSImage(data: data) {
                await MainActor.run {
                    previewImage = Image(nsImage: nsImage)
                }
            }
        } catch {
            guard let fallbackURL = URL(string: wallpaper.thumbs.large) else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: fallbackURL)
                if let nsImage = NSImage(data: data) {
                    await MainActor.run {
                        previewImage = Image(nsImage: nsImage)
                    }
                }
            } catch { }
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
