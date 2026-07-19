import AppKit
import Foundation
import SwiftUI

/// A temporary full-screen window pinned at the **desktop-picture layer**
/// (above the system wallpaper, below the desktop icons and all normal windows).
/// It plays an animated transition (old wallpaper -> new wallpaper), then the
/// caller applies `wal` underneath and the window fades out to reveal the
/// already-changed real desktop.
///
/// Technique from native macOS wallpaper apps (Mural, Whisky Wallpaper):
/// `CGWindowLevelForKey(.desktopWindow)` places content exactly on the desktop
/// picture layer rather than floating above app windows.
final class TransitionOverlayController: @unchecked Sendable {
    static let shared = TransitionOverlayController()

    private var activeWindows: [NSWindow] = []
    private var displayTimer: Timer?
    private var progress: TransitionProgress?

    private init() {}

    /// Play the transition, then run `completion` (which applies the wallpaper),
    /// then fade the overlay out to reveal the desktop.
    /// - Parameters:
    ///   - oldURL: image currently shown on the desktop (fallback: newURL).
    ///   - newURL: the wallpaper being applied.
    ///   - type: concrete transition effect (`.random` must be resolved first).
    ///   - duration: total transition time in seconds.
    ///   - fps: target frame rate.
    ///   - completion: executed once the transition reaches progress 1.0.
    nonisolated func play(
        oldURL: URL,
        newURL: URL,
        type: TransitionType,
        duration: Double,
        fps: Int,
        completion: @escaping @Sendable () -> Void
    ) {
        let effect = type.resolved
        let oldImage = NSImage(contentsOf: oldURL) ?? NSImage(contentsOf: newURL)
        let newImage = NSImage(contentsOf: newURL) ?? oldImage

        let progress = TransitionProgress()
        let rootView = TransitionImageView(
            progress: progress,
            oldImage: oldImage,
            newImage: newImage,
            effect: effect
        )

        let fps = max(1, min(fps, 120))
        let step = 1.0 / max(0.05, (duration * Double(fps)))

        let setup: @MainActor () -> Void = {
            self.progress = progress
            let windows = self.makeWindows(for: rootView)
            self.activeWindows = windows

            let timer = Timer.scheduledTimer(
                withTimeInterval: 1.0 / Double(fps),
                repeats: true
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.advance(step: step, completion: completion)
                }
            }
            self.displayTimer = timer
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated { setup() }
        } else {
            DispatchQueue.main.sync { MainActor.assumeIsolated { setup() } }
        }
    }

    @MainActor
    private func advance(
        step: Double,
        completion: @escaping @Sendable () -> Void
    ) {
        progress?.value = min((progress?.value ?? 0) + step, 1.0)
        if (progress?.value ?? 0) >= 1.0 {
            stopTimer()
            completion()
            fadeAndClose()
        }
    }

    @MainActor
    private func stopTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    @MainActor
    private func makeWindows(for rootView: TransitionImageView) -> [NSWindow] {
        var windows: [NSWindow] = []
        for screen in NSScreen.screens {
            let window = DesktopTransitionWindow(screen: screen)
            let hosting = NSHostingView(rootView: rootView)
            hosting.frame = window.contentLayoutRect
            hosting.autoresizingMask = [.width, .height]
            window.contentView = hosting
            window.orderFrontRegardless()
            windows.append(window)
        }
        return windows
    }

    @MainActor
    private func fadeAndClose() {
        let windows = activeWindows

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            for window in windows {
                window.animator().alphaValue = 0
            }
        }, completionHandler: {
            Task { @MainActor in
                for window in windows {
                    window.close()
                }
                self.activeWindows.removeAll()
            }
        })
    }
}

/// Borderless window pinned at the desktop-picture level: above the system
/// wallpaper, below the desktop icons and all app windows (click-through).
final class DesktopTransitionWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isRestorable = false
        setFrame(screen.frame, display: true)
    }
}

/// Progress holder owned by the controller and observed by the transition view.
/// Stored as a reference so the controller can mutate it and the view updates.
final class TransitionProgress: ObservableObject {
    @Published var value: Double = 0
}

/// SwiftUI view that composites the old and new wallpaper images according to
/// the selected transition effect, driven by a `progress` value (0 -> 1).
struct TransitionImageView: View {
    @ObservedObject var progress: TransitionProgress
    let oldImage: NSImage?
    let newImage: NSImage?
    let effect: TransitionType

    private var eased: Double {
        // Simple ease-in-out (swww uses Bezier curves; this is sufficient here).
        let t = min(max(progress.value, 0), 1)
        return t * t * (3 - 2 * t)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let oldImage {
                    Image(nsImage: oldImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }

                switch effect {
                case .fade:
                    fadeLayer(geometry: geometry)
                case .wipe:
                    wipeLayer(geometry: geometry)
                case .grow:
                    growLayer(geometry: geometry)
                case .random:
                    fadeLayer(geometry: geometry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func fadeLayer(geometry: GeometryProxy) -> some View {
        if let newImage {
            Image(nsImage: newImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .opacity(eased)
        }
    }

    @ViewBuilder
    private func wipeLayer(geometry: GeometryProxy) -> some View {
        let width = geometry.size.width * eased
        if let newImage {
            Image(nsImage: newImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .clipShape(Rectangle())
                .offset(x: -geometry.size.width + width, y: 0)
        }
    }

    @ViewBuilder
    private func growLayer(geometry: GeometryProxy) -> some View {
        let radius = eased * geometry.size.diagonal / 2
        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        if let newImage {
            Image(nsImage: newImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .clipShape(
                    Circle()
                        .path(in: CGRect(
                            x: center.x - radius,
                            y: center.y - radius,
                            width: radius * 2,
                            height: radius * 2))
                )
        }
    }
}

private extension CGSize {
    var diagonal: CGFloat {
        sqrt(width * width + height * height)
    }
}
