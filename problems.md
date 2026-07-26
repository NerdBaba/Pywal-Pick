# Problems

## CLI transition overlay frames never reach the window server

### Symptom
`wallpick random --transition --transition-type <fade|wipe|grow>` produces correct tick output (all frames log at 20/40/60 progress) but shows no visible animation on screen — just a brief fade before the wallpaper changes.

### Root Cause
In a short-lived CLI process, the **Core Animation commit cycle never fires** for layer-backed views at `.desktopWindow` level. The display link that normally drives CA commits is only established for actively-composited windows in a persistent `NSApplication` event loop. Without commits:

1. `needsDisplay = true` marks the CALayer dirty, but `draw(_:)` is never called
2. The layer backing store is never updated with new frame content
3. No layer commit reaches the window server
4. The window server composites the initial frame (empty/clear) for the entire animation duration

In the desktop (GUI) app, `NSHostingView` + SwiftUI hooks into the CA observer callback, which fires during natural CA commits driven by the persistent `NSApp.run()` event loop. The CLI process exits before any such cycle stabilises.

### Fix
Force **synchronous display** + **explicit CA flush** in every tick:

```swift
for (_, view) in windows {
    view.display()       // forces draw(_:) synchronously via .onSetNeedsDisplay policy
}
CATransaction.flush()    // pushes updated layer backing store to window server immediately
```

`view.display()` bypasses the deferred-layer-display path and calls `draw(_:)` right away (the `layerContentsRedrawPolicy = .onSetNeedsDisplay` routes the layer's display call back to the view). `CATransaction.flush()` guarantees the updated backing store reaches the window server before the tick returns.

### Files involved
- `Sources/CLI/CLITransitionController.swift` — tick function (line 57-60)
- `Sources/CLI/CLITransitionViews.swift` — `CLIFadeView`, `CLIWipeView`, `CLIGrowView` (pure AppKit `draw(_:)` views)

### History
1. Originally used the shared `TransitionOverlayController` with `TransitionImageView` (SwiftUI). `@Published` changes had deferred body recomputation; `CATransaction.flush()` committed stale state.
2. Rewrote CLI with pure AppKit `draw(_:)` views (`CLITransitionController` + `CLI*View` trio, no SwiftUI). Correct drawing logic, but frames still invisible.
3. Added `view.display()` + `CATransaction.flush()` — forces synchronous render-and-commit per frame.

---

## CATransaction.flush() commits stale SwiftUI state

### Symptom
Using `CATransaction.flush()` inside a tick callback while driving a SwiftUI `@Published` progress property produced frames that lagged by one tick — the commit fired before SwiftUI's CA observer had recomputed the view body.

### Root Cause
`@Published` changes fire `ObservableObjectPublisher.send()`, which schedules SwiftUI body recomputation on the main actor. This recomputation is deferred and runs during the **next** CA commit via SwiftUI's CA observer hook. An explicit `CATransaction.flush()` after setting `progress.value` commits the **current** (pre-recomputation) layer state, sending stale pixels to the window server.

### Fix
Removed `CATransaction.flush()` from the tick. Replaced the blocking `DispatchSemaphore` pump loop with `CFRunLoopRun()` so natural CA commits happen at the right point in the run loop iteration (after body recomputation).

### Files involved
- `Sources/PywalPick/TransitionOverlayController.swift` — removed `CATransaction.flush()` from tick
- `Sources/CLI/main.swift` — replaced semaphore pump with `CFRunLoopRun()` + `CFRunLoopStop()`

---

## Mask layer frame is CGRect.zero

### Symptom
The grow transition's circular mask was invisible — the `CAShapeLayer` was created but had zero frame, so the ellipse path fell outside the visible area.

### Root Cause
`maskLayer.frame` was never set (defaults to `.zero`). The mask layer's path was relative to the layer's own coordinate space, and with a zero frame the circle was placed at `(center.x - radius, ...)` in the mask's zero-sized rect, producing no visible mask.

Additionally, the mask was applied to `imageView.layer` instead of `self.layer` (the view's own layer), meaning the mask clipped the wrong layer.

### Fix
```swift
maskLayer.frame = bounds          // was: unset (default .zero)
layer?.mask = maskLayer           // was: imageView.layer?.mask = maskLayer
```

### Files involved
- `Sources/PywalPick/TransitionOverlayController.swift` — `MaskedImageView.updateMask()` method

---

## NSApp.stop() doesn't work from dispatch callbacks

### Symptom
`NSApp.run()` blocked forever when `NSApp.stop(nil)` was called from a `DispatchQueue.main.asyncAfter` callback.

### Root Cause
`NSApp.stop()` sets a flag that the NSApplication event loop checks only after processing a **real NSEvent**. Dispatch queue source callbacks are not NSEvents, so the flag is never checked and the loop runs indefinitely.

### Fix
Replaced `NSApp.run()` + `NSApp.stop()` with `CFRunLoopRun()` + `CFRunLoopStop()`. The CF run loop exits immediately after the current source callback returns, regardless of whether it was triggered by an NSEvent.

### Files involved
- `Sources/CLI/main.swift` — `runWal()` function (line ~310)

---

## Wipe transition direction reversed

### Symptom
The CLI wipe transition revealed the new image from left-to-right instead of right-to-left (mismatching the desktop app).

### Root Cause
The SwiftUI version uses `.offset(x: -size.width + width)` which shifts the new image left as it slides in — the visible portion comes from the **right** edge, expanding leftward. The CLI version clipped starting from `x: 0`, revealing from the left.

### Fix
Changed the clip rect origin:
```swift
// Before (left→right):
ctx.clip(to: CGRect(x: 0, y: 0, width: clipW, height: bounds.height))

// After (right→left):
let clipX = bounds.width - clipW
ctx.clip(to: CGRect(x: clipX, y: 0, width: clipW, height: bounds.height))
```

### Files involved
- `Sources/CLI/CLITransitionViews.swift` — `CLIWipeView.draw(_:)` line ~99

---

## Double alpha on fade transition

### Symptom
The fade transition's new image had alpha squared (e.g., 0.5 → 0.25) because opacity was applied twice.

### Root Cause
`ctx.setAlpha(currentOpacity)` set the context alpha, and `newImg.draw(in:from:operation:fraction: currentOpacity)` also applied the fraction as opacity. These compounded.

### Fix
Removed `ctx.setAlpha(currentOpacity)`, using only `fraction: currentOpacity` in the draw call.

### Files involved
- `Sources/CLI/CLITransitionViews.swift` — `CLIFadeView.draw(_:)` line ~55

---

## Missing black background

### Symptom
Areas of the screen not covered by the aspect-fill image rendering showed transparency instead of black, potentially revealing the real desktop wallpaper underneath the overlay.

### Root Cause
The SwiftUI version has `.background(Color.black)` on the ZStack. The CLI `draw(_:)` views only drew the old/new images at their cover rects, leaving the rest of the view transparent.

### Fix
Added `ctx.setFillColor(NSColor.black.cgColor)` + `ctx.fill(bounds)` at the start of each `draw(_:)`.

### Files involved
- `Sources/CLI/CLITransitionViews.swift` — all three `draw(_:)` methods

---

## CLI transition overlay shows black instead of old wallpaper

### Symptom
`wallpick random --transition` shows overlay windows that are opaque black — the animation (fade/wipe/grow) IS visible as a black ripple/fade, but the old wallpaper image is never displayed. The overlay is just a black rectangle covering the screen.

### What works
- Desktop app (`TransitionOverlayController` + `GrowTransitionView`) shows old wallpaper correctly
- `GrowTransitionView` uses `CALayer.contents = oldImage` (NSImage) inside a sublayer — works
- `OverlayWindow` with `isOpaque=true, backgroundColor=.black` — animation is visible
- `orderFrontRegardless()` — window appears on screen

### What doesn't work (tried so far)
1. **Direct `layer.contents = cgImage`** (original approach) — black
2. **Sublayer approach** (`ImageOverlayView` with `CALayer` sublayer, `NSImage` directly) — still black
3. **Longer RunLoop pump** (200ms, 12 iterations) — doesn't affect image rendering
4. **`NSImage` instead of `CGImage`** — no difference

### Key differences between CLI and desktop overlay

| Factor | Desktop (works) | CLI (black) |
|--------|----------------|-------------|
| Window level | `.desktopWindow` | `.desktopWindow + 1` |
| Event loop | `NSApp.run()` | `CFRunLoopRun()` |
| Image setup | `GrowTransitionView` as contentView | `ImageOverlayView` as contentView |
| Layer approach | Sublayer with `contents = NSImage` | Sublayer with `contents = NSImage` |
| Window config | `isOpaque=true, bg=.black` | `isOpaque=true, bg=.black` |

### Hypotheses

#### H1: `currentDesktopImageURL()` returns wrong URL
`NSWorkspace.shared.desktopImageURL(for:)` may return:
- A directory URL (dynamic wallpapers/slideshow) → `NSImage(contentsOf:)` returns nil → fallback to `sourceURL` (new wallpaper) → overlay shows new image (which becomes old after wal runs, so user sees "immediate swap")
- The new wallpaper URL if called after a previous wal run
- Nil entirely → falls back to `sourceURL`

**Evidence**: User reports "wallpapers swap immediately then black ripple plays" — this could mean the overlay shows the NEW wallpaper (which is already on screen), so the "swap" appears instant.

**Fix needed**: Add more debug logging to confirm what URL is being used. Check if `NSImage(contentsOf: oldURL)` returns nil.

#### H2: Window level `desktopWindow + 1` blocks image compositing
The WindowServer may handle image content differently at `+1` vs exact `.desktopWindow` level. Desktop overlay works at exact `.desktopWindow`.

**Test**: Try changing `OverlayWindow` level to `.desktopWindow` (without +1).

#### H3: `CFRunLoopRun()` doesn't drive CA commits for image layers
The CLI uses `CFRunLoopRun()` instead of `NSApp.run()`. Core Animation may need the NSApplication event loop to composite image layers (not just animation layers).

**Evidence**: Animations (fade alpha, wipe mask, grow mask) work because they use `CABasicAnimation` which CA handles independently. But static image content may need the full NSApp compositing pipeline.

**Test**: Try adding `CATransaction.flush()` after `showOverlay()` to force immediate compositing.

#### H4: Sublayer frame is zero on first layout
`ImageOverlayView.layout()` sets `imageLayer.frame = bounds` and adds the sublayer. But `bounds` might be `.zero` at first layout if the view hasn't been sized yet.

**Test**: Add logging in `layout()` to print `bounds` size.

### Files involved
- `Sources/CLI/CLITransitionController.swift` — `showOverlay()`, `ImageOverlayView`, `OverlayWindow`
- `Sources/CLI/main.swift` — `runWal()` transition section (line 279-343), `currentDesktopImageURL()`
- `Sources/PywalPick/TransitionOverlayController.swift` — working desktop overlay (reference)

### Debug logging added
- `main.swift:280` — prints `oldURL`, `sourceURL`, and whether fallback was used
- `CLITransitionController.swift:31-33` — prints warning if `NSImage(contentsOf:)` returns nil

### Suggested next steps
1. Run `wallpick random --transition` and check console for the debug output — is `oldURL` correct? Is fallback "yes"?
2. If fallback is "yes", `currentDesktopImageURL()` is returning nil — investigate why
3. If `oldURL` is correct but image still black, try `CATransaction.flush()` after overlay creation
4. If still black, try window level `.desktopWindow` (without +1)
5. If still black, add logging in `ImageOverlayView.layout()` to confirm `bounds` and `superlayer` state
6. Consider trying `NSHostingView(rootView: WallpaperImageView(image: oldImage))` like the desktop app does for fade/wipe (bypasses all CALayer concerns)
