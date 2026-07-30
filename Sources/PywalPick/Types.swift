import Foundation

public struct ImageFile: Identifiable, Comparable, Sendable {
    public let id = UUID()
    public let url: URL
    public let name: String
    public let dateModified: Date
    public let fileSize: Int64

    public init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        self.dateModified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
        self.fileSize = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    public static func < (lhs: ImageFile, rhs: ImageFile) -> Bool {
        lhs.name < rhs.name
    }
}

public enum SortOption: String, Codable, CaseIterable, Sendable {
    case name = "Name"
    case dateModified = "Date Modified"
    case size = "File Size"
}

public enum WalBackend: String, CaseIterable, Identifiable, Codable, Sendable {
    case haishoku
    case fastColorthief = "fast_colorthief"
    case schemer2
    case colorz
    case modernColorthief = "modern_colorthief"
    case wal
    case okthief
    case colorthief

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .haishoku: return "Haishoku"
        case .fastColorthief: return "Fast ColorThief"
        case .schemer2: return "Schemer2"
        case .colorz: return "Colorz"
        case .modernColorthief: return "Modern ColorThief"
        case .wal: return "Wal"
        case .okthief: return "OKThief"
        case .colorthief: return "ColorThief"
        }
    }
}

public enum NavigationDirection: Sendable {
    case left, right, up, down
}

public enum ViewMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case grid
    case carousel
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .carousel: return "film"
        }
    }
}

/// Type of animated transition played in the desktop overlay when a wallpaper
/// is applied. `random` resolves to one of the concrete effects at apply time.
public enum TransitionType: String, CaseIterable, Codable, Identifiable, Sendable {
    case fade
    case wipe
    case grow
    case random

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fade: return "Fade"
        case .wipe: return "Wipe"
        case .grow: return "Grow"
        case .random: return "Random"
        }
    }

    /// Concrete effect to render, resolving `random` to a uniform pick.
    public var resolved: TransitionType {
        if self == .random {
            let concrete: [TransitionType] = [.fade, .wipe, .grow]
            return concrete.randomElement() ?? .fade
        }
        return self
    }
}

public struct AppConfig: Codable, Sendable {
    public var wallpaperFolderPath: String
    public var dummyWallpaperFile: String
    public var walBinaryPath: String
    public var defaultSortOption: SortOption
    public var defaultSortOrder: Bool
    public var gridColumns: Int
    public var runPywalfox: Bool
    public var customScriptPath: String
    public var viewMode: ViewMode
    public var selectedBackend: WalBackend
    public var lastSelectedWallpaperPath: String
    public var transitionType: TransitionType
    public var transitionDuration: Double
    public var transitionFPS: Int
    public var showWallpaperNames: Bool

    public static let `default` = AppConfig(
        wallpaperFolderPath: "",
        dummyWallpaperFile: NSHomeDirectory() + "/Pictures/dummy-file.jpg",
        walBinaryPath: "/Volumes/NightSky/babaisalive/.local/bin/wal",
        defaultSortOption: .name,
        defaultSortOrder: true,
        gridColumns: 4,
        runPywalfox: false,
        customScriptPath: "",
        viewMode: .grid,
        selectedBackend: .schemer2,
        lastSelectedWallpaperPath: "",
        transitionType: .fade,
        transitionDuration: 1.0,
        transitionFPS: 60,
        showWallpaperNames: true
    )

    private static let configURL = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/PywalPick/config.json")

    public init(
        wallpaperFolderPath: String,
        dummyWallpaperFile: String,
        walBinaryPath: String,
        defaultSortOption: SortOption,
        defaultSortOrder: Bool,
        gridColumns: Int,
        runPywalfox: Bool,
        customScriptPath: String,
        viewMode: ViewMode,
        selectedBackend: WalBackend,
        lastSelectedWallpaperPath: String,
        transitionType: TransitionType,
        transitionDuration: Double,
        transitionFPS: Int,
        showWallpaperNames: Bool
    ) {
        self.wallpaperFolderPath = wallpaperFolderPath
        self.dummyWallpaperFile = dummyWallpaperFile
        self.walBinaryPath = walBinaryPath
        self.defaultSortOption = defaultSortOption
        self.defaultSortOrder = defaultSortOrder
        self.gridColumns = gridColumns
        self.runPywalfox = runPywalfox
        self.customScriptPath = customScriptPath
        self.viewMode = viewMode
        self.selectedBackend = selectedBackend
        self.lastSelectedWallpaperPath = lastSelectedWallpaperPath
        self.transitionType = transitionType
        self.transitionDuration = transitionDuration
        self.transitionFPS = transitionFPS
        self.showWallpaperNames = showWallpaperNames
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        wallpaperFolderPath = try c.decodeIfPresent(String.self, forKey: .wallpaperFolderPath) ?? d.wallpaperFolderPath
        dummyWallpaperFile = try c.decodeIfPresent(String.self, forKey: .dummyWallpaperFile) ?? d.dummyWallpaperFile
        walBinaryPath = try c.decodeIfPresent(String.self, forKey: .walBinaryPath) ?? d.walBinaryPath
        defaultSortOption = try c.decodeIfPresent(SortOption.self, forKey: .defaultSortOption) ?? d.defaultSortOption
        defaultSortOrder = try c.decodeIfPresent(Bool.self, forKey: .defaultSortOrder) ?? d.defaultSortOrder
        gridColumns = try c.decodeIfPresent(Int.self, forKey: .gridColumns) ?? d.gridColumns
        runPywalfox = try c.decodeIfPresent(Bool.self, forKey: .runPywalfox) ?? d.runPywalfox
        customScriptPath = try c.decodeIfPresent(String.self, forKey: .customScriptPath) ?? d.customScriptPath
        viewMode = try c.decodeIfPresent(ViewMode.self, forKey: .viewMode) ?? d.viewMode
        selectedBackend = try c.decodeIfPresent(WalBackend.self, forKey: .selectedBackend) ?? d.selectedBackend
        lastSelectedWallpaperPath = try c.decodeIfPresent(String.self, forKey: .lastSelectedWallpaperPath) ?? d.lastSelectedWallpaperPath
        transitionType = try c.decodeIfPresent(TransitionType.self, forKey: .transitionType) ?? d.transitionType
        transitionDuration = try c.decodeIfPresent(Double.self, forKey: .transitionDuration) ?? d.transitionDuration
        transitionFPS = try c.decodeIfPresent(Int.self, forKey: .transitionFPS) ?? d.transitionFPS
        showWallpaperNames = try c.decodeIfPresent(Bool.self, forKey: .showWallpaperNames) ?? true
    }

    public static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return `default`
        }
        return config
    }

    public func save() {
        do {
            let configDir = AppConfig.configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

            let dataToWrite = try JSONEncoder().encode(self)
            try dataToWrite.write(to: AppConfig.configURL)
        } catch {
            print("Failed to save config: \(error)")
        }
    }
}

@MainActor
public class SettingsManager: ObservableObject {
    @Published public var config: AppConfig {
        didSet {
            config.save()
        }
    }

    public init() {
        self.config = AppConfig.load()
    }

    func updateWallpaperFolderPath(_ path: String) {
        config.wallpaperFolderPath = path
    }

    func updateDummyWallpaperFile(_ path: String) {
        config.dummyWallpaperFile = path
    }

    func updateWalBinaryPath(_ path: String) {
        config.walBinaryPath = path
    }

    func updateDefaultSortOption(_ option: SortOption) {
        config.defaultSortOption = option
    }

    func updateDefaultSortOrder(_ ascending: Bool) {
        config.defaultSortOrder = ascending
    }
    
    func updateGridColumns(_ columns: Int) {
        config.gridColumns = columns
    }
    
    func updateViewMode(_ mode: ViewMode) {
        config.viewMode = mode
    }
}