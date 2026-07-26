import AppKit
import QuartzCore
import PywalPick

/// Controls full-screen overlay windows for wallpaper transitions in the CLI.
///
/// **Pattern**:
/// 1. showOverlay(old:new:) — dual-image overlay at desktopWindow + 1
///    (old full-screen, new hidden under a mask / opacity 0).
/// 2. Caller runs wal behind the overlay (desktop updates invisibly).
/// 3. animateOverlays() — reveal **new image inside the overlay** (not a
///    transparent hole). Opaque windows cannot punch through to the real
///    desktop: a mask hole only shows the window’s black background.
/// 4. Close overlay; real desktop already matches.
///
/// Critical: content views must set `wantsLayer = true` before adding image
/// sublayers. Without a backing layer the image never attaches.
final class CLITransitionController: @unchecked Sendable {
    static let shared = CLITransitionController()
    private var overlays: [(NSWindow, DualImageOverlayView)] = []
    private init() {}

    /// Create overlay windows compositing `oldImage` (full) over `newImage`
    /// (initially fully masked / invisible).
    @MainActor
    func showOverlay(oldImage: NSImage, newImage: NSImage) {
        closeOverlays()

        overlays = NSScreen.screens.map { screen in
            let window = OverlayWindow(screen: screen)
            let view = DualImageOverlayView(oldImage: oldImage, newImage: newImage)
            view.frame = window.contentLayoutRect
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            view.display()
            window.orderFrontRegardless()
            return (window, view)
        }

        CATransaction.flush()
    }

    /// Convenience when only the old image is known (fade uses window alpha).
    @MainActor
    func showOverlay(oldImage: NSImage) {
        showOverlay(oldImage: oldImage, newImage: oldImage)
    }

    @MainActor
    @discardableResult
    func showOverlay(oldURL: URL, newURL: URL? = nil) -> Bool {
        guard let oldImage = loadWallpaperImage(from: oldURL) else {
            print("⚠ Transition overlay: could not load old wallpaper from \(oldURL.path)")
            return false
        }
        let newImage = newURL.flatMap { loadWallpaperImage(from: $0) } ?? oldImage
        print("Debug: loaded old=\(oldURL.path) size=\(oldImage.size), new size=\(newImage.size)")
        showOverlay(oldImage: oldImage, newImage: newImage)
        return true
    }

    @MainActor
    func closeOverlays() {
        for (window, _) in overlays {
            window.close()
        }
        overlays = []
    }

    /// Animate the dual-image reveal, then invoke completion (caller closes windows).
    @MainActor
    func animateOverlays(
        type: TransitionType,
        duration: Double,
        completion: @escaping () -> Void
    ) {
        let effect = type.resolved

        for (_, view) in overlays {
            view.layoutSubtreeIfNeeded()
        }
        CATransaction.flush()

        switch effect {
        case .fade:
            animateFade(duration: duration, completion: completion)
        case .wipe:
            animateWipe(duration: duration, completion: completion)
        case .grow:
            animateGrowRipple(duration: duration, completion: completion)
        case .random:
            let effects: [TransitionType] = [.fade, .wipe, .grow]
            animateOverlays(type: effects.randomElement()!, duration: duration, completion: completion)
        }
    }

    // MARK: - Effect Implementations

    /// Cross-fade: new image layer opacity 0 → 1 over the old image.
    @MainActor
    private func animateFade(duration: Double, completion: @escaping () -> Void) {
        guard !overlays.isEmpty else { completion(); return }

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated { completion() }
        }
        for (_, view) in overlays {
            view.animateNewOpacity(from: 0, to: 1, duration: duration)
        }
        CATransaction.commit()
        CATransaction.flush()
    }

    /// Wipe: rectangular mask on the **new** image expands left → right,
    /// revealing new wallpaper over the old (both painted in the overlay).
    @MainActor
    private func animateWipe(duration: Double, completion: @escaping () -> Void) {
        guard !overlays.isEmpty else { completion(); return }
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated { completion() }
        }
        for (_, view) in overlays {
            view.animateWipeReveal(duration: duration)
        }
        CATransaction.commit()
        CATransaction.flush()
    }

    /// Grow / Ripple: circular mask on the **new** image expands from center
    /// (same as desktop `GrowTransitionView`). Never punches a hole in an
    /// opaque window — that only shows black.
    @MainActor
    private func animateGrowRipple(duration: Double, completion: @escaping () -> Void) {
        guard !overlays.isEmpty else { completion(); return }
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated { completion() }
        }
        for (_, view) in overlays {
            view.animateGrowReveal(duration: duration)
        }
        CATransaction.commit()
        CATransaction.flush()
    }
}

// MARK: - Image loading

func loadWallpaperImage(from url: URL) -> NSImage? {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          !isDirectory.boolValue
    else {
        return nil
    }

    if let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 {
        return image
    }

    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else {
        return nil
    }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}

private func layerContents(for image: NSImage) -> Any {
    if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        return cgImage
    }
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let cgImage = rep.cgImage {
        return cgImage
    }
    return image
}

// MARK: - Views / Windows

/// Dual-image overlay matching desktop `GrowTransitionView`:
/// - `oldImageLayer` full-screen background
/// - `newImageLayer` on top, revealed via mask / opacity
///
/// Both images live in the overlay so grow/wipe never depend on window
/// transparency (opaque desktop-level windows show black through holes).
final class DualImageOverlayView: NSView {
    private let oldImageLayer = CALayer()
    private let newImageLayer = CALayer()
    private let shapeMask = CAShapeLayer()

    init(oldImage: NSImage, newImage: NSImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        oldImageLayer.contents = layerContents(for: oldImage)
        oldImageLayer.contentsGravity = .resizeAspectFill
        oldImageLayer.contentsScale = scale

        newImageLayer.contents = layerContents(for: newImage)
        newImageLayer.contentsGravity = .resizeAspectFill
        newImageLayer.contentsScale = scale
        // Start fully hidden; each effect configures how new becomes visible.
        newImageLayer.opacity = 0

        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(oldImageLayer)
        layer?.addSublayer(newImageLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        oldImageLayer.frame = bounds
        newImageLayer.frame = bounds
        shapeMask.frame = bounds
    }

    // MARK: Animations (called after layout has non-zero bounds)

    func animateNewOpacity(from: Float, to: Float, duration: Double) {
        // Fade does not use a mask — just cross-fade new over old.
        newImageLayer.mask = nil
        newImageLayer.opacity = from

        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = from
        anim.toValue = to
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        newImageLayer.add(anim, forKey: "fade")
        newImageLayer.opacity = to
    }

    func animateWipeReveal(duration: Double) {
        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        newImageLayer.opacity = 1
        newImageLayer.mask = nil

        // Mask starts as zero-width at the left edge, expands to full width.
        let mask = CALayer()
        mask.backgroundColor = NSColor.white.cgColor
        mask.anchorPoint = CGPoint(x: 0, y: 0.5)
        mask.bounds = CGRect(x: 0, y: 0, width: 0, height: bounds.height)
        mask.position = CGPoint(x: 0, y: bounds.midY)
        newImageLayer.mask = mask

        let anim = CABasicAnimation(keyPath: "bounds.size.width")
        anim.fromValue = 0
        anim.toValue = bounds.width
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        mask.add(anim, forKey: "wipe")
        mask.bounds.size.width = bounds.width
    }

    func animateGrowReveal(duration: Double) {
        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let maxRadius = hypot(bounds.width, bounds.height) / 2

        newImageLayer.opacity = 1

        // Positive circular mask on the NEW layer (not even-odd hole on the whole view).
        shapeMask.frame = bounds
        shapeMask.fillColor = NSColor.black.cgColor
        shapeMask.fillRule = .nonZero

        let startPath = CGPath(
            ellipseIn: CGRect(x: center.x, y: center.y, width: 0, height: 0),
            transform: nil
        )
        let endPath = CGPath(
            ellipseIn: CGRect(
                x: center.x - maxRadius,
                y: center.y - maxRadius,
                width: maxRadius * 2,
                height: maxRadius * 2
            ),
            transform: nil
        )
        shapeMask.path = startPath
        newImageLayer.mask = shapeMask

        let anim = CABasicAnimation(keyPath: "path")
        anim.fromValue = startPath
        anim.toValue = endPath
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        shapeMask.add(anim, forKey: "grow")
        shapeMask.path = endPath
    }
}

/// Opaque borderless window at desktopWindow + 1.
/// Opaque + black is required for reliable compositing at desktop levels;
/// dual-image views paint both wallpapers inside the window so we never need
/// true transparency to “see through” to the system desktop.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
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
