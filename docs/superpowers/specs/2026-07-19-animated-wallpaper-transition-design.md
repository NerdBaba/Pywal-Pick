# Design: Animated Wallpaper Transition Overlay (swww-style)

Date: 2026-07-19

## Goal

When the user selects a wallpaper in PywalPick, instead of macOS instantly
hard-cutting the desktop to the new image, show a temporary full-screen overlay
window above the desktop on **all monitors** that plays an animated transition
(old wallpaper → new wallpaper), then runs `wal` underneath, and finally fades
the overlay out to reveal the already-changed desktop.

This mirrors swww's animation model (TransitionAnimator + Effect variants:
fade / wipe / grow) but adapted to macOS, where the app cannot blend pixels on
the system desktop surface directly. Instead we render the transition in a
separate borderless window layered above the desktop.

## Decisions (from brainstorming)

- Q1 Transition types: **B** — fade + wipe (directional) + grow/circle, selectable.
- Q2 Type selection: **B + C** — a Settings control AND a `random` option that
  picks among fade/wipe/grow at apply time.
- Q3 Overlay coverage: **A** — cover all screens (every monitor).
- Q4 Timing: **B** — configurable duration + fps in Settings, defaults ~1.0s / 60fps.
- Q5 Sequencing: **A** — overlay-first. Play the transition, THEN run `wal`
  inside the overlay's completion closure, so the desktop already matches when
  the overlay fades out.
- Q6 Old frame source: **A** — use `config.lastSelectedWallpaperPath` (the
  previously selected wallpaper file) as the "old" image.

## Section 1 — Architecture & Components

### New type: `TransitionOverlayController`
- Plain `NSObject`-based controller, `@unchecked Sendable` (consistent with the
  existing cache singletons). Single shared instance.
- Owns the transition windows (one per `NSScreen`).

#### `play(oldURL:newURL:type:duration:fps:completion:)`
1. Resolve old image (from `oldURL`) and new image (from `newURL`) via
   `NSImage(contentsOf:)` (may reuse `OptimizedImageCache` if convenient).
2. For each `NSScreen`:
   - Create a borderless, transparent `NSWindow`.
   - `styleMask = .borderless`, `isOpaque = false`, `backgroundColor = .clear`.
   - `level = .screenSaver` (above desktop, below nothing user-facing).
   - `collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]`.
   - Frame = `screen.frame`; `isReleasedWhenClosed = false`.
   - Content = SwiftUI `TransitionImageView` hosting old image (new image
     composited per effect via `progress`).
   - `orderFrontRegardless()`.
3. Animate `progress` 0→1 over `duration` at `fps`, applying the chosen effect.
4. On completion: invoke `completion` (runs `wal` etc.), then fade windows to
   opacity 0 and `close()` them.

### Hook point: `WallpaperSwitcherView.setWallpaper(_:backend:)`
- Refactored so the existing `wal` execution block (copy to dummy file, kill
  `WallpaperAgent`, run `wal`, set accent color, pywalfox, custom script, update
  `lastSelectedWallpaperPath`) runs **inside** the overlay's completion closure.
- The unreachable top-level `catch` (noted in AGENTS.md) is removed as part of
  this refactor.

### Config additions (`AppConfig`)
- `transitionType: TransitionType` — default `.fade`.
- `transitionDuration: Double` — default `1.0` (seconds).
- `transitionFPS: Int` — default `60`.

### New enum: `TransitionType` (Codable, Sendable)
Cases: `fade`, `wipe`, `grow`, `random`.
- `displayName` for UI (Fade / Wipe / Grow / Random).
- Helper to resolve `.random` → one of `fade`/`wipe`/`grow` at apply time.

### Settings UI (`SettingsView`)
Add a "Wallpaper Transition" group to the **Appearance** tab:
- Segmented `Picker` bound to `config.transitionType` (Fade/Wipe/Grow/Random).
- `Stepper` for `transitionDuration` (range 0.2–3.0).
- `Stepper` for `transitionFPS` (range 10–120).
Mutations autosave via `SettingsManager`.

## Section 2 — Transition effects

Two layered `Image` views (old underneath, new on top), `scaledToFill`,
controlled by `progress: CGFloat` (0→1) advanced by a timer at `transitionFPS`.

- **fade** — new image `opacity = eased(progress)`. (swww `simple`/`fade`.)
- **wipe** — new image clipped by a `Rectangle` offset = `progress × size`
  along a fixed default direction (left→right). (swww `wipe`.) Default direction
  `left`; adding a configurable direction is out of scope (YAGNI).
- **grow** — new image clipped by a `Circle` mask, radius = `progress ×
  diagonal`, centered on screen center. (swww `grow`/`center`.)
- **random** — at apply time pick uniformly among fade/wipe/grow, then run it.

### Timing driver
- A main-thread timer (e.g. `TimelineView(.animation)` or `CADisplayLink` /
  dispatch source) advances `progress` in steps of `1/(duration × fps)` per
  frame.
- Easing: simple ease-in-out applied to `progress` for fade/grow (swww uses
  Bezier; ease-in-out is sufficient without pulling in a Bezier dependency).

### Resolution
- Load both images at screen resolution; `scaledToFill` to cover each screen.

## Section 3 — Data flow, error handling, testing

### Data flow (`setWallpaper` refactor)
1. `oldURL` = `URL(fileURLWithPath: config.lastSelectedWallpaperPath)`
   (fallback to `newURL` if empty). `newURL` = selected wallpaper url.
2. Resolve effective type: if `config.transitionType == .random`, pick random
   among fade/wipe/grow.
3. `TransitionOverlayController.shared.play(oldURL:newURL:type:duration:fps:) {`
   → run existing `wal` + accent-color + pywalfox + custom-script logic inside
   closure. After `wal` success, closure returns; controller fades windows out
   and closes.
4. `config.lastSelectedWallpaperPath` still updated on success (as today).

### Error handling
- If `oldURL` image fails to load (deleted file), fall back to showing only the
  new image (fade from clear). No crash.
- If overlay window creation fails on a screen, skip that screen (best-effort)
  but still run `wal`.
- Remove the existing unreachable `catch` in `setWallpaper`.

### Testing
- Unit tests for `TransitionType`: Codable round-trip; `.random` resolves to a
  valid effect; duration/fps defaults sane.
- A non-UI test that `TransitionOverlayController.play` invokes its completion
  closure (using stub/dummy images; do not require real windows in CI).
- `swift build` and `swift test` must pass.
- Real visual verification stays manual (run the app, select a wallpaper,
  observe transition).

## Out of scope (YAGNI)
- Configurable wipe direction / wave / outer (swww `wave`, `outer`).
- Live desktop screen capture for the "old" frame.
- Animated wallpaper (GIF) playback after transition (swww `ImageAnimator`).
- Applying transitions from the CLI (`wallpick`) — CLI has no SwiftUI surface.

## File change summary
- `Sources/PywalPick/Types.swift` — add `TransitionType`; add config fields.
- `Sources/PywalPick/WallpaperSwitcherView.swift` — add `TransitionImageView`,
  refactor `setWallpaper`; remove unreachable catch.
- `Sources/PywalPick/TransitionOverlayController.swift` — NEW controller type.
- `Sources/PywalPick/SettingsView.swift` — add Transition group to Appearance tab.
- `Tests/ImagePickerTests/WallpaperSwitcherViewModelTests.swift` — add type/config
  tests (or new dedicated test file).
