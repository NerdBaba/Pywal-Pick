import Foundation

enum MatugenPaletteDocumentError: LocalizedError, Sendable {
    case invalidJSON(String)
    case invalidRoot

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let message):
            return "Matugen palette JSON is invalid: \(message)"
        case .invalidRoot:
            return "Matugen palette JSON must contain an object at the root"
        }
    }
}

struct MatugenPaletteColor: Sendable, Equatable, Identifiable {
    let id: String
    let dark: String?
    let light: String?
    let defaultValue: String?

    func value(for mode: MatugenMode) -> String? {
        switch mode {
        case .dark:
            return dark ?? defaultValue ?? light
        case .light:
            return light ?? defaultValue ?? dark
        }
    }
}

struct MatugenPaletteDocument: Sendable, Equatable {
    let mode: MatugenMode?
    let isDarkMode: Bool?
    let imagePath: String?
    let semanticColors: [String: MatugenPaletteColor]
    let base16Colors: [String: MatugenPaletteColor]
    let tonalPalettes: [String: [String: String]]

    init(data: Data) throws {
        let root: [String: Any]
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any] else {
                throw MatugenPaletteDocumentError.invalidRoot
            }
            root = dictionary
        } catch let error as MatugenPaletteDocumentError {
            throw error
        } catch {
            throw MatugenPaletteDocumentError.invalidJSON(error.localizedDescription)
        }

        let rawMode = root["mode"] as? String
        mode = rawMode.flatMap(MatugenMode.init(rawValue:))
        isDarkMode = root["is_dark_mode"] as? Bool
        imagePath = root["image"] as? String
        semanticColors = Self.parseColorMap(root["colors"] as? [String: Any] ?? [:])
        base16Colors = Self.parseColorMap(root["base16"] as? [String: Any] ?? [:])
        tonalPalettes = Self.parseTonalPalettes(root["palettes"] as? [String: Any] ?? [:])
    }

    private static func parseColorMap(_ values: [String: Any]) -> [String: MatugenPaletteColor] {
        Dictionary(uniqueKeysWithValues: values.compactMap { key, rawValue in
            guard let color = parseColor(rawValue, id: key) else { return nil }
            return (key, color)
        })
    }

    private static func parseColor(_ rawValue: Any, id: String) -> MatugenPaletteColor? {
        if let value = normalizedString(from: rawValue) {
            return MatugenPaletteColor(id: id, dark: nil, light: nil, defaultValue: value)
        }

        guard let dictionary = rawValue as? [String: Any] else { return nil }

        let direct = normalizedString(from: dictionary["color"] ?? dictionary["hex"] ?? dictionary["value"])
        let dark = normalizedString(from: dictionary["dark"])
        let light = normalizedString(from: dictionary["light"])
        let defaultValue = normalizedString(from: dictionary["default"]) ?? direct

        guard dark != nil || light != nil || defaultValue != nil else { return nil }
        return MatugenPaletteColor(
            id: id,
            dark: dark,
            light: light,
            defaultValue: defaultValue
        )
    }

    private static func parseTonalPalettes(_ values: [String: Any]) -> [String: [String: String]] {
        values.compactMapValues { rawFamily in
            guard let family = rawFamily as? [String: Any] else { return nil }
            let tones = family.compactMapValues { normalizedString(from: $0) }
            return tones.isEmpty ? nil : tones
        }
    }

    private static func normalizedString(from value: Any?) -> String? {
        if let string = value as? String {
            return normalizeColorString(string)
        }
        if let dictionary = value as? [String: Any] {
            if let color = dictionary["color"] as? String {
                return normalizeColorString(color)
            }
            if let hex = dictionary["hex"] as? String {
                return normalizeColorString(hex)
            }
            if let nestedDefault = dictionary["default"] {
                return normalizedString(from: nestedDefault)
            }
        }
        return nil
    }

    private static func normalizeColorString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6,
              digits.allSatisfy({ $0.isHexDigit })
        else {
            return trimmed
        }
        return "#" + digits.lowercased()
    }
}
