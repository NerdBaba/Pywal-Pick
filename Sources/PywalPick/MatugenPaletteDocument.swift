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
    let variants: [String: String]

    func value(for mode: MatugenMode) -> String? {
        value(for: mode.rawValue)
    }

    func value(for variant: String) -> String? {
        variants[variant] ?? defaultValue ?? dark ?? light
    }

    fileprivate init(id: String, variants: [String: String]) {
        self.id = id
        self.variants = variants
        self.dark = variants["dark"]
        self.light = variants["light"]
        self.defaultValue = variants["default"]
    }

}

struct MatugenPaletteDocument: Sendable, Equatable {
    let mode: MatugenMode?
    let isDarkMode: Bool?
    let imagePath: String?
    let semanticColors: [String: MatugenPaletteColor]
    let base16Colors: [String: MatugenPaletteColor]
    let tonalPalettes: [String: [String: String]]

    var availableVariants: [String] {
        let variants = semanticColors.values.flatMap(\.variants.keys)
            + base16Colors.values.flatMap(\.variants.keys)
        return Array(Set(variants)).sorted { lhs, rhs in
            let priority: [String: Int] = ["dark": 0, "light": 1, "default": 2]
            let leftPriority = priority[lhs] ?? 3
            let rightPriority = priority[rhs] ?? 3
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

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
        let groupedVariants = values.compactMap { variant, rawValue -> (String, [String: Any])? in
            guard let group = rawValue as? [String: Any],
                  !group.keys.contains(where: { ["color", "hex", "value"].contains($0) }),
                  group.values.contains(where: { normalizedString(from: $0) != nil })
            else {
                return nil
            }
            return (variant, group)
        }
        let modeKeys = Set(["dark", "light", "default"])
        let hasGroupedShape = groupedVariants.contains { variant, _ in
            modeKeys.contains(variant)
        } || groupedVariants.allSatisfy { variant, group in
            !modeKeys.contains(variant)
                && !group.keys.contains(where: { modeKeys.contains($0) })
        }
        if hasGroupedShape {
            var groupedColors: [String: [String: String]] = [:]
            for (variant, group) in groupedVariants {
                for (name, rawValue) in group {
                    guard let color = normalizedString(from: rawValue) else { continue }
                    groupedColors[name, default: [:]][variant] = color
                }
            }
            return groupedColors.reduce(into: [:]) { result, item in
                result[item.key] = MatugenPaletteColor(id: item.key, variants: item.value)
            }
        }

        return Dictionary(uniqueKeysWithValues: values.compactMap { key, rawValue in
            guard let color = parseColor(rawValue, id: key) else { return nil }
            return (key, color)
        })
    }

    private static func parseColor(_ rawValue: Any, id: String) -> MatugenPaletteColor? {
        if let value = normalizedString(from: rawValue) {
            return MatugenPaletteColor(id: id, variants: ["default": value])
        }

        guard let dictionary = rawValue as? [String: Any] else { return nil }

        var variants: [String: String] = [:]
        for key in ["color", "hex", "value"] {
            if let direct = normalizedString(from: dictionary[key]) {
                variants["default"] = direct
                break
            }
        }
        for (variant, value) in dictionary {
            guard variant != "color", variant != "hex", variant != "value",
                  let normalized = normalizedString(from: value)
            else {
                continue
            }
            variants[variant] = normalized
        }

        guard !variants.isEmpty else { return nil }
        return MatugenPaletteColor(id: id, variants: variants)
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
            for key in ["color", "hex", "value", "default"] {
                if let nestedValue = dictionary[key],
                   let normalized = normalizedString(from: nestedValue) {
                    return normalized
                }
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

struct MatugenPaletteGenerationInfo: Codable, Sendable, Equatable {
    let sourcePath: String
    let mode: MatugenMode
    let schemeType: MatugenSchemeType
    let contrast: Double
}

struct MatugenPaletteSnapshot: Sendable, Equatable {
    let document: MatugenPaletteDocument
    let generationInfo: MatugenPaletteGenerationInfo?
}

enum MatugenPaletteCacheError: LocalizedError, Sendable {
    case missingPalette(URL)
    case invalidPalette(String)
    case invalidMetadata(String)

    var errorDescription: String? {
        switch self {
        case .missingPalette(let url):
            return "No generated Matugen palette was found at \(url.path)."
        case .invalidPalette(let message):
            return "The generated Matugen palette could not be read: \(message)"
        case .invalidMetadata(let message):
            return "The generated Matugen metadata could not be read: \(message)"
        }
    }
}

enum MatugenPaletteCache {
    static let rawColorsFileName = "matugen-colors.json"
    static let manifestFileName = "pywalpick-matugen-manifest.json"
    static let defaultDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".cache/wal", isDirectory: true)

    static func load(from directory: URL = defaultDirectory) throws -> MatugenPaletteSnapshot {
        let colorsURL = directory.appendingPathComponent(rawColorsFileName)
        guard FileManager.default.fileExists(atPath: colorsURL.path) else {
            throw MatugenPaletteCacheError.missingPalette(colorsURL)
        }

        let document: MatugenPaletteDocument
        do {
            document = try MatugenPaletteDocument(data: Data(contentsOf: colorsURL))
        } catch {
            throw MatugenPaletteCacheError.invalidPalette(error.localizedDescription)
        }

        let manifestURL = directory.appendingPathComponent(manifestFileName)
        let generationInfo: MatugenPaletteGenerationInfo?
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            do {
                generationInfo = try JSONDecoder().decode(
                    MatugenPaletteGenerationInfo.self,
                    from: Data(contentsOf: manifestURL)
                )
            } catch {
                throw MatugenPaletteCacheError.invalidMetadata(error.localizedDescription)
            }
        } else {
            generationInfo = nil
        }

        return MatugenPaletteSnapshot(document: document, generationInfo: generationInfo)
    }
}
