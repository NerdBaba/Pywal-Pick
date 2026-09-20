import Foundation

/// A concrete theme option shown when a user reselects the active wallpaper.
///
/// Regular choices select a pywal extraction backend. Matugen choices select
/// the Material You scheme and use Matugen as the backend automatically.
public enum WallpaperThemeChoice: Hashable, Identifiable, Sendable {
    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case pywal
        case matugen

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .pywal: return "Pywal backends"
            case .matugen: return "Matugen styles"
            }
        }
    }

    case backend(WalBackend)
    case matugen(MatugenSchemeType)

    public var id: String {
        switch self {
        case .backend(let backend): return "backend-\(backend.rawValue)"
        case .matugen(let scheme): return "matugen-\(scheme.rawValue)"
        }
    }

    public var section: Section {
        switch self {
        case .backend: return .pywal
        case .matugen: return .matugen
        }
    }

    public var backend: WalBackend {
        switch self {
        case .backend(let backend): return backend
        case .matugen: return .matugen
        }
    }

    /// The selected Matugen scheme, or the default scheme for a regular backend.
    /// The fallback keeps this property useful for simple collection rendering.
    public var schemeType: MatugenSchemeType {
        switch self {
        case .backend: return .schemeTonalSpot
        case .matugen(let scheme): return scheme
        }
    }

    public var displayName: String {
        switch self {
        case .backend(let backend): return backend.displayName
        case .matugen(let scheme): return scheme.displayName
        }
    }

    public static var all: [Self] {
        let backends = WalBackend.allCases
            .filter { !$0.isMatugen }
            .map(Self.backend)
        let schemes = MatugenSchemeType.allCases.map(Self.matugen)
        return backends + schemes
    }

    /// Applies only the settings represented by the choice.
    public func apply(to config: inout AppConfig) {
        switch self {
        case .backend(let backend):
            config.selectedBackend = backend
        case .matugen(let scheme):
            config.selectedBackend = .matugen
            config.matugenSchemeType = scheme
        }
    }

    public var fontStyle: WallpaperThemeChoiceFontStyle {
        switch self {
        case .backend(let backend):
            switch backend {
            case .haishoku, .okthief, .colorthief:
                return .serif
            case .fastColorthief, .wal:
                return .monospaced
            case .schemer2, .colorz, .modernColorthief, .matugen:
                return .rounded
            }
        case .matugen(let scheme):
            switch scheme {
            case .schemeExpressive, .schemeFidelity, .schemeNeutral:
                return .serif
            case .schemeMonochrome:
                return .monospaced
            case .schemeContent, .schemeFruitSalad, .schemeRainbow, .schemeTonalSpot, .schemeVibrant:
                return .rounded
            }
        }
    }
}

public enum WallpaperThemeChoiceFontStyle: String, CaseIterable, Hashable, Sendable {
    case rounded
    case monospaced
    case serif
}

/// Pure keyboard navigation state for the theme-choice grid.
public struct WallpaperThemeChoiceNavigator: Sendable {
    public let choices: [WallpaperThemeChoice]
    private var index: Int

    public init(
        choices: [WallpaperThemeChoice] = WallpaperThemeChoice.all,
        selectedChoice: WallpaperThemeChoice? = nil
    ) {
        self.choices = choices
        self.index = selectedChoice.flatMap { choices.firstIndex(of: $0) } ?? 0
    }

    public var focusedChoice: WallpaperThemeChoice? {
        guard choices.indices.contains(index) else { return nil }
        return choices[index]
    }

    @discardableResult
    public mutating func move(
        _ direction: NavigationDirection,
        columns: Int = 3
    ) -> WallpaperThemeChoice? {
        guard !choices.isEmpty else { return nil }

        let columnCount = max(1, columns)
        let nextIndex: Int
        switch direction {
        case .left:
            nextIndex = max(0, index - 1)
        case .right:
            nextIndex = min(choices.count - 1, index + 1)
        case .up:
            nextIndex = max(0, index - columnCount)
        case .down:
            nextIndex = min(choices.count - 1, index + columnCount)
        }

        index = nextIndex
        return focusedChoice
    }

    public func activate() -> WallpaperThemeChoice? {
        focusedChoice
    }
}

/// Actions emitted by the native key responder embedded in the popover.
///
/// Keeping the key-code mapping independent from AppKit makes the responder
/// small and gives the picker a deterministic test surface.
public enum WallpaperThemeChoiceKeyAction: Equatable, Sendable {
    case move(NavigationDirection)
    case activate
    case dismiss

    public init?(keyCode: UInt16) {
        switch keyCode {
        case 123: self = .move(.left)
        case 124: self = .move(.right)
        case 126: self = .move(.up)
        case 125: self = .move(.down)
        case 36, 49, 76: self = .activate
        case 53: self = .dismiss
        default: return nil
        }
    }
}
