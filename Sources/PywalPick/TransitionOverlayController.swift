import AppKit
import QuartzCore
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
public final class TransitionOverlayController: @unchecked Sendable {
    public static let shared = TransitionOverlayController()

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
    @MainActor
    public func play(
        oldURL: URL,
        newURL: URL,
        type: TransitionType,
        duration: Double,
        fps: Int,
        completion: @escaping () -> Void
    ) {
        let effect = type.resolved
        let oldImage = NSImage(contentsOf: oldURL) ?? NSImage(contentsOf: newURL)
        let newImage = NSImage(contentsOf: newURL) ?? oldImage

        // For grow effect, use AppKit-only view to ensure consistent rendering
        // in both GUI and CLI contexts (bypassing potential SwiftUI rendering issues)
        if effect == .grow {
            playGrowTransition(
                oldImage: oldImage,
                newImage: newImage,
                duration: duration,
                fps: fps,
                completion: completion
            )
            return
        }

        let progress = ProgressObject()
        let windows: [(NSWindow, NSHostingView, CGSize)] = NSScreen.screens.map { screen in
            let window = DesktopTransitionWindow(screen: screen)
            let screenSize = window.contentLayoutRect.size
            let hosting = NSHostingView(rootView: TransitionImageView(
                progress: progress,
                oldImage: oldImage,
                newImage: newImage,
                effect: effect,
                screenSize: screenSize
            ))
            hosting.frame = window.contentLayoutRect
            hosting.autoresizingMask = [.width, .height]
            window.contentView = hosting
            window.orderFrontRegardless()
            return (window, hosting, screenSize)
        }

        let step = 1.0 / max(0.05, (duration * Double(fps)))
        let totalSteps = max(1, Int((duration * Double(fps)).rounded()))
        let interval = 1.0 / Double(fps)

        func tick(currentStep: Int) {
            let newValue = min(Double(currentStep) * step, 1.0)
            progress.value = newValue

            for (_, hosting, _) in windows {
                hosting.needsDisplay = true
            }

            if currentStep >= totalSteps {
                for (window, _, _) in windows {
                    window.animator().alphaValue = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    for (window, _, _) in windows {
                        window.close()
                    }
                    completion()
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                    tick(currentStep: currentStep + 1)
                }
            }
        }

        tick(currentStep: 1)
    }

    /// AppKit-only grow transition that bypasses SwiftUI for consistent rendering.
    @MainActor
    private func playGrowTransition(
        oldImage: NSImage?,
        newImage: NSImage?,
        duration: Double,
        fps: Int,
        completion: @escaping () -> Void
    ) {
        let windows: [(NSWindow, GrowTransitionView)] = NSScreen.screens.map { screen in
            let window = DesktopTransitionWindow(screen: screen)
            let transitionView = GrowTransitionView(oldImage: oldImage, newImage: newImage)
            transitionView.frame = window.contentLayoutRect
            transitionView.autoresizingMask = [.width, .height]
            window.contentView = transitionView
            // Force layout to ensure frame is set before animation starts
            transitionView.layoutSubtreeIfNeeded()
            transitionView.displayIfNeeded()
            window.orderFrontRegardless()
            return (window, transitionView)
        }

        let step = 1.0 / max(0.05, (duration * Double(fps)))
        let totalSteps = max(1, Int((duration * Double(fps)).rounded()))
        let interval = 1.0 / Double(fps)

        func tick(currentStep: Int) {
            let progress = min(Double(currentStep) * step, 1.0)

            for (_, view) in windows {
                view.setProgress(progress)
            }

            if currentStep >= totalSteps {
                for (window, _) in windows {
                    window.animator().alphaValue = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    for (window, _) in windows {
                        window.close()
                    }
                    completion()
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                    tick(currentStep: currentStep + 1)
                }
            }
        }

        tick(currentStep: 1)
    }
}

/// Progress holder observed by the transition view.
final class ProgressObject: ObservableObject {
    @Published var value: Double = 0
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

/// Computes the rect an image must occupy so it **fills** `size` (aspect-fill /
/// "cover"), cropping the overflow and centering the result. This matches the
/// macOS "Fill Screen" desktop wallpaper behavior, which is what `wal` applies.
private func coverRect(for image: NSImage, in size: CGSize) -> CGRect {
    let imgSize = image.size
    guard imgSize.width > 0, imgSize.height > 0 else {
        return CGRect(origin: .zero, size: size)
    }
    let scale = max(size.width / imgSize.width, size.height / imgSize.height)
    let w = imgSize.width * scale
    let h = imgSize.height * scale
    return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
}

/// An NSView that renders an NSImage exactly as macOS renders its desktop
/// wallpaper: fill screen, centered, crop overflow (aspect-fill / "cover").
/// Using the same AppKit scaling path keeps the overlay pixel-aligned with the
/// real wallpaper so the transition does not jump (and avoids black bars).
final class NSImageLayerView: NSView {
    let imageView: NSImageView

    init(image: NSImage?) {
        self.imageView = NSImageView()
        self.imageView.image = image
        self.imageView.imageScaling = .scaleAxesIndependently
        self.imageView.imageAlignment = .alignCenter
        super.init(frame: .zero)
        self.imageView.autoresizingMask = [.width, .height]
        self.imageView.frame = bounds
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        if let image = imageView.image {
            imageView.frame = coverRect(for: image, in: bounds.size)
        } else {
            imageView.frame = bounds
        }
    }
}

/// NSView that renders an NSImage with a circular grow mask using CAShapeLayer.
/// This ensures consistent rendering between GUI and CLI contexts.
final class MaskedImageView: NSView {
    let imageView: NSImageView
    private var targetRadius: CGFloat = 0

    init(image: NSImage?) {
        self.imageView = NSImageView()
        self.imageView.image = image
        self.imageView.imageScaling = .scaleAxesIndependently
        self.imageView.imageAlignment = .alignCenter
        super.init(frame: .zero)
        self.imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        if let image = imageView.image {
            imageView.frame = coverRect(for: image, in: bounds.size)
        } else {
            imageView.frame = bounds
        }
        updateMask()
    }

    private func updateMask() {
        guard bounds.width > 0 && bounds.height > 0 else { return }
        imageView.wantsLayer = true
        imageView.layer?.mask = nil

        let maskLayer = CAShapeLayer()
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let diameter = targetRadius * 2
        maskLayer.path = CGPath(
            ellipseIn: CGRect(x: center.x - targetRadius, y: center.y - targetRadius, width: diameter, height: diameter),
            transform: nil
        )
        imageView.layer?.mask = maskLayer
    }

    func setRadius(_ radius: CGFloat) {
        targetRadius = radius
        // Defer to next runloop to ensure layout has been applied
        DispatchQueue.main.async { [weak self] in
            self?.updateMask()
        }
    }
}

/// SwiftUI wrapper for an NSImageLayerView (unmasked).
struct WallpaperImageView: NSViewRepresentable {
    let image: NSImage?

    func makeNSView(context: Context) -> NSImageLayerView {
        NSImageLayerView(image: image)
    }

    func updateNSView(_ nsView: NSImageLayerView, context: Context) {
    }
}

/// SwiftUI wrapper for a masked NSImageLayerView for the grow effect.
struct MaskedImageViewWrapper: NSViewRepresentable {
    let image: NSImage?
    let radius: CGFloat

    func makeNSView(context: Context) -> MaskedImageView {
        MaskedImageView(image: image)
    }

    func updateNSView(_ nsView: MaskedImageView, context: Context) {
        nsView.setRadius(radius)
    }
}

/// SwiftUI view that composites the old and new wallpaper images according to
/// the selected transition effect, driven by a `progress` value (0 -> 1).
/// Renders deterministically into the given `screenSize` so GUI and CLI
/// produce identical pixels (no GeometryReader fallback).
struct TransitionImageView: View {
    @ObservedObject var progress: ProgressObject
    let oldImage: NSImage?
    let newImage: NSImage?
    let effect: TransitionType
    let screenSize: CGSize

    private var eased: Double {
        // Simple ease-in-out (swww uses Bezier curves; this is sufficient here).
        let t = min(max(progress.value, 0), 1)
        return t * t * (3 - 2 * t)
    }

    var body: some View {
        let size = screenSize
        ZStack {
            if let oldImage {
                WallpaperImageView(image: oldImage)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }

            switch effect {
            case .fade:
                fadeLayer(size: size)
            case .wipe:
                wipeLayer(size: size)
            case .grow:
                growLayer(size: size)
            case .random:
                fadeLayer(size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func fadeLayer(size: CGSize) -> some View {
        if let newImage {
            WallpaperImageView(image: newImage)
                .frame(width: size.width, height: size.height)
                .clipped()
                .opacity(eased)
        }
    }

    @ViewBuilder
    private func wipeLayer(size: CGSize) -> some View {
        let width = size.width * eased
        if let newImage {
            WallpaperImageView(image: newImage)
                .frame(width: size.width, height: size.height)
                .clipped()
                .clipShape(Rectangle())
                .offset(x: -size.width + width, y: 0)
        }
    }

    @ViewBuilder
    private func growLayer(size: CGSize) -> some View {
        let radius = eased * size.diagonal / 2
        if let newImage {
            MaskedImageViewWrapper(image: newImage, radius: radius)
                .frame(width: size.width, height: size.height)
        }
    }
}

/// NSView that renders two NSImages with a grow transition effect.
/// Uses AppKit drawing directly to ensure consistent rendering in both
/// GUI (full SwiftUI app) and CLI (minimal AppKit context) modes.
final class GrowTransitionView: NSView {
    let oldImage: NSImage?
    let newImage: NSImage?
    private var currentRadius: CGFloat = 0

    init(oldImage: NSImage?, newImage: NSImage?) {
        self.oldImage = oldImage
        self.newImage = newImage
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.set()
        dirtyRect.fill()

        // Draw old image as background (full screen)
        if let oldImg = oldImage {
            let cgOld = oldImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
            guard let cgOld = cgOld else { return }
            let imgSize = oldImg.size
            guard imgSize.width > 0, imgSize.height > 0 else { return }
            let scale = max(bounds.width / imgSize.width, bounds.height / imgSize.height)
            let w = imgSize.width * scale
            let h = imgSize.height * scale
            let drawRect = CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
            NSGraphicsContext.current?.cgContext.draw(cgOld, in: drawRect)
        }

        // Draw new image with growing circle mask
        guard let newImg = newImage, currentRadius > 0 else { return }
        let cgNew = newImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
        guard let cgNew = cgNew else { return }

        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)

        // Create a path that represents only the growing circle area
        let clipPath = NSBezierPath(ovalIn: CGRect(
            x: center.x - currentRadius,
            y: center.y - currentRadius,
            width: currentRadius * 2,
            height: currentRadius * 2
        ))

        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            clipPath.addClip()

            let imgSize = newImg.size
            guard imgSize.width > 0, imgSize.height > 0 else {
                context.restoreGState()
                return
            }

            // Scale to fill screen (aspect-fill)
            let scale = max(bounds.width / imgSize.width, bounds.height / imgSize.height)
            let w = imgSize.width * scale
            let h = imgSize.height * scale
            let drawRect = CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)

            context.draw(cgNew, in: drawRect)
            context.restoreGState()
        }
    }

    func setProgress(_ progress: Double) {
        let t = min(max(progress, 0), 1)
        let eased = t * t * (3 - 2 * t)
        currentRadius = eased * bounds.size.diagonal / 2
        setNeedsDisplay(bounds)
    }
}

private extension CGSize {
    var diagonal: CGFloat {
        sqrt(width * width + height * height)
    }
}