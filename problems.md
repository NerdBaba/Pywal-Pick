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

### Root causes (fixed)

#### RC1: `ImageOverlayView` never enabled layer-backing
`ImageOverlayView` deliberately avoided `wantsLayer = true` and only called `layer?.addSublayer(imageLayer)` in `layout()`. Because no one set `wantsLayer`, `layer` stayed `nil`, the image sublayer was never attached, and the opaque black `OverlayWindow` was all that appeared.

**Fix**: Match `GrowTransitionView` — set `wantsLayer = true` in `init`, add the image sublayer immediately, use `CGImage` for `contents`, call `layoutSubtreeIfNeeded()` + `display()` + `CATransaction.flush()` after attaching the content view.

#### RC2: Dummy file overwritten before capturing the old image
`runWal` copied the *new* wallpaper onto `dummy-file.jpg` **before** resolving `currentDesktopImageURL()`. On this setup the desktop picture URL *is* the dummy file, so the "old" frame was actually the new wallpaper (or a half-written state). Combined with RC1 this looked like: instant swap, then a black ripple.

**Fix**: Load/resolve the old `NSImage` **before** deleting/copying the dummy file (`resolveOldWallpaperImage`), then pass the in-memory image into `showOverlay(oldImage:)`.

#### RC3: Directory / dynamic wallpaper URLs
`NSWorkspace.desktopImageURL` can return a directory. Reject directories; fall back through dummy → lastSelected → source.

### Files involved
- `Sources/CLI/CLITransitionController.swift` — `ImageOverlayView`, `showOverlay(oldImage:)`, `loadWallpaperImage`
- `Sources/CLI/main.swift` — `resolveOldWallpaperImage`, capture-before-copy in `runWal`

### Verified
```
wallpick random --transition --transition-type grow|fade|wipe --no-pywalfox
```
Loads old image from desktop/dummy before overwrite, completes animation, exits cleanly.
