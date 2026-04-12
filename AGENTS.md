# AGENTS.md

## Project Overview

**Wallpaper Switcher** is a macOS application (SwiftUI + SPM) that helps users select wallpapers and apply them using pywal. It features a grid-based wallpaper browser with sorting, search, keyboard navigation, and integration with the pywal color scheme system.

**Platform**: macOS 14+
**Language**: Swift 6.2
**Package Manager**: Swift Package Manager (SPM)
**Dependencies**: None (standalone SPM project)

## Directory Structure

```
wal-pick/
├── Sources/
│   ├── ImagePicker/          # Main application logic
│   │   ├── EmptyFileDocument.swift
│   │   ├── OptimizedCache.swift
│   │   ├── RandomOverlayView.swift
│   │   ├── SettingsView.swift
│   │   ├── ThumbnailCache.swift
│   │   ├── Types.swift
│   │   └── WallpaperSwitcherView.swift
│   └── App/
│       └── AppMain.swift      # App entry point
├── Tests/
│   └── ImagePickerTests/
│       └── WallpaperSwitcherViewModelTests.swift
├── Resources/
│   └── Fonts/
│       ├── NunitoSans-Variable.ttf
│       └── NunitoSans.zip
├── docs/
│   ├── OverlayConstraints.md
│   └── plans/
├── build_app.sh               # Create macOS app bundle
├── test_wal.sh                # Test wal binary
├── debug_wal.sh               # Debug wal path
└── Package.swift              # SPM package definition
```

## Essential Commands

### Build
```bash
swift build                        # Debug build
swift build --configuration release # Release build
```

### Create App Bundle
```bash
./build_app.sh
# Creates: WallpaperSwitcher.app/Contents/MacOS/WallpaperSwitcher
```

### Test Wal Binary
```bash
./test_wal.sh
# Tests wal binary execution with dummy file
```

### Debug Wal Path
```bash
./debug_wal.sh
# Checks wal binary existence, permissions, and execution
```

### Run Tests
```bash
swift test
```

### Clear Build
```bash
rm -rf .build
```

## Code Organization

### Target Structure (from Package.swift)
- **ImagePicker** (target): Core logic, shared types, caching, UI components
- **App** (target): App entry point, window configuration, font registration
- **ImagePickerTests** (test target): Unit tests

### Key Components

#### Types.swift
- `ImageFile`: Represents a wallpaper with id, url, name, dateModified, fileSize
- `SortOption`: Enum for sorting (Name, Date Modified, File Size)
- `NavigationDirection`: Enum for keyboard navigation (left, right, up, down)
- `AppConfig`: Configuration with defaults, Codable persistence
- `SettingsManager`: ObservableObject managing config

#### WallpaperSwitcherView.swift
- Main UI with grid layout, search, sorting
- Keyboard navigation (arrow keys, Enter)
- Wallpaper selection and wal execution
- Random wallpaper overlay
- Shell command execution for wal/pywalfox

#### SettingsView.swift
- Configuration UI for wallpaper folder, wal path, grid columns
- Pywalfox integration toggle

#### Caches
- `ThumbnailCache`: Disk + memory cache for thumbnails (16:9 ratio)
- `OptimizedImageCache`: In-memory NSCache for images

#### Shell Execution
- `runShellCommand()`: Async shell execution with environment PATH
- Logs to Desktop/wallpaper_switcher.log

## Naming Conventions

- **Types**: PascalCase (e.g., `WallpaperSwitcherView`, `SettingsManager`)
- **Methods/Properties**: camelCase (e.g., `loadWallpapers`, `wallpaperFolderPath`)
- **Singletons**: `shared` suffix (e.g., `ThumbnailCache.shared`)
- **Managers**: `Manager` suffix (e.g., `SettingsManager`)
- **Views**: `View` suffix (e.g., `SettingsView`, `RandomOverlayView`)
- **Caches**: `Cache` suffix (e.g., `ThumbnailCache`, `OptimizedImageCache`)

## SwiftUI Patterns

### State Management
- `@StateObject` for view-level state (e.g., viewModel)
- `@ObservedObject` for external state (e.g., settingsManager)
- `@EnvironmentObject` for shared state across views
- `@Environment(\.openWindow)` for window management
- `@FocusState` for keyboard focus management

### View Modifiers
- `.background(.ultraThinMaterial)` - Glass morphism effect
- `.clipShape(RoundedRectangle(...))` - Rounded corners
- `.onKeyPress(...)` - Keyboard input handling
- `.transition(...)` - View animations

### Async/Await
- Use `async` functions for shell commands and file operations
- `Task { ... }` for background work
- `await MainActor.run { ... }` for UI updates on main thread

## Testing

### Test Structure
```swift
@MainActor
final class ViewModelTests: XCTestCase {
    func testSomething() {
        // Test code
    }
}
```

### Current Tests
- `WallpaperSwitcherViewModelTests.swift`: Tests search query behavior

### Testing Shell Commands
Tests verify wal binary execution, not UI behavior.

## Configuration Persistence

- **Location**: `~/Library/Application Support/ImagePicker/config.json`
- **Config**: `AppConfig` struct (Codable)
- **Auto-save**: `SettingsManager.config` setter triggers save
- **Load on init**: `SettingsManager` loads config in init

## Important Gotchas

### Thread Safety & Sendable
- **WARNING**: Multiple concurrent access warnings in `ThumbnailCache` (lines 1084, 1088)
  - Capturing `imageFiles` in concurrent dispatch queue
  - Consider using actor or proper synchronization
- All caches are `@unchecked Sendable` - verify thread safety
- Use `@MainActor` for UI-related code

### Unreachable Catch Block
- **WARNING**: Unreachable catch in `WallpaperSwitcherView.swift:1097`
  - `do` block doesn't throw, making catch unreachable
  - Remove or simplify error handling

### Wal Binary
- **Required**: wal binary path must be configured
- **Fallback paths**: Checks common locations if configured path missing
- **Permissions**: Must be executable (755)
- **Command format**: `wal -i <dummy-file> -n`
- **Logs**: Debug logs written to Desktop/wallpaper_switcher.log

### File Paths
- **Dummy file**: Configurable, defaults to `~/Pictures/dummy-file.jpg`
- **Thumbs cache**: `~/Library/Caches/ImagePicker/Thumbnails/`
- **App config**: `~/Library/Application Support/ImagePicker/config.json`

### Keyboard Navigation
- **Focus**: Grid is auto-focused on appear (0.1s delay)
- **Keys**: Arrow keys move selection, Enter selects
- **Command+F**: Focus search field

### Pywal Integration
- **pywalfox**: Optional Firefox theme updater (toggle in Settings)
- **Accent color**: Extracted from wal colors (index 7)
- **System reload**: Requires killing WallpaperAgent, Dock, ControlCenter

### Logging
- **Console**: `print()` statements for debugging
- **File**: `/tmp/wallswitcherlogs/app.log`
- **Debug**: Desktop/wallpaper_switcher.log (wallpaper switching process)

## Code Style

### File Organization
- One type per file (no large files with multiple types)
- Public types first, then private helpers
- Comments at top of file for module-level documentation

### Property Wrappers
- `@Published` for observable properties
- `@State` for local view state
- `@Binding` for two-way binding
- `@Environment` for dependency injection

### Async/Await Style
```swift
Task {
    do {
        // Async work
        let result = await someAsyncFunction()
        await MainActor.run {
            // UI update
            self.uiProperty = result
        }
    } catch {
        // Error handling
    }
}
```

### Shell Command Style
```swift
private func runShellCommand(_ command: String) async -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments = ["-c", command]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    // Configure environment with common paths
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = existingPath + ":/usr/local/bin:/opt/homebrew/bin"

    try? task.run()
    let output = String(data: pipe.fileHandleForReading.readToEnd() ?? Data(), encoding: .utf8)
    task.waitUntilExit()
    return task.terminationStatus == 0
}
```

## Common Patterns

### Singleton Caches
```swift
class SomeCache: @unchecked Sendable {
    static let shared = SomeCache()

    private init() {
        // Initialize
    }

    func doSomething() {
        // Thread-safe operation
    }
}
```

### Configuration Management
```swift
@MainActor
public struct AppConfig: Codable, Sendable {
    static let `default` = AppConfig(/* defaults */)
    private static let configURL = URL(fileURLWithPath: "path/to/config.json")

    @MainActor public static func load() -> AppConfig {
        // Load from file or return default
    }

    @MainActor public func save() {
        // Save to file
    }
}
```

### View with Keyboard Navigation
```swift
.onKeyPress(.leftArrow) {
    viewModel.moveSelection(direction: .left, columns: config.gridColumns)
    return .handled
}
.onKeyPress(.rightArrow) {
    viewModel.moveSelection(direction: .right, columns: config.gridColumns)
    return .handled
}
// ... etc
```

### Image Loading with Cache
```swift
.task {
    if let nsImage = await OptimizedImageCache.shared.loadThumbnail(
        for: wallpaper.url,
        size: CGSize(width: cardWidth, height: imageHeight)
    ) {
        thumbnailImage = Image(nsImage: nsImage)
    }
}
```

## Debugging

### Check Wal Installation
```bash
# Check if wal exists
ls -la /usr/local/bin/wal
ls -la /opt/homebrew/bin/wal

# Test wal
./test_wal.sh

# Check permissions
stat -f "%A" /usr/local/bin/wal
```

### View Logs
```bash
cat ~/Desktop/wallpaper_switcher.log
cat /tmp/wallswitcherlogs/app.log
```

### Check Config
```bash
cat ~/Library/Application\ Support/ImagePicker/config.json
```

### Test Build
```bash
swift build
swift test
```

## Documentation

- **OverlayConstraints.md**: Layout constraints for overlays
- **plans/**: Feature design documents (keyboard navigation)
- **README.md**: Original ImagePicker documentation (outdated)

## Notes for Future Agents

1. **Fix warnings first**: Address Sendable and unreachable catch warnings before major changes
2. **Thread safety**: Be careful with concurrent access to shared state
3. **Wal integration**: Changes to wal execution require testing on macOS
4. **Keyboard navigation**: New keyboard features need focus state management
5. **Cache cleanup**: Thumbnail cache should be cleaned periodically (call `cleanupOldCache()`)
6. **Logging**: Use both console print() and file logging for debugging
7. **Settings persistence**: Config auto-saves on change - don't forget to save explicitly
8. **UI updates**: Always use `await MainActor.run` for UI updates from background tasks
9. **App bundle**: Use `./build_app.sh` for creating distributable app, not `swift build` directly
10. **Environment**: PATH includes `.local/bin`, `/usr/local/bin`, `/opt/homebrew/bin` for wal
