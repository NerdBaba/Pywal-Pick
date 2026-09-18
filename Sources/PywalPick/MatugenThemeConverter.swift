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
        schemeType: MatugenSchemeType = .schemeTonalSpot
    ) throws -> Data {
        let document = try makeDocument(from: data)
        guard !document.semanticColors.isEmpty else {
            throw MatugenThemeError.missingColor("colors")
        }

        let background = try color(named: "surface", from: document.semanticColors, mode: mode)
        let foreground = try color(named: "on_surface", from: document.semanticColors, mode: mode)
        let accent = try materialAccent(from: document.semanticColors, mode: mode)
        let backgroundColor = try ThemeColor(hex: background)
        var pywalColors: [String: String]

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
            pywalColors = try makeTonalColors(
                document: document,
                background: backgroundColor,
                mode: mode,
                schemeType: schemeType
            )
        }

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

    private static func makeTonalColors(
        document: MatugenPaletteDocument,
        background: ThemeColor,
        mode: MatugenMode,
        schemeType: MatugenSchemeType
    ) throws -> [String: String] {
        let dark = mode == .dark
        let normalTone = dark ? 70.0 : 40.0
        let brightTone = dark ? 80.0 : 30.0
        let allNeutral = schemeType == .schemeMonochrome || schemeType == .schemeNeutral
        let families: [String: String] = allNeutral
            ? ["error": "neutral", "tertiary": "neutral", "secondary": "neutral", "primary": "neutral"]
            : ["error": "error", "tertiary": "tertiary", "secondary": "secondary", "primary": "primary"]

        func tone(_ family: String, _ target: Double) throws -> String {
            let resolvedFamily = families[family] ?? family
            guard let palette = document.tonalPalettes[resolvedFamily] else {
                throw MatugenThemeError.missingColor("palettes.\(resolvedFamily)")
            }
            return try MatugenToneSelector.select(
                family: palette,
                familyName: resolvedFamily,
                targetTone: target,
                background: background,
                minimumContrast: 4.5
            )
        }

        func readableSemantic(_ name: String) throws -> String? {
            guard document.semanticColors[name] != nil else { return nil }
            let value = try color(named: name, from: document.semanticColors, mode: mode)
            let parsed = try ThemeColor(hex: value)
            return parsed.contrastRatio(to: background) >= 4.5 ? parsed.hex : nil
        }

        let onSurface = try color(named: "on_surface", from: document.semanticColors, mode: mode)
        let onSurfaceVariant = try color(named: "on_surface_variant", from: document.semanticColors, mode: mode)
        var colors: [String: String] = [
            "color0": background.hex,
            "color7": onSurface,
            "color15": onSurface,
        ]
        if let variant = try? ThemeColor(hex: onSurfaceVariant),
           variant.contrastRatio(to: background) >= 4.5 {
            colors["color8"] = variant.hex
        } else {
            colors["color8"] = try tone("neutral", brightTone)
        }

        let slots: [(String, String, Double, String?)] = [
            ("color1", "error", normalTone, allNeutral ? nil : "error"),
            ("color2", "tertiary", normalTone, allNeutral ? nil : "tertiary"),
            ("color3", "secondary", normalTone, allNeutral ? nil : "secondary"),
            ("color4", "primary", normalTone, allNeutral ? nil : "primary"),
            ("color5", "secondary", brightTone, nil),
            ("color6", "tertiary", brightTone, nil),
            ("color9", "error", brightTone, nil),
            ("color10", "tertiary", brightTone, nil),
            ("color11", "secondary", brightTone, nil),
            ("color12", "primary", brightTone, nil),
            ("color13", "secondary", brightTone, nil),
            ("color14", "tertiary", brightTone, nil),
        ]
        for (slot, family, target, semanticName) in slots {
            if let semanticName,
               let semanticValue = try readableSemantic(semanticName) {
                colors[slot] = semanticValue
            } else {
                colors[slot] = try tone(family, target)
            }
        }
        return colors
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

    private static func color(
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
