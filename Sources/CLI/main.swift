import Foundation
import AppKit
import UniformTypeIdentifiers
import PywalPick

@MainActor
func main() {
    let args = CommandLine.arguments.dropFirst()

    guard !args.isEmpty else {
        printUsage()
        exit(0)
    }

    let command = args.first!.lowercased()
    let remainingArgs = Array(args.dropFirst())

    // Parse global options
    var backend: WalBackend?
    var dryRun = false
    var noPywalfox = false
    var playTransition = false
    var transitionType: TransitionType?
    var filteredArgs: [String] = []

    var i = 0
    while i < remainingArgs.count {
        let arg = remainingArgs[i]
        if arg == "--backend", i + 1 < remainingArgs.count {
            i += 1
            if let b = WalBackend(rawValue: remainingArgs[i]) {
                backend = b
            } else {
                print("Error: Unknown backend '\(remainingArgs[i])'")
                print("Available backends: \(WalBackend.allCases.map { $0.rawValue }.joined(separator: ", "))")
                exit(1)
            }
        } else if arg == "--no-pywalfox" {
            noPywalfox = true
        } else if arg == "--dry-run" {
            dryRun = true
        } else if arg == "--transition" {
            playTransition = true
        } else if arg == "--transition-type", i + 1 < remainingArgs.count {
            i += 1
            if let t = TransitionType(rawValue: remainingArgs[i].lowercased()) {
                transitionType = t
            } else {
                print("Error: Unknown transition type '\(remainingArgs[i])'")
                print("Available types: \(TransitionType.allCases.map { $0.rawValue }.joined(separator: ", "))")
                exit(1)
            }
        } else {
            filteredArgs.append(arg)
        }
        i += 1
    }

    switch command {
    case "random":
        cmdRandom(backend: backend, dryRun: dryRun, noPywalfox: noPywalfox, playTransition: playTransition, transitionType: transitionType)
    case "update":
        cmdUpdate(backend: backend, dryRun: dryRun, noPywalfox: noPywalfox, playTransition: playTransition, transitionType: transitionType)
    case "set":
        guard let path = filteredArgs.first else {
            print("Error: 'set' requires a file path argument")
            print("Usage: wallpick set <path>")
            exit(1)
        }
        cmdSet(path: path, backend: backend, dryRun: dryRun, noPywalfox: noPywalfox, playTransition: playTransition, transitionType: transitionType)
    case "list":
        cmdList(query: filteredArgs.isEmpty ? nil : filteredArgs.joined(separator: " "))
    case "current":
        cmdCurrent()
    case "help", "--help", "-h":
        printUsage()
    default:
        print("Error: Unknown command '\(command)'")
        printUsage()
        exit(1)
    }
}

// MARK: - Usage

func printUsage() {
    print("""
    Usage: wallpick <command> [options]

    Commands:
      random              Set a random wallpaper and update colors
      update              Re-run wal on the current wallpaper (update colors only)
      set <path>          Set wallpaper by file path
      list [query]        List wallpapers (optionally filtered by query)
      current             Show the current wallpaper path
      help                Show this help message

    Options:
      --backend <name>    Override the wal backend (haishoku, schemer2, colorthief, etc.)
      --no-pywalfox       Skip pywalfox update
      --dry-run           Print what would happen without executing
      --transition        Play animated transition overlay (type: random by default)
      --transition-type <type>
                          Transition effect: fade | wipe | grow | random
                          (overrides the saved setting; default when --transition
                          is used without this flag is random)

    Examples:
      wallpick random
      wallpick random --backend fast_colorthief
      wallpick random --transition
      wallpick random --transition --transition-type grow
      wallpick update --transition --transition-type wipe
      wallpick set /path/to/wallpaper.jpg --transition --transition-type fade
      wallpick update
      wallpick set /path/to/wallpaper.jpg
      wallpick list sunset
      wallpick current
    """)
}

// MARK: - Wallpaper Discovery

func discoverWallpapers() -> [ImageFile] {
    let config = AppConfig.load()
    guard !config.wallpaperFolderPath.isEmpty else {
        fatalError("Error: No wallpaper folder configured. Run the GUI app and set it in Settings.")
    }

    let folderURL = URL(fileURLWithPath: config.wallpaperFolderPath)
    guard FileManager.default.fileExists(atPath: folderURL.path) else {
        fatalError("Error: Wallpaper folder does not exist at: \(config.wallpaperFolderPath)")
    }

    let supportedTypes: Set<UTType> = [.jpeg, .png, .gif, .bmp, .tiff, .webP]

    let enumerator = FileManager.default.enumerator(
        at: folderURL,
        includingPropertiesForKeys: [.contentTypeKey, .contentModificationDateKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
    )

    var imageFiles: [ImageFile] = []
    while let fileURL = enumerator?.nextObject() as? URL {
        guard
            let fileType = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType,
            supportedTypes.contains(fileType)
        else {
            continue
        }
        imageFiles.append(ImageFile(url: fileURL))
    }

    return imageFiles.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
}

// MARK: - Wal Execution

func findWalBinary() -> String {
    let config = AppConfig.load()
    if FileManager.default.fileExists(atPath: config.walBinaryPath) {
        return config.walBinaryPath
    }

    let commonPaths = [
        "/usr/local/bin/wal",
        "/opt/homebrew/bin/wal",
        "/usr/bin/wal",
        NSHomeDirectory() + "/.local/bin/wal",
        NSHomeDirectory() + "/bin/wal",
    ]

    for path in commonPaths {
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }

    fatalError("Error: wal binary not found. Configure the path in the GUI app Settings.")
}

// The actual wal application logic - used both directly and after transition
func performWalApplication(
    walPath: String,
    dummyFile: String,
    usedBackend: WalBackend,
    noPywalfox: Bool,
    runPywalfox: Bool,
    customScript: String
) -> Bool {
    _ = runShellCommand("killall WallpaperAgent")

    let command = "\(walPath) -i \"\(dummyFile)\" -n --backend \(usedBackend.rawValue)"
    print("Running: \(command)")
    let walSuccess = runShellCommand(command)

    if walSuccess {
        Thread.sleep(forTimeInterval: 1)

        let walCachePath = NSHomeDirectory() + "/.cache/wal/colors"
        if FileManager.default.fileExists(atPath: walCachePath),
           let colorsContent = try? String(contentsOfFile: walCachePath, encoding: .utf8) {
            let colorLines = colorsContent.components(separatedBy: .newlines)
                .filter { !$0.isEmpty && $0.hasPrefix("#") }
            print("✓ Wal updated colors: \(colorLines.count) colors extracted")

            setAccentColorFromWal()

            if !noPywalfox && runPywalfox {
                print("Running pywalfox update...")
                _ = runShellCommand("pywalfox update")
            }

            if !customScript.isEmpty {
                print("Running custom script: \(customScript)")
                _ = runShellCommand(customScript)
            }
        }
    } else {
        print("✗ Wal command failed")
    }

    return walSuccess
}

@MainActor
func runWal(
    wallpaperPath: String,
    backend: WalBackend? = nil,
    dryRun: Bool = false,
    noPywalfox: Bool = false,
    playTransition: Bool = false,
    transitionType: TransitionType? = nil
) -> Bool {
    let walPath = findWalBinary()
    let config = AppConfig.load()
    let dummyFile = config.dummyWallpaperFile
    let usedBackend = backend ?? config.selectedBackend
    // CLI default: random. Explicit flag or saved setting overrides.
    let effect = transitionType ?? config.transitionType

    let sourceURL = URL(fileURLWithPath: wallpaperPath)
    if !FileManager.default.fileExists(atPath: sourceURL.path) {
        print("Error: Wallpaper file not found: \(wallpaperPath)")
        return false
    }

    let dummyURL = URL(fileURLWithPath: dummyFile)
    let dummyDir = dummyURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dummyDir, withIntermediateDirectories: true)

    // CRITICAL: Capture the old wallpaper image BEFORE overwriting the dummy
    // file. The desktop is typically configured to show dummy-file.jpg, so if
    // we copy first, currentDesktopImageURL() points at the NEW image and the
    // transition has nothing to animate from.
    let oldImageForTransition: NSImage?
    if playTransition && !dryRun {
        oldImageForTransition = resolveOldWallpaperImage(
            sourceURL: sourceURL,
            dummyURL: dummyURL,
            lastSelectedPath: config.lastSelectedWallpaperPath
        )
    } else {
        oldImageForTransition = nil
    }

    if FileManager.default.fileExists(atPath: dummyFile) {
        try? FileManager.default.removeItem(at: dummyURL)
    }

    do {
        try FileManager.default.copyItem(at: sourceURL, to: dummyURL)
    } catch {
        print("Error: Could not copy wallpaper to dummy location: \(error)")
        return false
    }

    if dryRun {
        print("[dry-run] Would execute: \(walPath) -i \"\(dummyFile)\" -n --backend \(usedBackend.rawValue)")
        return true
    }

    guard playTransition else {
        return performWalApplication(
            walPath: walPath,
            dummyFile: dummyFile,
            usedBackend: usedBackend,
            noPywalfox: noPywalfox,
            runPywalfox: config.runPywalfox,
            customScript: config.customScriptPath
        )
    }

    let resolvedEffect = effect.resolved
    print("Debug: transitionType=\(effect.rawValue), resolved=\(resolvedEffect.rawValue), duration=\(config.transitionDuration)s, fps=\(config.transitionFPS)")

    // Dual-image overlay (same idea as desktop GrowTransitionView):
    // paint OLD + NEW inside an opaque window, then reveal NEW via mask/opacity.
    // Do NOT punch holes in an opaque window — that only shows black, not the desktop.
    let newImage = loadWallpaperImage(from: sourceURL)
        ?? loadWallpaperImage(from: dummyURL)
    let oldImage = oldImageForTransition ?? newImage

    guard let oldImage, let newImage else {
        print("⚠ Transition: no image available — applying wal without overlay")
        return performWalApplication(
            walPath: walPath,
            dummyFile: dummyFile,
            usedBackend: usedBackend,
            noPywalfox: noPywalfox,
            runPywalfox: config.runPywalfox,
            customScript: config.customScriptPath
        )
    }

    print("Debug: overlay old size=\(oldImage.size), new size=\(newImage.size)")
    CLITransitionController.shared.showOverlay(oldImage: oldImage, newImage: newImage)

    // Brief pump so the windows render on screen.
    // ~200ms (~12 frames at 60fps) gives the window server time to composite
    // the overlay windows before we start wal on a background thread.
    for _ in 0..<12 {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.016))
    }

    // Run wal behind the overlays on a background thread so the main
    // thread's run loop keeps pumping — Core Animation can composite the
    // overlay windows while wal executes.
    let walBox = WalResultBox()
    let group = DispatchGroup()
    group.enter()

    DispatchQueue.global(qos: .userInitiated).async {
        let result = performWalApplication(
            walPath: walPath,
            dummyFile: dummyFile,
            usedBackend: usedBackend,
            noPywalfox: noPywalfox,
            runPywalfox: config.runPywalfox,
            customScript: config.customScriptPath
        )
        walBox.value = result
        group.leave()
    }

    // Keep the main run loop pumping while wal runs so overlay windows
    // stay composited on screen.
    while group.wait(timeout: .now()) == .timedOut {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    let walResult = walBox.value

    // Animate overlays away, revealing the new wallpaper
    CLITransitionController.shared.animateOverlays(
        type: effect,
        duration: config.transitionDuration
    ) {
        CLITransitionController.shared.closeOverlays()
        CFRunLoopStop(CFRunLoopGetMain())
    }

    // Safety timeout: if animation completion never fires (e.g. CA
    // transaction dropped), force-exit so the CLI doesn't hang forever.
    let safetyTimeout = config.transitionDuration + 3.0
    DispatchQueue.main.asyncAfter(deadline: .now() + safetyTimeout) {
        CLITransitionController.shared.closeOverlays()
        CFRunLoopStop(CFRunLoopGetMain())
    }

    // Pump the run loop until the animation completes (or safety timeout fires).
    CFRunLoopRun()
    return walResult
}

/// Resolve and load the image currently on the desktop for the transition
/// "from" frame. Must be called **before** the dummy file is overwritten.
///
/// Order of preference:
/// 1. System desktop image URL (if it is a real image file)
/// 2. Configured dummy wallpaper file (what wal/kill WallpaperAgent reloads)
/// 3. Last selected wallpaper path from config
/// 4. The new source wallpaper (weak fallback — transition will look like a no-op)
func resolveOldWallpaperImage(
    sourceURL: URL,
    dummyURL: URL,
    lastSelectedPath: String
) -> NSImage? {
    var candidates: [(String, URL)] = []

    if let desktopURL = currentDesktopImageURL() {
        candidates.append(("desktopImageURL", desktopURL))
    }
    candidates.append(("dummy", dummyURL))
    if !lastSelectedPath.isEmpty {
        candidates.append(("lastSelected", URL(fileURLWithPath: lastSelectedPath)))
    }
    candidates.append(("source", sourceURL))

    for (label, url) in candidates {
        if let image = loadWallpaperImage(from: url) {
            print("Debug: old wallpaper from \(label)=\(url.path) size=\(image.size)")
            return image
        } else {
            print("Debug: skipped \(label)=\(url.path) (missing or not an image file)")
        }
    }
    return nil
}

/// The image currently shown on the desktop, used as the "old" frame for the
/// transition overlay. Returns nil for empty paths or directories (dynamic /
/// slideshow wallpapers — `NSImage(contentsOf:)` fails on those).
func currentDesktopImageURL() -> URL? {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
    guard let url = NSWorkspace.shared.desktopImageURL(for: screen), !url.path.isEmpty else {
        return nil
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          !isDirectory.boolValue
    else {
        return nil
    }
    return url
}

func setAccentColorFromWal() {
    let walCachePath = NSHomeDirectory() + "/.cache/wal/colors"
    guard FileManager.default.fileExists(atPath: walCachePath),
          let colorsContent = try? String(contentsOfFile: walCachePath, encoding: .utf8)
    else { return }

    let colorLines = colorsContent.components(separatedBy: .newlines)
        .filter { !$0.isEmpty && $0.hasPrefix("#") }

    guard colorLines.count >= 8 else { return }

    let accentColorHex = colorLines[7].trimmingCharacters(in: .whitespacesAndNewlines)
    let colorName = mapHexToSystemColorName(accentColorHex)

    print("Setting accent color: \(accentColorHex) -> \(colorName)")
    _ = runShellCommand("defaults write -g AppleAccentColor -string '\(colorName)'")
    _ = runShellCommand("defaults write -g AppleHighlightColor -string '\(accentColorHex)'")
    _ = runShellCommand("killall Dock")
    _ = runShellCommand("killall ControlCenter")
}

func mapHexToSystemColorName(_ hexString: String) -> String {
    var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
    if hex.hasPrefix("#") { hex.removeFirst() }
    if hex.count == 3 {
        let r = hex[hex.startIndex]
        let g = hex[hex.index(after: hex.startIndex)]
        let b = hex[hex.index(hex.startIndex, offsetBy: 2)]
        hex = "\(r)\(r)\(g)\(g)\(b)\(b)"
    } else if hex.count != 6 { return "0" }

    var rgb: UInt64 = 0
    let scanner = Scanner(string: hex)
    scanner.charactersToBeSkipped = CharacterSet(charactersIn: "0x")
    scanner.scanHexInt64(&rgb)

    let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
    let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
    let blue = CGFloat(rgb & 0x0000FF) / 255.0

    let nsColor = NSColor(red: red, green: green, blue: blue, alpha: 1.0)
    guard let rgbColor = nsColor.usingColorSpace(.sRGB) else { return "0" }

    let hueDegrees = rgbColor.hueComponent * 360
    let saturation = rgbColor.saturationComponent

    if saturation < 0.3 { return "7" }
    if hueDegrees >= 330 || hueDegrees < 15 { return "3" }
    if hueDegrees >= 15 && hueDegrees < 45 { return "4" }
    if hueDegrees >= 45 && hueDegrees < 75 { return "5" }
    if hueDegrees >= 75 && hueDegrees < 165 { return "6" }
    if hueDegrees >= 165 && hueDegrees < 225 { return "0" }
    if hueDegrees >= 225 && hueDegrees < 285 { return "1" }
    if hueDegrees >= 285 && hueDegrees < 330 { return "2" }
    return "0"
}

func runShellCommand(_ command: String) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments = ["-c", command]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    var environment = ProcessInfo.processInfo.environment
    if let existingPath = environment["PATH"] {
        environment["PATH"] = existingPath + ":/usr/local/bin:/opt/homebrew/bin:~/.local/bin"
    }
    task.environment = environment

    do {
        try task.run()
        let data = try pipe.fileHandleForReading.readToEnd()
        if let output = String(data: data ?? Data(), encoding: .utf8), !output.isEmpty {
            print(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        task.waitUntilExit()
        return task.terminationStatus == 0
    } catch {
        print("Error running command: \(error)")
        return false
    }
}

func runShellCommandOutput(_ command: String) -> String? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments = ["-c", command]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = (environment["PATH"] ?? "") + ":/usr/local/bin:/opt/homebrew/bin"
    task.environment = environment

    do {
        try task.run()
        let data = try pipe.fileHandleForReading.readToEnd()
        task.waitUntilExit()
        return String(data: data ?? Data(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return nil
    }
}

// MARK: - Commands

func cmdRandom(backend: WalBackend?, dryRun: Bool, noPywalfox: Bool, playTransition: Bool = false, transitionType: TransitionType? = nil) {
    let wallpapers = discoverWallpapers()
    guard !wallpapers.isEmpty else {
        print("Error: No wallpapers found in configured folder.")
        exit(1)
    }

    let randomIndex = Int.random(in: 0..<wallpapers.count)
    let wallpaper = wallpapers[randomIndex]

    print("Selected: \(wallpaper.name)")
    let success = MainActor.assumeIsolated {
        runWal(wallpaperPath: wallpaper.url.path, backend: backend, dryRun: dryRun, noPywalfox: noPywalfox, playTransition: playTransition, transitionType: transitionType)
    }

    if success && !dryRun {
        var updatedConfig = AppConfig.load()
        updatedConfig.lastSelectedWallpaperPath = wallpaper.url.path
        updatedConfig.save()
        print("✓ Wallpaper set successfully")
    }

    exit(success ? 0 : 1)
}

func cmdUpdate(backend: WalBackend?, dryRun: Bool, noPywalfox: Bool, playTransition: Bool = false, transitionType: TransitionType? = nil) {
    let config = AppConfig.load()
    guard !config.lastSelectedWallpaperPath.isEmpty else {
        print("Error: No wallpaper has been set yet. Use 'wallpick random' or 'wallpick set <path>' first.")
        exit(1)
    }

    let path = config.lastSelectedWallpaperPath
    guard FileManager.default.fileExists(atPath: path) else {
        print("Error: Previously set wallpaper not found at: \(path)")
        exit(1)
    }

    let name = URL(fileURLWithPath: path).lastPathComponent
    print("Updating colors for: \(name)")
    let success = MainActor.assumeIsolated {
        runWal(wallpaperPath: path, backend: backend, dryRun: dryRun, noPywalfox: noPywalfox, playTransition: playTransition, transitionType: transitionType)
    }
    exit(success ? 0 : 1)
}

func cmdSet(path: String, backend: WalBackend?, dryRun: Bool, noPywalfox: Bool, playTransition: Bool = false, transitionType: TransitionType? = nil) {
    let fullPath = (path as NSString).expandingTildeInPath
    guard FileManager.default.fileExists(atPath: fullPath) else {
        print("Error: File not found: \(fullPath)")
        exit(1)
    }

    let name = URL(fileURLWithPath: fullPath).lastPathComponent
    print("Setting wallpaper: \(name)")
    let success = MainActor.assumeIsolated {
        runWal(wallpaperPath: fullPath, backend: backend, dryRun: dryRun, noPywalfox: noPywalfox, playTransition: playTransition, transitionType: transitionType)
    }

    if success && !dryRun {
        var updatedConfig = AppConfig.load()
        updatedConfig.lastSelectedWallpaperPath = fullPath
        updatedConfig.save()
        print("✓ Wallpaper set successfully")
    }

    exit(success ? 0 : 1)
}

func cmdList(query: String?) {
    let wallpapers = discoverWallpapers()

    let filtered: [ImageFile]
    if let query = query, !query.isEmpty {
        filtered = wallpapers.filter { $0.name.localizedCaseInsensitiveContains(query) }
    } else {
        filtered = wallpapers
    }

    if filtered.isEmpty {
        print("No wallpapers found" + (query != nil ? " matching '\(query!)'" : ""))
        exit(0)
    }

    for wallpaper in filtered {
        let size = formattedFileSize(wallpaper.fileSize)
        print("\(wallpaper.url.path)\t\(size)")
    }

    print("\nTotal: \(filtered.count) wallpapers")
}

func cmdCurrent() {
    let config = AppConfig.load()
    guard !config.lastSelectedWallpaperPath.isEmpty else {
        print("No wallpaper has been set yet.")
        exit(0)
    }

    let path = config.lastSelectedWallpaperPath
    let name = URL(fileURLWithPath: path).lastPathComponent

    if FileManager.default.fileExists(atPath: path) {
        print("Current wallpaper: \(name)")
        print("Path: \(path)")
    } else {
        print("Last set wallpaper (file no longer exists): \(name)")
        print("Path: \(path)")
    }
}

func formattedFileSize(_ size: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
}

/// Thread-safe box for wal result from a background queue.
private final class WalResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}

// Run
// Initialize NSApplication for AppKit window operations (required for transition overlay).
// .accessory keeps us out of the Dock while still allowing desktop-level windows.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

main()