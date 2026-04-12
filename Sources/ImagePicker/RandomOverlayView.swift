import Foundation
import SwiftUI

struct RandomOverlayView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @ObservedObject var viewModel: WallpaperSwitcherViewModel
    @Binding var isShowing: Bool
    @State private var selectedWallpaper: ImageFile?
    @State private var isAnimating = false
    @State private var animationScale: CGFloat = 0.8
    @State private var animationOpacity: Double = 0.0
    @State private var animationRotation: Double = 0.0
    @State private var previewImage: Image?
    @State private var isLoading = false
    var setWallpaper: (ImageFile) -> Void

    var body: some View {
        ZStack(alignment: .center) {
            // Blur/translucency backdrop (avoid solid/dark blocks).
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.85)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isShowing = false }
                .transition(.opacity)

            // Centered popover container
            VStack(spacing: 24) {
                // Header
                HStack {
                    Text("Random Wallpaper")
                        .font(.custom("Nunito Sans ExtraBold", size: 24))
                        .foregroundColor(.primary)

                    Spacer()

                    Button(action: {
                        isShowing = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.primary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Preview area with animation
                ZStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                    } else if let previewImage = previewImage {
                        previewImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 500, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .scaleEffect(animationScale)
                            .opacity(animationOpacity)
                            .rotationEffect(.degrees(animationRotation))
                            .animation(
                                .interpolatingSpring(
                                    mass: 0.8,
                                    stiffness: 120,
                                    damping: 12,
                                    initialVelocity: 0
                                )
                                .speed(1.2),
                                value: animationScale
                            )
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 80))
                            .foregroundColor(.primary.opacity(0.5))
                    }
                }
                .frame(maxWidth: 500, maxHeight: 300)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                )

                // Wallpaper info
                if let wallpaper = selectedWallpaper {
                    VStack(spacing: 8) {
                        Text(wallpaper.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 16) {
                            Label(
                                "Size: " + formattedFileSize(wallpaper.fileSize), systemImage: "doc"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)

                            Label(formattedDate(wallpaper.dateModified), systemImage: "calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Action buttons
                HStack(spacing: 16) {
                    Button(action: {
                        // Respin - get another random wallpaper
                        pickRandomWallpaper()
                    }) {
                        Label("Respin", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .controlSize(.large)

                    Button(action: {
                        // Set as wallpaper
                        if let wallpaper = selectedWallpaper {
                            viewModel.setCurrentWallpaper(wallpaper)
                            setWallpaper(wallpaper)
                            isShowing = false
                        }
                    }) {
                        Label("Set Wallpaper", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)

                    Button(action: {
                        // Cancel
                        isShowing = false
                    }) {
                        Label("Cancel", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.large)
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 24)
            .background(
                VisualEffectView(material: .popover, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .gray.opacity(0.25), radius: 20, x: 0, y: 10)
            )
            .frame(width: 600)
            .shadow(radius: 0)  // Remove outer shadow since we added it to the background
        }
        // Ensure the overlay covers the full view (so it behaves like a popover).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            pickRandomWallpaper()
        }
    }

    private func pickRandomWallpaper() {
        isLoading = true
        animationScale = 0.8
        animationOpacity = 0.0
        animationRotation = Double.random(in: -5...5)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !viewModel.wallpapers.isEmpty {
                let randomIndex = Int.random(in: 0..<viewModel.wallpapers.count)
                selectedWallpaper = viewModel.wallpapers[randomIndex]

                // Load preview image
                loadPreviewImage(for: selectedWallpaper!.url)

                // Trigger animation
                withAnimation {
                    animationScale = 1.0
                    animationOpacity = 1.0
                    animationRotation = 0.0
                }
            }
            isLoading = false
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
