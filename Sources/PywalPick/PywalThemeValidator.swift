import Foundation

enum PywalThemeValidationError: LocalizedError, Sendable {
    case invalidSchema(String)
    case unreadableColor(String, Double, Double)

    var errorDescription: String? {
        switch self {
        case .invalidSchema(let message):
            return "Generated pywal theme has an invalid schema: \(message)"
        case .unreadableColor(let name, let actual, let required):
            return "Generated pywal \(name) contrast is \(String(format: "%.3f", actual)):1; expected at least \(String(format: "%.1f", required)):1."
        }
    }
}

enum PywalThemeValidator {
    private static let slots = (0..<16).map { "color\($0)" }

    static func validate(
        directory: URL,
        expectedScheme: Data,
        enforceStandardContrast: Bool
    ) throws {
        let expected = try readTheme(from: expectedScheme, name: "scheme")
        let colorsJSONURL = directory.appendingPathComponent("colors.json")
        let actualData = try requireData(colorsJSONURL)
        let actual = try readTheme(from: actualData, name: "colors.json")

        guard actual.colors == expected.colors else {
            throw PywalThemeValidationError.invalidSchema("colors.json does not match the converted scheme")
        }
        guard actual.special == expected.special else {
            throw PywalThemeValidationError.invalidSchema("colors.json special colors do not match the converted scheme")
        }

        let colorLines = try requireText(directory.appendingPathComponent("colors"))
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.hasPrefix("#") }
        guard colorLines.count >= 16,
              Array(colorLines.prefix(16)) == slots.compactMap({ actual.colors[$0] })
        else {
            throw PywalThemeValidationError.invalidSchema("colors does not contain the canonical 16 slots")
        }

        let shell = try requireText(directory.appendingPathComponent("colors.sh"))
        for slot in slots {
            guard let expectedColor = actual.colors[slot],
                  shell.contains("\(slot)='\(expectedColor)'")
            else {
                throw PywalThemeValidationError.invalidSchema("colors.sh is missing \(slot)")
            }
        }

        guard enforceStandardContrast else { return }
        let background = try themeColor(actual.special["background"], named: "background")
        for slot in slots.dropFirst() {
            let value = try themeColor(actual.colors[slot], named: slot)
            let ratio = value.contrastRatio(to: background)
            guard ratio >= 4.5 else {
                throw PywalThemeValidationError.unreadableColor(slot, ratio, 4.5)
            }
        }

        let cursor = try themeColor(actual.special["cursor"], named: "cursor")
        let cursorRatio = cursor.contrastRatio(to: background)
        guard cursorRatio >= 3 else {
            throw PywalThemeValidationError.unreadableColor("cursor", cursorRatio, 3)
        }
        try validateGhostty(directory: directory, background: background)
        try validateTilix(directory: directory)
    }

    private struct Theme {
        let colors: [String: String]
        let special: [String: String]
    }

    private static func readTheme(from data: Data, name: String) throws -> Theme {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawColors = object["colors"] as? [String: Any],
              let rawSpecial = object["special"] as? [String: Any]
        else {
            throw PywalThemeValidationError.invalidSchema("\(name) is not a pywal JSON object")
        }
        let colors = rawColors.compactMapValues { $0 as? String }
        let special = rawSpecial.compactMapValues { $0 as? String }
        guard Set(colors.keys) == Set(slots),
              Set(special.keys) == ["background", "foreground", "cursor"]
        else {
            throw PywalThemeValidationError.invalidSchema("\(name) has incomplete color keys")
        }
        for value in Array(colors.values) + Array(special.values) {
            _ = try themeColor(value, named: name)
        }
        return Theme(colors: colors, special: special)
    }

    private static func validateGhostty(directory: URL, background: ThemeColor) throws {
        let url = directory.appendingPathComponent("colors-ghostty")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let contents = try requireText(url)
        let values = contents.split(whereSeparator: \.isNewline).reduce(into: [String: String]()) { result, line in
            let pieces = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count == 2 else { return }
            result[pieces[0]] = pieces[1]
        }
        guard let selectionBackground = values["selection-background"],
              let selectionForeground = values["selection-foreground"]
        else { return }
        let selected = try themeColor(selectionForeground, named: "Ghostty selection foreground")
        let selectedBackground = try themeColor(selectionBackground, named: "Ghostty selection background")
        guard selected.hex != values["foreground"] || selectedBackground.hex != values["background"] else {
            throw PywalThemeValidationError.invalidSchema("Ghostty selection is identical to ordinary text")
        }
        let ratio = selected.contrastRatio(to: selectedBackground)
        guard ratio >= 4.5 else {
            throw PywalThemeValidationError.unreadableColor("Ghostty selection", ratio, 4.5)
        }
        if let cursor = values["cursor-color"] {
            let cursorValue = try themeColor(cursor, named: "Ghostty cursor")
            guard cursorValue.contrastRatio(to: background) >= 3 else {
                throw PywalThemeValidationError.unreadableColor("Ghostty cursor", cursorValue.contrastRatio(to: background), 3)
            }
        }
    }

    private static func validateTilix(directory: URL) throws {
        let url = directory.appendingPathComponent("colors-tilix.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              let foreground = object["highlight-foreground-color"] as? String,
              let background = object["highlight-background-color"] as? String
        else { return }
        let ratio = try themeColor(foreground, named: "Tilix selection foreground")
            .contrastRatio(to: themeColor(background, named: "Tilix selection background"))
        guard ratio >= 4.5 else {
            throw PywalThemeValidationError.unreadableColor("Tilix selection", ratio, 4.5)
        }
    }

    private static func requireData(_ url: URL) throws -> Data {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            throw PywalThemeValidationError.invalidSchema("missing \(url.lastPathComponent)")
        }
        return data
    }

    private static func requireText(_ url: URL) throws -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            throw PywalThemeValidationError.invalidSchema("missing or invalid \(url.lastPathComponent)")
        }
        return text
    }

    private static func themeColor(_ value: String?, named name: String) throws -> ThemeColor {
        guard let value else {
            throw PywalThemeValidationError.invalidSchema("missing \(name)")
        }
        do {
            return try ThemeColor(hex: value)
        } catch {
            throw PywalThemeValidationError.invalidSchema("invalid \(name) value \(value)")
        }
    }
}
