# Matugen and pywal theme synchronization

## Status

Implemented in Pywal Pick.

## Context and research

Pywal Pick currently copies the selected wallpaper to the configured dummy file,
runs `wal`, and reads `~/.cache/wal/colors` and `colors.json` for downstream
integrations. The GUI and CLI duplicate that workflow, so a new generator must
live in the shared `PywalPick` target to keep both entry points consistent.

Matugen supports image-based Material You generation, configurable light/dark
modes, scheme variants, contrast, machine-readable JSON output, and a
`--base16-backend wal` option. Its configuration can be supplied with `-c`, so
Pywal Pick can use an app-owned configuration without changing the user’s
global Matugen setup. Matugen’s official themes repository also supplies a
Pywalfox-compatible JSON mapping, while the installed pywal binary can render
its complete native template set from a scheme JSON using
`wal --theme <file> --out-dir <directory>`.

References:

- https://github.com/InioX/matugen
- https://github.com/InioX/matugen/wiki/Configuration
- https://github.com/InioX/matugen/wiki/Usage
- https://github.com/InioX/matugen-themes/blob/main/templates/pywalfox-colors.json
- https://github.com/dylanaraps/pywal

## Goals

- Add Matugen as a selectable color backend in the same backend picker and
  keyboard/cycle flow as the existing pywal backends.
- Keep pywal as the compatibility boundary: existing pywalfox integrations,
  shell scripts, terminal themes, and other consumers continue to read the
  normal `~/.cache/wal` files.
- Preserve Matugen’s full semantic palette for consumers that understand
  Material roles.
- Render the complete installed pywal theme set through pywal itself instead
  of reimplementing its template formats.
- Keep the main actor responsive and avoid duplicate generation when the same
  wallpaper and options are applied repeatedly.
- Fail safely: an unsuccessful Matugen run must not corrupt or partially
  replace the last valid pywal cache.

## Non-goals

- Do not replace or modify the user’s global Matugen configuration.
- Do not make Matugen required to run Pywal Pick.
- Do not have Matugen set the macOS wallpaper; Pywal Pick retains ownership of
  copying the dummy wallpaper and managing transitions.
- Do not migrate the existing Wallhaven, overlay, or thumbnail subsystems.

## Chosen approach

Use a Matugen-first hybrid pipeline when the user selects the `matugen`
backend. `matugen` is a member of `WalBackend.allCases`, so the existing
backend picker, CLI `--backend` override, and cycle-to-next-backend behavior
all reach this pipeline without a second mode toggle:

1. Copy the selected image to the configured dummy path, as today.
2. Run Matugen against that dummy path with an app-owned minimal config,
   `--json hex`, `--base16-backend wal`, the selected mode/scheme/contrast, and
   `--source-color-index 0` so the process never waits for an interactive color
   choice.
3. Convert Matugen’s Base16 data to a valid pywal scheme JSON.
4. Ask pywal to render that scheme into a private staging directory with
   `--out-dir`, `-n`, `-q`, and `-e`.
5. Validate required outputs, add the raw Matugen JSON and a manifest, then
   atomically replace generated files in `~/.cache/wal`.
6. Run accent-color, pywalfox, and custom-script integrations only after the
   cache publish succeeds.

If Matugen is disabled, missing, invalid, or fails, the existing pywal image
pipeline remains the fallback. A Matugen failure leaves the previous cache
untouched until the fallback starts, so downstream integrations never observe
the failed staging output.

## Architecture

### Configuration

Add backwards-compatible Codable values to `WalBackend` and `AppConfig`:

- `WalBackend.matugen`: display name `Matugen (Material You)`, placed after the
  existing pywal backends so cycling reaches it and wraps back to the first
  backend.
- `matugenBinaryPath`: default `~/.cargo/bin/matugen`, with the existing
  common-path discovery fallback.
- `matugenMode`: `dark` or `light`; default `dark`.
- `matugenSchemeType`: Matugen’s supported scheme type, default
  `scheme-tonal-spot`.
- `matugenContrast`: clamped to Matugen’s `-1...1` range, default `0`.

The existing backend picker remains the selector. The Settings Integrations
tab adds Matugen executable and palette controls below it, with a short note
that Matugen participates in backend cycling. Existing config files decode
with their current defaults because every new key is decoded with
`decodeIfPresent`.

### Shared service

Add a focused `MatugenThemeService` actor to `Sources/PywalPick`.

Its public operation accepts the source wallpaper URL, the copied input URL,
and an immutable generation configuration. It returns a
`MatugenThemeResult` containing whether generation was reused or performed,
the published cache location, and elapsed time; failures are thrown as
localized `MatugenThemeServiceError` values.

The service owns:

- binary discovery and executable validation for Matugen and pywal;
- app-owned Matugen config under
  `~/Library/Application Support/PywalPick/Matugen/`;
- staging under `~/Library/Caches/PywalPick/Matugen/`;
- file fingerprinting and manifest validation;
- process invocation with `Process` argument arrays, never shell interpolation;
- Matugen JSON decoding and pywal scheme conversion;
- pywal rendering and output validation;
- atomic per-file publication into `~/.cache/wal`.

### Matugen-to-pywal mapping

Matugen’s `--base16-backend wal` supplies the terminal palette. The scheme
converter maps standard Base16 roles into pywal’s ANSI slots, while using
Material surface roles for the lightest foreground/background pair so browser
and selection consumers retain readable contrast:

| pywal slot | Base16 role |
| --- | --- |
| color0 | base00 |
| color1 | base08 |
| color2 | base0B |
| color3 | base0A |
| color4 | base0D |
| color5 | base0E |
| color6 | base0C |
| color7 | surface_container_highest |
| color8 | base03 |
| color9 | base08 |
| color10 | base0B |
| color11 | base0A |
| color12 | base0D |
| color13 | base0E |
| color14 | base0C |
| color15 | on_background |

The pywal `special` values use Matugen’s selected-mode `surface` for
`background`, `on_surface` for `foreground`, and `primary` for `cursor`. The
generated Tilix theme receives the same Material `primary`/`on_primary` pair
for its highlight colors and explicitly enables those colors. The emitted
scheme also records the dummy wallpaper path and alpha `100`, matching
pywal’s native `colors.json` contract. The unmodified Matugen JSON is
published as `~/.cache/wal/matugen-colors.json` so all Material roles and
Base16 values remain available without lossy conversion.

### Cache publication

The staging directory must contain at least `colors`, `colors.json`, and
`colors.sh`, plus the files produced by pywal’s installed template set. Every
required file is checked for existence and non-empty content before publish.
Each final file is written with an atomic replacement operation. Existing
user-created files outside the generated output list are preserved. A
manifest records the wallpaper fingerprint and generation settings, and is
used to reuse a valid cache without starting either external process.

The fingerprint includes the canonical wallpaper path, file size,
modification date/resource identifier, the Matugen and pywal binary paths,
mode, scheme type, and contrast. A single actor instance serializes requests, which
prevents two simultaneous wallpaper selections from publishing out of order.

### GUI and CLI flow

The existing GUI and CLI apply paths call the shared service after copying the
dummy wallpaper. In Matugen mode, a successful service result replaces the
direct `wal -i` call. In pywal mode, or after a Matugen failure, the existing
direct pywal path is used. The post-processing sequence is shared in behavior:

1. verify the cache;
2. set the system accent from pywal colors;
3. optionally run `pywalfox update`;
4. optionally run the configured custom script;
5. persist the selected wallpaper.

The transition overlay remains independent and continues to run while the
background generation/application work proceeds.

## Error handling

- Missing Matugen: show/log a clear fallback message and run pywal.
- Matugen non-zero exit or malformed JSON: discard staging and run pywal.
- Pywal renderer missing or unable to render: discard staging and leave the
  prior cache intact; the caller reports failure rather than publishing a
  partial theme.
- Cache publish failure: do not run pywalfox or custom scripts; preserve the
  previous cache and report the failure.
- Cancellation: terminate the child process where possible, discard staging,
  and do not update the manifest.

## Testing and performance checks

Unit and macOS integration tests cover:

- backwards-compatible config decoding and defaults;
- Matugen JSON decoding, mode selection, and exact Base16-to-pywal mapping;
- pywal scheme JSON shape and required cache-file validation;
- fingerprint changes and cache reuse;
- deterministic cache publication using an injected process runner.

Process execution is injected behind a small protocol so these tests do not
depend on a local Matugen or pywal installation. A macOS integration check
uses the installed binaries when available and confirms that pywal produces the
standard cache file set in a temporary `--out-dir`.

Performance acceptance criteria:

- repeated application of the same wallpaper/options performs no external
  generation process;
- external generation never runs on the main actor;
- only one Matugen/pywal generation is in flight;
- staging and publication do not read image pixels in Swift or copy the full
  wallpaper more than the existing dummy-file step;
- release build and full test suite remain green.
