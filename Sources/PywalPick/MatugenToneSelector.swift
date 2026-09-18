import Foundation

enum MatugenToneSelectionError: LocalizedError, Sendable {
    case noReadableTone(family: String, minimumContrast: Double)

    var errorDescription: String? {
        switch self {
        case .noReadableTone(let family, let minimumContrast):
            return "Matugen family \(family) has no color with \(minimumContrast):1 contrast against the generated background."
        }
    }
}

enum MatugenToneSelector {
    static func select(
        family: [String: String],
        familyName: String,
        targetTone: Double,
        background: ThemeColor,
        minimumContrast: Double
    ) throws -> String {
        let candidates = family.compactMap { tone, value -> (tone: Double, color: String, distance: Double)? in
            guard let toneValue = Double(tone),
                  let parsed = try? ThemeColor(hex: value),
                  parsed.contrastRatio(to: background) >= minimumContrast
            else { return nil }
            return (toneValue, parsed.hex, abs(toneValue - targetTone))
        }

        guard let selected = candidates.min(by: { left, right in
            if left.distance != right.distance { return left.distance < right.distance }
            return left.tone < right.tone
        }) else {
            throw MatugenToneSelectionError.noReadableTone(
                family: familyName,
                minimumContrast: minimumContrast
            )
        }
        return selected.color
    }
}
