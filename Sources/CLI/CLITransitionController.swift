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
    /// Each overlay is a transparent borderless window at desktopWindow + 1
    /// whose content view's CALayer displays the image via .contents.
    @MainActor
    func showOverlay(oldURL: URL) {
        closeOverlays()

        guard let oldImage = NSImage(contentsOf: oldURL) else {
            print("⚠ Transition overlay: could not load old wallpaper from \(oldURL.path)")
            return
        }

        overlays = NSScreen.screens.map { screen in
            let window = OverlayWindow(screen: screen)
            let view = NSView()
            view.wantsLayer = true
            view.layer?.contents = oldImage
            view.layer?.contentsGravity = .resizeAspectFill
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
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for (window, _) in overlays {
                window.animator().alphaValue = 0
            }
        }, completionHandler: completion)
    }

    /// Wipe: a white CALayer mask slides off the content view, revealing the
    /// desktop from right to left.
    private func animateWipe(duration: Double, completion: @escaping () -> Void) {
        for (_, view) in overlays {
            guard let layer = view.layer else { continue }
            let mask = CALayer()
            mask.backgroundColor = NSColor.white.cgColor
            mask.frame = layer.bounds
            layer.mask = mask
            CATransaction.flush()

            let anim = CABasicAnimation(keyPath: "position")
            anim.fromValue = NSValue(point: mask.position)
            anim.toValue = NSValue(point: NSPoint(x: mask.position.x + layer.bounds.width, y: mask.position.y))
            anim.duration = duration
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            mask.add(anim, forKey: "wipe")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05, execute: completion)
    }

    /// Grow / Ripple: a CAShapeLayer mask (even-odd fill) reveals the desktop
    /// through a growing circle from screen center. Outside the circle the
    /// overlay's old wallpaper is still visible; inside the circle the new
    /// desktop wallpaper (already set by wal) shows through.
    private func animateGrowRipple(duration: Double, completion: @escaping () -> Void) {
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
            CATransaction.flush()

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
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05, execute: completion)
    }
}

/// Transparent borderless window at desktopWindow + 1 level, positioned above
/// the system desktop wallpaper but below desktop icons and normal windows.
/// Click-through and invisible to window cycling.
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
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isRestorable = false
        setFrame(screen.frame, display: true)
    }
}
