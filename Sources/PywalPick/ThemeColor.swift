import Foundation

enum ThemeColorError: LocalizedError, Sendable, Equatable {
    case invalidHex(String)

    var errorDescription: String? {
        switch self {
        case .invalidHex(let value):
            return "Expected a six-digit sRGB hex color, got \(value)."
        }
    }
}

struct ThemeColor: Equatable, Sendable {
    let hex: String

    init(hex: String) throws {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard digits.utf8.count == 6,
              digits.unicodeScalars.allSatisfy({
                  switch $0.value {
                  case 48...57, 65...70, 97...102: return true
                  default: return false
                  }
              })
        else {
            throw ThemeColorError.invalidHex(hex)
        }
        self.hex = "#" + digits.lowercased()
    }

    var relativeLuminance: Double {
        let values = stride(from: 1, through: 5, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            let component = Double(Int(hex[start..<end], radix: 16) ?? 0) / 255
            return component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
    }

    /// The channel spread in sRGB space. This is a compact measure of how
    /// colorful a candidate is, without introducing another color library.
    var chroma: Double {
        let components = rgbComponents
        return (components.max() ?? 0) - (components.min() ?? 0)
    }

    /// Pure-ish black and white are technically readable in many pairings but
    /// make poor ANSI accents when the Matugen family offers alternatives.
    var isNearExtreme: Bool {
        relativeLuminance <= 0.02 || relativeLuminance >= 0.98
    }

    func contrastRatio(to other: ThemeColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var rgbComponents: [Double] {
        stride(from: 1, through: 5, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return Double(Int(hex[start..<end], radix: 16) ?? 0) / 255
        }
    }
}
