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
        lastSelectedWallpaperPath: ""
    )

    private static let configURL = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/PywalPick/config.json")

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