import AppKit
import QuartzCore
import PywalPick

/// Controls full-screen overlay windows for wallpaper transitions in the CLI.
///
/// **Pattern** (from WalBridge + Mural research):
/// 1. showOverlay() — create transparent overlay windows at desktopWindow + 1,
///    showing the OLD wallpaper via CALayer.contents.
/// 2. Call wal behind the overlays (caller does this — desktop changes invisibly).
/// 3. animateOverlays() — animate the overlays away, revealing the new desktop.
///
/// This completely eliminates the black background because the overlay never
/// has a visual gap — it always shows valid wallpaper content.
final class CLITransitionController: @unchecked Sendable {
    static let shared = CLITransitionController()
    private var overlays: [(NSWindow, NSView)] = []
    private init() {}

    /// Create overlay windows on every screen showing `oldURL` wallpaper.
    /// Each overlay is a borderless window at desktopWindow + 1 whose content
    /// view uses a CALayer sublayer to display the old wallpaper image.
    ///
    /// Uses a sublayer (not `layer.contents`) matching the proven
    /// `GrowTransitionView` pattern — setting `contents` directly on a
    /// layer-backed NSView's root layer renders black on macOS.
    @MainActor
    func showOverlay(oldURL: URL) {
        closeOverlays()

        guard let oldImage = NSImage(contentsOf: oldURL) else {
            print("⚠ Transition overlay: could not load old wallpaper from \(oldURL.path)")
            return
        }

        overlays = NSScreen.screens.map { screen in
            let window = OverlayWindow(screen: screen)
            let view = ImageOverlayView(image: oldImage)
            view.frame = window.contentLayoutRect
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            window.orderFrontRegardless()
            return (window, view)
        }
    }

    /// Close and remove all overlay windows.
    @MainActor
    func closeOverlays() {
        for (window, _) in overlays {
            window.close()
        }
        overlays = []
    }

    /// Animate overlay windows away to reveal the new desktop wallpaper
    /// underneath (which should already have been set by wal).
    ///
    /// - parameter type: The concrete transition effect to use.
    /// - parameter duration: Total animation time in seconds.
    /// - parameter completion: Called on the main queue after the animation finishes.
    @MainActor
    func animateOverlays(
        type: TransitionType,
        duration: Double,
        completion: @escaping () -> Void
    ) {
        let effect = type.resolved

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

    /// Cross-fade: window alpha goes to 0 over duration.
    private func animateFade(duration: Double, completion: @escaping () -> Void) {
        guard !overlays.isEmpty else { completion(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for (window, _) in overlays {
                window.animator().alphaValue = 0
            }
        }, completionHandler: completion)
    }

    /// Wipe: a white CALayer mask slides off the content view, revealing the
    /// desktop from left to right.
    private func animateWipe(duration: Double, completion: @escaping () -> Void) {
        guard !overlays.isEmpty else { completion(); return }
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        for (_, view) in overlays {
            guard let layer = view.layer else { continue }
            let mask = CALayer()
            mask.backgroundColor = NSColor.white.cgColor
            mask.frame = layer.bounds
            layer.mask = mask

            let anim = CABasicAnimation(keyPath: "position")
            anim.fromValue = NSValue(point: mask.position)
            anim.toValue = NSValue(point: NSPoint(x: mask.position.x + layer.bounds.width, y: mask.position.y))
            anim.duration = duration
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            mask.add(anim, forKey: "wipe")
        }
        CATransaction.commit()
    }

    /// Grow / Ripple: a CAShapeLayer mask (even-odd fill) reveals the desktop
    /// through a growing circle from screen center. Outside the circle the
    /// overlay's old wallpaper is still visible; inside the circle the new
    /// desktop wallpaper (already set by wal) shows through.
    private func animateGrowRipple(duration: Double, completion: @escaping () -> Void) {
        guard !overlays.isEmpty else { completion(); return }
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        for (_, view) in overlays {
            guard let layer = view.layer else { continue }
            let bounds = layer.bounds
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let maxRadius = sqrt(bounds.width * bounds.width + bounds.height * bounds.height) / 2

            let mask = CAShapeLayer()
            mask.fillRule = .evenOdd
            mask.fillColor = NSColor.black.cgColor

            let startPath = CGMutablePath()
            startPath.addRect(bounds)
            startPath.addEllipse(in: CGRect(x: center.x, y: center.y, width: 0, height: 0))
            mask.path = startPath

            layer.mask = mask

            let endPath = CGMutablePath()
            endPath.addRect(bounds)
            endPath.addEllipse(in: CGRect(
                x: center.x - maxRadius, y: center.y - maxRadius,
                width: maxRadius * 2, height: maxRadius * 2
            ))

            let anim = CABasicAnimation(keyPath: "path")
            anim.fromValue = startPath
            anim.toValue = endPath
            anim.duration = duration
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            mask.add(anim, forKey: "grow")
        }
        CATransaction.commit()
    }
}

/// An NSView that displays a wallpaper image via a CALayer sublayer.
/// Matches the proven `GrowTransitionView` pattern: the image lives in a
/// sublayer of the view's backing layer, NOT set directly on `layer.contents`.
/// Setting `contents` on a plain NSView's root layer renders black at desktop
/// window level on macOS — sublayers bypass this bug.
private final class ImageOverlayView: NSView {
    private let imageLayer = CALayer()

    init(image: NSImage) {
        super.init(frame: .zero)
        // Do NOT set wantsLayer here — the parent (OverlayWindow.contentView)
        // handles layer-backing. We only add our sublayer to the tree.
        imageLayer.contents = image
        imageLayer.contentsGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
        // Add sublayer on first layout when backing layer is available
        if imageLayer.superlayer == nil {
            layer?.addSublayer(imageLayer)
        }
    }
}

/// Opaque borderless window at desktopWindow + 1 level, positioned above
/// the system desktop wallpaper but below desktop icons and normal windows.
/// Click-through and invisible to window cycling.
///
/// Uses isOpaque=true + backgroundColor=.black (matching Mural and DesktopOverlay)
/// rather than transparent windows — the WindowServer may skip compositing
/// transparent desktop-level windows on modern macOS.
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
