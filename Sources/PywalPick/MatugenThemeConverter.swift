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
    private struct Tone: Decodable {
        let color: String
    }

    private struct PaletteColor: Decodable {
        let dark: Tone?
        let `default`: Tone?
        let light: Tone?

        func color(for mode: MatugenMode) -> String? {
            switch mode {
            case .dark:
                return dark?.color ?? `default`?.color
            case .light:
                return light?.color ?? `default`?.color
            }
        }
    }

    private struct MatugenPayload: Decodable {
        let base16: [String: PaletteColor]?
        let colors: [String: PaletteColor]?
    }

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
        let payload: MatugenPayload
        do {
            payload = try JSONDecoder().decode(MatugenPayload.self, from: data)
        } catch {
            throw MatugenThemeError.invalidJSON(error.localizedDescription)
        }

        guard let base16 = payload.base16 else {
            throw MatugenThemeError.missingColor("base16")
        }
        guard let materialColors = payload.colors else {
            throw MatugenThemeError.missingColor("colors")
        }

        var pywalColors: [String: String] = [:]
        for (slot, base16Name) in pywalBase16Mapping {
            pywalColors[slot] = try color(
                named: base16Name,
                from: base16,
                mode: mode
            )
        }

        let background = try color(named: "surface", from: materialColors, mode: mode)
        let foreground = try color(named: "on_surface", from: materialColors, mode: mode)
        let accent = try materialAccent(from: materialColors, mode: mode)
        pywalColors["color7"] = try color(
            named: "surface_container_highest",
            from: materialColors,
            mode: mode
        )
        pywalColors["color15"] = try color(
            named: "on_background",
            from: materialColors,
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
        let payload: MatugenPayload
        do {
            payload = try JSONDecoder().decode(MatugenPayload.self, from: data)
        } catch {
            throw MatugenThemeError.invalidJSON(error.localizedDescription)
        }
        guard let materialColors = payload.colors else {
            throw MatugenThemeError.missingColor("colors")
        }
        return try materialAccent(from: materialColors, mode: mode)
    }

    private static func color(
        named name: String,
        from colors: [String: PaletteColor],
        mode: MatugenMode
    ) throws -> String {
        guard let paletteColor = colors[name], let value = paletteColor.color(for: mode) else {
            throw MatugenThemeError.missingColor(name)
        }
        guard isHexColor(value) else {
            throw MatugenThemeError.invalidColor(name, value)
        }
        return value.lowercased()
    }

    private static func materialAccent(
        from colors: [String: PaletteColor],
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
