import Foundation

enum MatugenThemeError: LocalizedError, Sendable {
    case invalidJSON(String)
    case missingColor(String)
    case invalidColor(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let message):
            return "Matugen returned invalid JSON: \(message)"
        case .missingColor(let name):
            return "Matugen JSON is missing the required color \(name)"
        case .invalidColor(let name, let value):
            return "Matugen returned an invalid color for \(name): \(value)"
        }
    }
}

struct MatugenThemeAccent: Sendable, Equatable {
    let primary: String
    let onPrimary: String
}

struct MatugenThemeConverter {
    private static let pywalBase16Mapping: [(String, String)] = [
        ("color0", "base00"),
        ("color1", "base08"),
        ("color2", "base0b"),
        ("color3", "base0a"),
        ("color4", "base0d"),
        ("color5", "base0e"),
        ("color6", "base0c"),
        ("color8", "base03"),
        ("color9", "base08"),
        ("color10", "base0b"),
        ("color11", "base0a"),
        ("color12", "base0d"),
        ("color13", "base0e"),
        ("color14", "base0c"),
    ]

    static func makePywalScheme(
        from data: Data,
        wallpaperPath: String,
        mode: MatugenMode
    ) throws -> Data {
        let document = try makeDocument(from: data)
        guard !document.base16Colors.isEmpty else {
            throw MatugenThemeError.missingColor("base16")
        }
        guard !document.semanticColors.isEmpty else {
            throw MatugenThemeError.missingColor("colors")
        }

        var pywalColors: [String: String] = [:]
        for (slot, base16Name) in pywalBase16Mapping {
            pywalColors[slot] = try color(
                named: base16Name,
                from: document.base16Colors,
                mode: mode
            )
        }

        let background = try color(named: "surface", from: document.semanticColors, mode: mode)
        let foreground = try color(named: "on_surface", from: document.semanticColors, mode: mode)
        let accent = try materialAccent(from: document.semanticColors, mode: mode)
        pywalColors["color7"] = try color(
            named: "surface_container_highest",
            from: document.semanticColors,
            mode: mode
        )
        pywalColors["color15"] = try color(
            named: "on_background",
            from: document.semanticColors,
            mode: mode
        )

        let scheme: [String: Any] = [
            "wallpaper": wallpaperPath,
            "alpha": "100",
            "special": [
                "background": background,
                "foreground": foreground,
                "cursor": accent.primary,
            ],
            "colors": pywalColors,
        ]

        do {
            return try JSONSerialization.data(
                withJSONObject: scheme,
                options: [.prettyPrinted, .sortedKeys]
            )
        } catch {
            throw MatugenThemeError.invalidJSON(error.localizedDescription)
        }
    }

    static func applyGeneratedThemeOverrides(
        at directory: URL,
        primary: String,
        onPrimary: String
    ) throws {
        let tilixURL = directory.appendingPathComponent("colors-tilix.json")
        guard FileManager.default.fileExists(atPath: tilixURL.path) else { return }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(contentsOf: tilixURL))
        } catch {
            throw MatugenThemeError.invalidJSON(error.localizedDescription)
        }
        guard var theme = object as? [String: Any] else {
            throw MatugenThemeError.invalidJSON("Tilix theme is not a JSON object")
        }

        theme["cursor-foreground-color"] = primary
        theme["highlight-background-color"] = primary
        theme["highlight-foreground-color"] = onPrimary
        theme["use-cursor-color"] = true
        theme["use-highlight-color"] = true

        do {
            let data = try JSONSerialization.data(
                withJSONObject: theme,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: tilixURL, options: .atomic)
        } catch {
            throw MatugenThemeError.invalidJSON(error.localizedDescription)
        }
    }

    static func materialAccent(
        from data: Data,
        mode: MatugenMode
    ) throws -> MatugenThemeAccent {
        let document = try makeDocument(from: data)
        guard !document.semanticColors.isEmpty else {
            throw MatugenThemeError.missingColor("colors")
        }
        return try materialAccent(from: document.semanticColors, mode: mode)
    }

    private static func makeDocument(from data: Data) throws -> MatugenPaletteDocument {
        do {
            return try MatugenPaletteDocument(data: data)
        } catch {
            throw MatugenThemeError.invalidJSON(error.localizedDescription)
        }
    }

    private static func color(
        named name: String,
        from colors: [String: MatugenPaletteColor],
        mode: MatugenMode
    ) throws -> String {
        guard let paletteColor = colors[name], let value = paletteColor.value(for: mode) else {
            throw MatugenThemeError.missingColor(name)
        }
        let normalized = value.hasPrefix("#") ? value.lowercased() : "#" + value.lowercased()
        guard isHexColor(normalized) else {
            throw MatugenThemeError.invalidColor(name, value)
        }
        return normalized
    }

    private static func materialAccent(
        from colors: [String: MatugenPaletteColor],
        mode: MatugenMode
    ) throws -> MatugenThemeAccent {
        MatugenThemeAccent(
            primary: try color(named: "primary", from: colors, mode: mode),
            onPrimary: try color(named: "on_primary", from: colors, mode: mode)
        )
    }

    private static func isHexColor(_ value: String) -> Bool {
        let characters = Array(value)
        guard characters.count == 7, characters[0] == "#" else { return false }
        return characters.dropFirst().allSatisfy {
            $0.isNumber || ("a"..."f").contains($0.lowercased())
        }
    }
}
