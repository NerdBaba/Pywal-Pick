import Foundation
import SwiftUI

struct RandomOverlayView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @ObservedObject var viewModel: WallpaperSwitcherViewModel
    @Binding var isShowing: Bool
    @State private var selectedWallpaper: ImageFile?
    @State private var previewImage: Image?
    @State private var previewID = UUID()
    @State private var showingDeleteAlert = false
    var setWallpaper: (ImageFile) -> Void

    var body: some View {
        ZStack(alignment: .center) {
            // Blur/translucency backdrop (avoid solid/dark blocks).
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.9)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isShowing = false }
                .transition(.opacity)

            // Centered popover container
            VStack(spacing: UIStyle.spaceXXL) {
                // Header
                HStack {
                    Label("Random Wallpaper", systemImage: "shuffle")
                        .font(.custom("Nunito Sans ExtraBold", size: 22))
                        .foregroundStyle(.primary)
                        .labelStyle(.titleAndIcon)
                        .symbolRenderingMode(.hierarchical)

                    Spacer()

                    Button {
                        isShowing = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, UIStyle.spaceXXL)
                .padding(.top, UIStyle.spaceLG)

                // Preview area
                ZStack {
                    if let previewImage = previewImage {
                        previewImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 500, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: UIStyle.radiusMD, style: .continuous))
                            .id(previewID)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.96).combined(with: .opacity),
                                removal: .opacity
                            ))
                    } else {
                        ContentUnavailableView {
                            Label("Loading preview", systemImage: "photo.on.rectangle.angled")
                        }
                        .frame(maxWidth: 500, maxHeight: 300)
                    }
                }
                .frame(maxWidth: 500, maxHeight: 300)
                .background(
                    RoundedRectangle(cornerRadius: UIStyle.radiusMD, style: .continuous)
                        .fill(.quaternary.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: UIStyle.radiusMD, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: UIStyle.hairline)
                )

                // Wallpaper info
                if let wallpaper = selectedWallpaper {
                    VStack(spacing: UIStyle.spaceSM) {
                        Text(wallpaper.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: UIStyle.spaceLG) {
                            Label(
                                formattedFileSize(wallpaper.fileSize),
                                systemImage: "doc"
                            )
                            .font(UIStyle.caption)
                            .foregroundStyle(.secondary)

                            Label(formattedDate(wallpaper.dateModified), systemImage: "calendar")
                                .font(UIStyle.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Action buttons
                HStack(spacing: UIStyle.spaceMD) {
                    Button {
                        pickRandomWallpaper()
                    } label: {
                        Label("Respin", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        if let wallpaper = selectedWallpaper {
                            setWallpaper(wallpaper)
                            isShowing = false
                        }
                    } label: {
                        Label("Set Wallpaper", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedWallpaper == nil)

                    Button {
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.large)
                    .disabled(selectedWallpaper == nil)
                    .alert("Delete Wallpaper?", isPresented: $showingDeleteAlert, presenting: selectedWallpaper) { wallpaper in
                        Button("Delete", role: .destructive) {
                            deleteWallpaper(wallpaper)
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: { wallpaper in
                        Text("Are you sure you want to delete \"\(wallpaper.name)\"? This action cannot be undone.")
                    }
                }
                .padding(.horizontal, UIStyle.spaceXXL)
            }
            .padding(.vertical, UIStyle.spaceXXL)
            .background(
                VisualEffectView(material: .popover, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: UIStyle.radiusXL, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIStyle.radiusXL, style: .continuous)
                    .strokeBorder(.primary.opacity(0.1), lineWidth: UIStyle.hairline)
            )
            .uiElevatedShadow()
            .frame(width: 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            pickRandomWallpaper()
        }
    }

    private func pickRandomWallpaper() {
        if !viewModel.wallpapers.isEmpty {
            let randomIndex = Int.random(in: 0..<viewModel.wallpapers.count)
            selectedWallpaper = viewModel.wallpapers[randomIndex]
            loadPreviewImage(for: selectedWallpaper!.url)

            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                previewID = UUID()
            }
        }
    }

    private func loadPreviewImage(for url: URL) {
        Task {
            if let nsImage = await OptimizedImageCache.shared.loadThumbnail(
                for: url,
                size: CGSize(width: 800, height: 450)
            ) {
                await MainActor.run {
                    previewImage = Image(nsImage: nsImage)
                }
            }
        }
    }

    private func formattedFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func deleteWallpaper(_ wallpaper: ImageFile) {
        do {
            try FileManager.default.removeItem(at: wallpaper.url)
            if let index = viewModel.wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
                viewModel.wallpapers.remove(at: index)
                viewModel.updateFilteredWallpapers()
            }
            pickRandomWallpaper()
        } catch {
            print("Failed to delete wallpaper: \(error)")
        }
    }
}

// VisualEffectView for better material effects
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
