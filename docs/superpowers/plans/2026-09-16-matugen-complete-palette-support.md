# Matugen Complete Palette Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (recommended) or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Matugen JSON conversion robust across current and legacy color shapes and expose every generated Material, Base16, and tonal palette color in an in-app explorer.

**Architecture:** Introduce one sendable `MatugenPaletteDocument` parser as the source of truth for both pywal conversion and UI inspection. Keep generation read-only from the explorer: Matugen and pywal continue to run only through the existing wallpaper-application service, while the explorer loads the last atomically published palette and manifest.

**Tech Stack:** Swift 6.2, SwiftUI, Foundation JSONSerialization/Decodable, AppKit `NSPasteboard`, XCTest, Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-09-14-matugen-pywal-sync-design.md`

## Global Constraints

- macOS 14+ and Swift 6.2 remain the minimum platform/toolchain.
- The app remains dependency-free; do not add a package for color parsing or UI.
- Matugen stays optional; pywal backends and fallback behavior remain unchanged.
- The service must continue to publish only after staging validation and must preserve the previous cache on failure.
- `matugen --json hex --base16-backend wal` remains the generation command; parser compatibility must not require changing the generated format.
- All external process execution stays off the main actor and uses argument arrays.
- Existing untracked `.pi/` and `assets/` files are user-owned and must not be staged.

---

### Task 1: Add a lossless Matugen palette document model

**Files:**
- Create: `Sources/PywalPick/MatugenPaletteDocument.swift`
- Create: `Tests/ImagePickerTests/MatugenPaletteDocumentTests.swift`

**Interfaces:**
- Consumes: raw `Data` from `matugen --json` or `~/.cache/wal/matugen-colors.json`.
- Produces: `MatugenPaletteDocument(data:)`, `MatugenPaletteColor.value(for:)`, and sorted semantic/Base16/tonal collections for the converter and explorer.

- [ ] **Step 1: Write the failing parser tests.**

  Add fixtures covering these exact forms in one document: modern nested values (`{"dark":{"color":"#112233"}}`), legacy nested strings (`{"dark":"112233"}`), direct strings (`"#445566"`), and tonal palette stops (`{"10":{"color":"#..."}}`). Assert that the parser returns 50 semantic entries when given the installed-schema fixture, 16 Base16 entries, six tonal families, and both dark/light values. Assert that a stripped value becomes `#112233` for display and conversion.

- [ ] **Step 2: Run the parser tests and verify the expected RED result.**

  Run:

  ```bash
  swift test --filter MatugenPaletteDocumentTests
  ```

  Expected result: compilation fails because `MatugenPaletteDocument` and its color-value API do not exist yet.

- [ ] **Step 3: Implement the parser model.**

  Define `MatugenPaletteDocument` with these internal/publicly testable values:

  ```swift
  struct MatugenPaletteColor: Sendable, Equatable, Identifiable {
      let id: String
      let dark: String?
      let light: String?
      let defaultValue: String?

      func value(for mode: MatugenMode) -> String?
  }

  struct MatugenPaletteDocument: Sendable, Equatable {
      let mode: MatugenMode?
      let isDarkMode: Bool?
      let imagePath: String?
      let semanticColors: [String: MatugenPaletteColor]
      let base16Colors: [String: MatugenPaletteColor]
      let tonalPalettes: [String: [String: String]]

      init(data: Data) throws
  }
  ```

  Parse the top-level `colors`, `base16`, and `palettes` dictionaries with a recursive JSON value helper. A color value decoder must accept a string, `{ "color": string }`, and mode-keyed dictionaries whose leaves are either form. Normalize exactly six hex digits by adding `#`; preserve non-hex strings for display, while leaving required-value validation to the converter. Decode `mode`, `is_dark_mode`, and `image` when present, and ignore unrelated future top-level fields.

- [ ] **Step 4: Run the parser tests and verify GREEN.**

  Run the same `swift test --filter MatugenPaletteDocumentTests` command. All parser shape, mode fallback, palette count, and stripped-hex assertions must pass.

- [ ] **Step 5: Commit the isolated parser.**

  ```bash
  git add Sources/PywalPick/MatugenPaletteDocument.swift Tests/ImagePickerTests/MatugenPaletteDocumentTests.swift
  git commit -m "feat: add flexible Matugen palette parser"
  ```

### Task 2: Route pywal conversion through the complete model

**Files:**
- Modify: `Sources/PywalPick/MatugenThemeConverter.swift`
- Modify: `Tests/ImagePickerTests/MatugenThemeTests.swift`

**Interfaces:**
- Consumes: `MatugenPaletteDocument(data:)` from Task 1.
- Produces: the existing `makePywalScheme(from:wallpaperPath:mode:)`, `materialAccent(from:mode:)`, and Tilix override behavior with modern/legacy/stripped input support.

- [ ] **Step 1: Add failing conversion cases.**

  Add tests that pass legacy mode-keyed strings and stripped six-digit values into `makePywalScheme`, assert normalized `#rrggbb` output, and assert that both `.dark` and `.light` select their corresponding values. Add a test with a malformed required `primary` or `surface` value and assert `MatugenThemeError.invalidColor` rather than an invalid pywal scheme.

- [ ] **Step 2: Run the focused conversion tests and verify RED.**

  ```bash
  swift test --filter MatugenThemeTests
  ```

  Expected result: the new legacy/stripped tests fail because the current private decoder cannot decode string leaves and the current hex validator rejects stripped input.

- [ ] **Step 3: Replace the converter’s duplicate private payload decoder.**

  Decode once through `MatugenPaletteDocument`, add a converter helper that reads a named value for the requested mode, prepends `#` for six-digit values, lowercases it, and validates exactly seven characters with hexadecimal digits. Keep the existing Base16-to-pywal slot mapping and Material contrast overrides (`color7`, `color15`, cursor, and Tilix), but source all values from the shared document model. Preserve the existing error cases and error messages.

- [ ] **Step 4: Run focused conversion tests and verify GREEN.**

  ```bash
  swift test --filter MatugenThemeTests
  ```

  Confirm the modern fixture, legacy fixture, stripped fixture, light/dark fixture, malformed-value fixture, and Tilix highlight fixture all pass.

- [ ] **Step 5: Commit the conversion integration.**

  ```bash
  git add Sources/PywalPick/MatugenThemeConverter.swift Tests/ImagePickerTests/MatugenThemeTests.swift
  git commit -m "fix: support legacy and stripped Matugen colors"
  ```

### Task 3: Prove every configured Matugen variant and preserve palette metadata

**Files:**
- Modify: `Sources/PywalPick/MatugenThemeService.swift`
- Modify: `Tests/ImagePickerTests/MatugenThemeTests.swift`
- Modify: `Sources/PywalPick/MatugenPaletteDocument.swift`

**Interfaces:**
- Consumes: all `MatugenMode.allCases` and `MatugenSchemeType.allCases`.
- Produces: validated cache output and a public/readable manifest metadata value for the explorer.

- [ ] **Step 1: Add a failing variant matrix test.**

  Extend the injected-runner service test to iterate every mode and every scheme type, generate a private cache for each pair, parse the published `matugen-colors.json`, and assert 16 Base16 colors, 50 semantic colors, six tonal palette groups, valid selected-mode `surface`, `on_surface`, `primary`, and `on_primary`, and a valid 16-line pywal `colors` file. Assert the manifest’s mode, scheme type, and contrast match the request. Add an installed-binary test loop for all 18 combinations, skipped only when the configured Matugen or wal executable or wallpaper fixture is absent.

- [ ] **Step 2: Run the matrix test and verify RED where coverage is missing.**

  ```bash
  swift test --filter MatugenThemeTests
  ```

  Expected result: the new assertions fail to compile or fail on metadata access because the service currently keeps its manifest and raw-palette path private to the actor and the integration test does not exercise all combinations.

- [ ] **Step 3: Expose only the required read-only metadata and keep cache publication safe.**

  Add a small `MatugenPaletteGenerationInfo` Codable/Sendable value containing `sourcePath`, `mode`, `schemeType`, and `contrast`. Keep the existing internal manifest fingerprint fields private, but decode the public subset from the published manifest for UI use. Add a service/cache helper that loads the raw palette and metadata from the configured cache directory without running either process. Do not change the staging/publish order; parser or metadata errors must happen before `publishGeneratedCache`.

- [ ] **Step 4: Run the full Matugen suite and verify GREEN.**

  ```bash
  swift test --filter MatugenThemeTests
  ```

  Record that all injected variant cases pass and that the installed matrix either passes all 18 combinations or is explicitly skipped only for missing local binaries/fixture.

- [ ] **Step 5: Commit the variant coverage.**

  ```bash
  git add Sources/PywalPick/MatugenThemeService.swift Sources/PywalPick/MatugenPaletteDocument.swift Tests/ImagePickerTests/MatugenThemeTests.swift
  git commit -m "test: cover all Matugen modes and schemes"
  ```

### Task 4: Build the in-app Matugen color explorer

**Files:**
- Create: `Sources/PywalPick/MatugenPaletteExplorerView.swift`
- Modify: `Sources/PywalPick/SettingsView.swift`
- Modify: `Sources/App/AppMain.swift`
- Create: `Tests/ImagePickerTests/MatugenPaletteExplorerTests.swift`

**Interfaces:**
- Consumes: the read-only cache loader and `MatugenPaletteDocument` from Tasks 1 and 3.
- Produces: `MatugenPaletteExplorerView` in a `WindowGroup` with search, mode comparison, swatches, copy actions, and explicit refresh/error states.

- [ ] **Step 1: Write explorer data/grouping tests.**

  Add tests for a loaded document that assert the explorer presents exactly three sections: semantic roles, Base16, and tonal palettes; a search term such as `primary` returns matching semantic roles and the primary tonal family; an empty cache returns a missing-cache state; and a malformed cache returns a readable parse error without crashing.

- [ ] **Step 2: Run the explorer tests and verify RED.**

  ```bash
  swift test --filter MatugenPaletteExplorerTests
  ```

  Expected result: compilation fails because the explorer grouping/state model does not exist.

- [ ] **Step 3: Implement the read-only explorer.**

  Create a small `@MainActor` explorer model with `document`, `generationInfo`, `searchText`, `isLoading`, and `errorMessage`. Its `reload()` reads only the published cache files. The view must include a searchable toolbar, dark/light segmented selection, refresh button, metadata row, and scrollable sections. Each semantic/Base16 row displays the role name, dark value, light value, the currently selected swatch, and a copy button. Each tonal palette displays all sorted tone keys and values as swatches. Use AppKit `NSPasteboard.general` for copying and a local hex-to-`Color` helper that returns a neutral swatch for non-hex values. Show an explicit “Generate a Matugen theme first” empty state when no cache exists and an error state with retry when JSON is invalid.

- [ ] **Step 4: Add the app entry points.**

  Add `WindowGroup("Matugen Colors", id: "matugen-colors")` to `Sources/App/AppMain.swift`. Add an “Explore Colors” button to the Matugen section in `SettingsView` using `@Environment(\.openWindow)`, and leave it visible only when the Matugen backend is selected. Give the explorer a minimum size suitable for the three-column color rows and pass through the existing settings environment object only if needed for future path display.

- [ ] **Step 5: Run the explorer tests and verify GREEN.**

  ```bash
  swift test --filter MatugenPaletteExplorerTests
  ```

  Confirm grouping, filtering, missing-cache, malformed-cache, and document rendering tests pass.

- [ ] **Step 6: Commit the explorer.**

  ```bash
  git add Sources/PywalPick/MatugenPaletteExplorerView.swift Sources/PywalPick/SettingsView.swift Sources/App/AppMain.swift Tests/ImagePickerTests/MatugenPaletteExplorerTests.swift
  git commit -m "feat: add Matugen palette explorer"
  ```

### Task 5: Documentation and completion verification

**Files:**
- Modify: `docs/superpowers/specs/2026-09-14-matugen-pywal-sync-design.md`
- No unrelated files may be staged.

- [ ] **Step 1: Update the design spec with the final parser and explorer contracts.**

  Document modern/legacy/stripped input support, the three explorer sections, the read-only refresh behavior, and the 18-combination verification matrix. Keep the existing pywal mapping and fallback guarantees unchanged.

- [ ] **Step 2: Run all verification commands.**

  ```bash
  swift test
  swift build --configuration release
  git diff --check
  git status --short
  ```

  Require 0 test failures, a successful release build, no whitespace errors, and only the intended tracked files changed. Verify the installed integration test output explicitly reports both modes and all nine configured schemes.

- [ ] **Step 3: Review the final diff and commit the documentation.**

  ```bash
  git diff --stat HEAD~4..HEAD
  git add -f docs/superpowers/specs/2026-09-14-matugen-pywal-sync-design.md docs/superpowers/plans/2026-09-16-matugen-complete-palette-support.md
  git commit -m "docs: specify complete Matugen palette support"
  ```

  Confirm `.pi/`, `assets/AppIcon.icns`, and `assets/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png` remain untracked and unstaged.

