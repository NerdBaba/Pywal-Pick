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
        mode: MatugenMode,
        schemeType: MatugenSchemeType = .schemeTonalSpot,
        preferredColors: [String: String] = [:]
    ) throws -> Data {
        let document = try makeDocument(from: data)
        guard !document.semanticColors.isEmpty else {
            throw MatugenThemeError.missingColor("colors")
        }

        let background = try color(named: "surface", from: document.semanticColors, mode: mode)
        let foreground = try color(named: "on_surface", from: document.semanticColors, mode: mode)
        let accent = try materialAccent(from: document.semanticColors, mode: mode)
        var pywalColors: [String: String]
        var cursor = accent.primary

        if document.tonalPalettes.isEmpty {
            // Keep old/hand-authored Matugen JSON usable. Current Matugen output
            // always includes tonal palettes and takes the scheme-aware path below.
            guard !document.base16Colors.isEmpty else {
                throw MatugenThemeError.missingColor("base16")
            }
            pywalColors = [:]
            for (slot, base16Name) in pywalBase16Mapping {
                pywalColors[slot] = try color(
                    named: base16Name,
                    from: document.base16Colors,
                    mode: mode
                )
            }
            pywalColors["color7"] = foreground
            pywalColors["color15"] = try color(named: "on_background", from: document.semanticColors, mode: mode)
        } else {
            let candidates = try MatugenColorCandidateBuilder.build(
                document: document,
                mode: mode,
                schemeType: schemeType
            )
            pywalColors = candidates.localColors
            for (slot, value) in candidates.acceptedPreferences(preferredColors) {
                if slot == "cursor" {
                    if candidates.acceptsCursor(value) {
                        cursor = value
                    }
                } else if candidates.accepts(value, for: slot) {
                    pywalColors[slot] = value
                }
            }
        }

        let scheme: [String: Any] = [
            "wallpaper": wallpaperPath,
            "alpha": "100",
            "special": [
                "background": background,
                "foreground": foreground,
                "cursor": cursor,
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

    static func makeColorCandidates(
        from data: Data,
        mode: MatugenMode,
        schemeType: MatugenSchemeType
    ) throws -> MatugenThemeCandidateSet {
        let document = try makeDocument(from: data)
        guard !document.tonalPalettes.isEmpty else {
            throw MatugenThemeError.missingColor("palettes")
        }
        return try MatugenColorCandidateBuilder.build(
            document: document,
            mode: mode,
            schemeType: schemeType
        )
    }

    static func applyGeneratedThemeOverrides(
        at directory: URL,
        primary: String,
        onPrimary: String
    ) throws {
        let fileManager = FileManager.default
        let tilixURL = directory.appendingPathComponent("colors-tilix.json")
        if fileManager.fileExists(atPath: tilixURL.path) {
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

        let ghosttyURL = directory.appendingPathComponent("colors-ghostty")
        if fileManager.fileExists(atPath: ghosttyURL.path) {
            var contents = try String(contentsOf: ghosttyURL, encoding: .utf8)
            contents = replaceOrAppend("selection-background", with: primary, in: contents)
            contents = replaceOrAppend("selection-foreground", with: onPrimary, in: contents)
            contents = replaceOrAppend("cursor-color", with: primary, in: contents)
            contents = replaceOrAppend("cursor-text", with: onPrimary, in: contents)
            try Data(contents.utf8).write(to: ghosttyURL, options: .atomic)
        }
    }

    private static func replaceOrAppend(_ key: String, with value: String, in contents: String) -> String {
        let line = "\(key) = \(value)"
        let pattern = "(?m)^\\s*\(NSRegularExpression.escapedPattern(for: key))\\s*=.*$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return contents }
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        if let match = regex.firstMatch(in: contents, range: range),
           let matchRange = Range(match.range, in: contents) {
            return contents.replacingCharacters(in: matchRange, with: line)
        }
        return contents.hasSuffix("\n") ? contents + line + "\n" : contents + "\n" + line + "\n"
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

    static func color(
        named name: String,
        from colors: [String: MatugenPaletteColor],
        mode: MatugenMode
    ) throws -> String {
        guard let paletteColor = colors[name],
              let value = paletteColor.variants[mode.rawValue] ??
                (paletteColor.variants.count == 1 ? paletteColor.variants["default"] : nil)
        else {
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
        return characters.dropFirst().allSatisfy { character in
            guard character.unicodeScalars.count == 1,
                  let scalar = character.unicodeScalars.first
            else {
                return false
            }
            switch scalar.value {
            case 48...57, 65...70, 97...102:
                return true
            default:
                return false
            }
        }
    }
}
