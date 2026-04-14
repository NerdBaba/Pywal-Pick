import AppKit

/// Color group categories for hue-based grouping.
public enum ColorGroup: String, CaseIterable, Sendable {
    case all = "All"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case cyan = "Cyan"
    case blue = "Blue"
    case purple = "Purple"
    case pink = "Pink"
    case gray = "Gray"
    case black = "Black"
    case white = "White"

    /// Display order for the filter bar (excluding "all").
    static let displayOrder: [ColorGroup] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .gray, .black, .white
    ]

    /// Representative NSColor for each group (used in swatch display).
    var representativeColor: NSColor {
        switch self {
        case .all: return .systemGray
        case .red: return NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
        case .orange: return NSColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1)
        case .yellow: return NSColor(red: 1.0, green: 0.9, blue: 0.1, alpha: 1)
        case .green: return NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1)
        case .cyan: return NSColor(red: 0.1, green: 0.85, blue: 0.85, alpha: 1)
        case .blue: return NSColor(red: 0.2, green: 0.4, blue: 0.95, alpha: 1)
        case .purple: return NSColor(red: 0.6, green: 0.2, blue: 0.9, alpha: 1)
        case .pink: return NSColor(red: 0.95, green: 0.3, blue: 0.6, alpha: 1)
        case .gray: return NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        case .black: return NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        case .white: return NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)
        }
    }
}

extension NSColor {
    /// Hue value in range 0...1. Returns 0 if color cannot be converted to HSB.
    var hue: CGFloat {
        guard let rgb = usingColorSpace(.sRGB) else { return 0 }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return h
    }

    /// Saturation value in range 0...1.
    var saturationValue: CGFloat {
        guard let rgb = usingColorSpace(.sRGB) else { return 0 }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return s
    }

    /// Maps a dominant color to a ColorGroup based on hue, saturation, and brightness.
    var colorGroup: ColorGroup {
        guard let rgb = usingColorSpace(.sRGB) else { return .gray }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        if b < 0.2 { return .black }
        if b > 0.85 { return .white }

        if s < 0.08 { return .gray }

        let hueDegrees = h * 360
        switch hueDegrees {
        case 0..<20, 340..<360: return .red
        case 20..<45: return .orange
        case 45..<70: return .yellow
        case 70..<150: return .green
        case 150..<200: return .cyan
        case 200..<270: return .blue
        case 270..<310: return .purple
        case 310..<340: return .pink
        default: return .gray
        }
    }
}
