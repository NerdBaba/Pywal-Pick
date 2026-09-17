import XCTest
@testable import PywalPick

final class MatugenThemeTests: XCTestCase {
    func testMatugenIsAvailableInBackendCycle() {
        XCTAssertTrue(WalBackend.allCases.contains(.matugen))
        XCTAssertEqual(WalBackend.matugen.displayName, "Matugen (Material You)")
    }

    func testMatugenSettingsSurviveConfigRoundTrip() throws {
        var config = AppConfig.default
        config.matugenBinaryPath = "/custom/bin/matugen"
        config.matugenMode = .light
        config.matugenSchemeType = .schemeFidelity
        config.matugenContrast = 0.35

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded.matugenBinaryPath, "/custom/bin/matugen")
        XCTAssertEqual(decoded.matugenMode, .light)
        XCTAssertEqual(decoded.matugenSchemeType, .schemeFidelity)
        XCTAssertEqual(decoded.matugenContrast, 0.35)
    }

    func testOldConfigUsesMatugenDefaults() throws {
        let data = Data("{\"wallpaperFolderPath\":\"/wallpapers\"}".utf8)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded.matugenBinaryPath, AppConfig.default.matugenBinaryPath)
        XCTAssertEqual(decoded.matugenMode, AppConfig.default.matugenMode)
        XCTAssertEqual(decoded.matugenSchemeType, AppConfig.default.matugenSchemeType)
        XCTAssertEqual(decoded.matugenContrast, AppConfig.default.matugenContrast)
    }

    func testConvertsMatugenBase16AndMaterialColorsToPywalScheme() throws {
        let scheme = try MatugenThemeConverter.makePywalScheme(
            from: Data(
                """
                {
                  "base16": {
                    "base00": {"dark": {"color": "#100000"}},
                    "base03": {"dark": {"color": "#300000"}},
                    "base05": {"dark": {"color": "#500000"}},
                    "base07": {"dark": {"color": "#700000"}},
                    "base08": {"dark": {"color": "#800000"}},
                    "base0a": {"dark": {"color": "#a00000"}},
                    "base0b": {"dark": {"color": "#b00000"}},
                    "base0c": {"dark": {"color": "#c00000"}},
                    "base0d": {"dark": {"color": "#d00000"}},
                    "base0e": {"dark": {"color": "#e00000"}}
                  },
                  "colors": {
                    "surface": {"dark": {"color": "#101010"}},
                    "on_surface": {"dark": {"color": "#f0f0f0"}},
                    "on_background": {"dark": {"color": "#eeeeee"}},
                    "surface_container_highest": {"dark": {"color": "#202020"}},
                    "primary": {"dark": {"color": "#0088ff"}},
                    "on_primary": {"dark": {"color": "#001122"}}
                  }
                }
                """.utf8
            ),
            wallpaperPath: "/tmp/dummy.jpg",
            mode: .dark
        )

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: scheme) as? [String: Any]
        )
        let special = try XCTUnwrap(object["special"] as? [String: String])
        let colors = try XCTUnwrap(object["colors"] as? [String: String])

        XCTAssertEqual(object["wallpaper"] as? String, "/tmp/dummy.jpg")
        XCTAssertEqual(special["background"], "#101010")
        XCTAssertEqual(special["foreground"], "#f0f0f0")
        XCTAssertEqual(special["cursor"], "#0088ff")
        XCTAssertEqual(colors["color0"], "#100000")
        XCTAssertEqual(colors["color1"], "#800000")
        XCTAssertEqual(colors["color2"], "#b00000")
        XCTAssertEqual(colors["color7"], "#202020")
        XCTAssertEqual(colors["color8"], "#300000")
        XCTAssertEqual(colors["color15"], "#eeeeee")
    }

    func testAppliesMaterialAccentToGeneratedTilixHighlight() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pywalpick-tilix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let tilixURL = directory.appendingPathComponent("colors-tilix.json")
        let original: [String: Any] = [
            "cursor-background-color": "#101010",
            "cursor-foreground-color": "#f0f0f0",
            "foreground-color": "#f0f0f0",
            "highlight-background-color": "#101010",
            "highlight-foreground-color": "#f0f0f0",
            "use-cursor-color": false,
            "use-highlight-color": false,
        ]
        try JSONSerialization.data(withJSONObject: original, options: [])
            .write(to: tilixURL)

        try MatugenThemeConverter.applyGeneratedThemeOverrides(
            at: directory,
            primary: "#0088ff",
            onPrimary: "#001122"
        )

        let updated = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: tilixURL)) as? [String: Any]
        )
        XCTAssertEqual(updated["highlight-background-color"] as? String, "#0088ff")
        XCTAssertEqual(updated["highlight-foreground-color"] as? String, "#001122")
        XCTAssertEqual(updated["cursor-foreground-color"] as? String, "#0088ff")
        XCTAssertEqual(updated["use-highlight-color"] as? Bool, true)
        XCTAssertEqual(updated["use-cursor-color"] as? Bool, true)
    }

    func testRejectsMatugenJsonWithoutRequiredPalette() {
        XCTAssertThrowsError(
            try MatugenThemeConverter.makePywalScheme(
                from: Data("{\"colors\": {}}".utf8),
                wallpaperPath: "/tmp/dummy.jpg",
                mode: .dark
            )
        )
    }

    func testConvertsLegacyAndStrippedHexMatugenColorsForBothModes() throws {
        let scheme = try MatugenThemeConverter.makePywalScheme(
            from: Self.legacyMatugenFixture(),
            wallpaperPath: "/tmp/dummy.jpg",
            mode: .light
        )

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: scheme) as? [String: Any]
        )
        let special = try XCTUnwrap(object["special"] as? [String: String])
        let colors = try XCTUnwrap(object["colors"] as? [String: String])

        XCTAssertEqual(special["background"], "#fefefe")
        XCTAssertEqual(special["foreground"], "#101010")
        XCTAssertEqual(special["cursor"], "#445566")
        XCTAssertEqual(colors["color0"], "#fefefe")
        XCTAssertEqual(colors["color7"], "#dddddd")
        XCTAssertEqual(colors["color15"], "#101010")
    }

    func testRejectsMalformedRequiredLegacyColor() {
        XCTAssertThrowsError(
            try MatugenThemeConverter.makePywalScheme(
                from: Self.legacyMatugenFixture(primary: "not-a-color"),
                wallpaperPath: "/tmp/dummy.jpg",
                mode: .dark
            )
        ) { error in
            guard case MatugenThemeError.invalidColor("primary", "not-a-color") = error else {
                return XCTFail("Expected an invalid primary color error, got \(error)")
            }
        }
    }

    func testRejectsNonASCIINumeralsInRequiredHexColor() {
        XCTAssertThrowsError(
            try MatugenThemeConverter.makePywalScheme(
                from: Self.legacyMatugenFixture(primary: "#１２３４５６"),
                wallpaperPath: "/tmp/dummy.jpg",
                mode: .dark
            )
        ) { error in
            guard case MatugenThemeError.invalidColor("primary", "#１２３４５６") = error else {
                return XCTFail("Expected invalidColor for non-ASCII hex digits, got \(error)")
            }
        }
    }

    func testThemeServicePublishesPywalCacheAndReusesIt() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("pywalpick-matugen-test-\(UUID().uuidString)", isDirectory: true)
        let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
        let pywalCache = root.appendingPathComponent("wal", isDirectory: true)
        let configDirectory = root.appendingPathComponent("config", isDirectory: true)
        let sourceURL = root.appendingPathComponent("wallpaper.jpg")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("wallpaper fixture".utf8).write(to: sourceURL)
        defer { try? fileManager.removeItem(at: root) }

        let runner = RecordingThemeProcessRunner(
            matugenOutput: Self.matugenFixture,
            matugenDiagnostics: "Format error decoding Jpeg: Error parsing image."
        )
        let service = MatugenThemeService(
            processRunner: runner,
            cacheRoot: cacheRoot,
            pywalCacheDirectory: pywalCache,
            configDirectory: configDirectory
        )
        var config = AppConfig.default
        config.matugenBinaryPath = "/bin/sh"
        config.walBinaryPath = "/bin/sh"

        let first = try await service.generate(
            sourceURL: sourceURL,
            inputURL: sourceURL,
            config: config
        )
        XCTAssertFalse(first.reused)
        let callsAfterFirstGeneration = await runner.callCount
        XCTAssertEqual(callsAfterFirstGeneration, 2)
        XCTAssertTrue(fileManager.fileExists(atPath: pywalCache.appendingPathComponent("colors").path))
        XCTAssertTrue(fileManager.fileExists(atPath: pywalCache.appendingPathComponent("matugen-colors.json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: pywalCache.appendingPathComponent("pywalpick-matugen-manifest.json").path))
        let tilix = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: pywalCache.appendingPathComponent("colors-tilix.json"))
            ) as? [String: Any]
        )
        XCTAssertEqual(tilix["highlight-background-color"] as? String, "#0088ff")
        XCTAssertEqual(tilix["highlight-foreground-color"] as? String, "#001122")
        XCTAssertEqual(tilix["use-highlight-color"] as? Bool, true)

        let second = try await service.generate(
            sourceURL: sourceURL,
            inputURL: sourceURL,
            config: config
        )
        XCTAssertTrue(second.reused)
        let callsAfterReuse = await runner.callCount
        XCTAssertEqual(callsAfterReuse, 2)

        config.matugenContrast = 0.2
        let third = try await service.generate(
            sourceURL: sourceURL,
            inputURL: sourceURL,
            config: config
        )
        XCTAssertFalse(third.reused)
        let callsAfterConfigurationChange = await runner.callCount
        XCTAssertEqual(callsAfterConfigurationChange, 4)
    }

    func testThemeServiceSupportsEveryConfiguredModeAndScheme() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("pywalpick-matugen-matrix-\(UUID().uuidString)", isDirectory: true)
        let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
        let pywalCache = root.appendingPathComponent("wal", isDirectory: true)
        let configDirectory = root.appendingPathComponent("config", isDirectory: true)
        let sourceURL = root.appendingPathComponent("wallpaper.jpg")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("wallpaper fixture".utf8).write(to: sourceURL)
        defer { try? fileManager.removeItem(at: root) }

        let runner = RecordingThemeProcessRunner(matugenOutput: Self.matugenFixture)
        let service = MatugenThemeService(
            processRunner: runner,
            cacheRoot: cacheRoot,
            pywalCacheDirectory: pywalCache,
            configDirectory: configDirectory
        )
        var config = AppConfig.default
        config.matugenBinaryPath = "/bin/sh"
        config.walBinaryPath = "/bin/sh"

        for mode in MatugenMode.allCases {
            for schemeType in MatugenSchemeType.allCases {
                config.matugenMode = mode
                config.matugenSchemeType = schemeType
                let result = try await service.generate(
                    sourceURL: sourceURL,
                    inputURL: sourceURL,
                    config: config
                )
                XCTAssertFalse(result.reused, "Unexpected cache reuse for \(mode)/\(schemeType)")

                let snapshot = try MatugenPaletteCache.load(from: pywalCache)
                XCTAssertEqual(snapshot.document.semanticColors.count, 50)
                XCTAssertEqual(snapshot.document.base16Colors.count, 16)
                XCTAssertEqual(snapshot.document.tonalPalettes.count, 6)
                let generationInfo = try XCTUnwrap(snapshot.generationInfo)
                XCTAssertEqual(generationInfo.mode, mode)
                XCTAssertEqual(generationInfo.schemeType, schemeType)
                XCTAssertEqual(generationInfo.contrast, config.matugenContrast)
                XCTAssertNotNil(snapshot.document.semanticColors["surface"]?.value(for: mode))
                XCTAssertNotNil(snapshot.document.semanticColors["on_surface"]?.value(for: mode))
                XCTAssertNotNil(snapshot.document.semanticColors["primary"]?.value(for: mode))
                XCTAssertNotNil(snapshot.document.semanticColors["on_primary"]?.value(for: mode))
            }
        }

        let calls = await runner.callCount
        XCTAssertEqual(calls, MatugenMode.allCases.count * MatugenSchemeType.allCases.count * 2)
    }

    func testInstalledMatugenAndWalGenerateARealCache() async throws {
        let matugenPath = AppConfig.default.matugenBinaryPath
        let walPath = AppConfig.default.walBinaryPath
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: matugenPath)
                && FileManager.default.isExecutableFile(atPath: walPath),
            "Local Matugen and wal binaries are not installed"
        )

        let sourceURL = URL(fileURLWithPath: "/Volumes/NightSky/babaisalive/Pictures/dummy-file.jpg")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: sourceURL.path),
            "Local wallpaper fixture is not available"
        )

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("pywalpick-matugen-real-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        var config = AppConfig.default
        config.matugenBinaryPath = matugenPath
        config.walBinaryPath = walPath
        let service = MatugenThemeService(
            cacheRoot: root.appendingPathComponent("cache", isDirectory: true),
            pywalCacheDirectory: root.appendingPathComponent("wal", isDirectory: true),
            configDirectory: root.appendingPathComponent("config", isDirectory: true)
        )

        let first = try await service.generate(
            sourceURL: sourceURL,
            inputURL: sourceURL,
            config: config
        )
        XCTAssertFalse(first.reused)
        XCTAssertTrue(fileManager.fileExists(atPath: first.cacheDirectory.appendingPathComponent("colors").path))

        let colorsJSON = try Data(contentsOf: first.cacheDirectory.appendingPathComponent("colors.json"))
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: colorsJSON))

        let second = try await service.generate(
            sourceURL: sourceURL,
            inputURL: sourceURL,
            config: config
        )
        XCTAssertTrue(second.reused)
    }

    func testInstalledMatugenAndWalSupportEveryConfiguredVariant() async throws {
        let matugenPath = AppConfig.default.matugenBinaryPath
        let walPath = AppConfig.default.walBinaryPath
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: matugenPath)
                && FileManager.default.isExecutableFile(atPath: walPath),
            "Local Matugen and wal binaries are not installed"
        )

        let sourceURL = URL(fileURLWithPath: "/Volumes/NightSky/babaisalive/Pictures/dummy-file.jpg")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: sourceURL.path),
            "Local wallpaper fixture is not available"
        )

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("pywalpick-matugen-real-matrix-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        var config = AppConfig.default
        config.matugenBinaryPath = matugenPath
        config.walBinaryPath = walPath
        let service = MatugenThemeService(
            cacheRoot: root.appendingPathComponent("cache", isDirectory: true),
            pywalCacheDirectory: root.appendingPathComponent("wal", isDirectory: true),
            configDirectory: root.appendingPathComponent("config", isDirectory: true)
        )

        for mode in MatugenMode.allCases {
            for schemeType in MatugenSchemeType.allCases {
                config.matugenMode = mode
                config.matugenSchemeType = schemeType
                let result = try await service.generate(
                    sourceURL: sourceURL,
                    inputURL: sourceURL,
                    config: config
                )
                XCTAssertFalse(result.reused, "Unexpected reuse for \(mode)/\(schemeType)")

                let snapshot = try MatugenPaletteCache.load(from: result.cacheDirectory)
                XCTAssertEqual(snapshot.document.semanticColors.count, 50)
                XCTAssertEqual(snapshot.document.base16Colors.count, 16)
                XCTAssertEqual(snapshot.document.tonalPalettes.count, 6)
                XCTAssertEqual(snapshot.generationInfo?.mode, mode)
                XCTAssertEqual(snapshot.generationInfo?.schemeType, schemeType)
                let colors = try String(
                    contentsOf: result.cacheDirectory.appendingPathComponent("colors"),
                    encoding: .utf8
                )
                XCTAssertGreaterThanOrEqual(
                    colors.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("#") }.count,
                    16
                )
            }
        }
    }

    func testMalformedMatugenOutputLeavesExistingPywalCacheUntouched() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("pywalpick-matugen-invalid-\(UUID().uuidString)", isDirectory: true)
        let pywalCache = root.appendingPathComponent("wal", isDirectory: true)
        let sourceURL = root.appendingPathComponent("wallpaper.jpg")
        try fileManager.createDirectory(at: pywalCache, withIntermediateDirectories: true)
        try Data("wallpaper fixture".utf8).write(to: sourceURL)
        let existingColors = "#existing-cache\n"
        try existingColors.write(
            to: pywalCache.appendingPathComponent("colors"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? fileManager.removeItem(at: root) }

        let runner = RecordingThemeProcessRunner(matugenOutput: "not json")
        let service = MatugenThemeService(
            processRunner: runner,
            cacheRoot: root.appendingPathComponent("cache", isDirectory: true),
            pywalCacheDirectory: pywalCache,
            configDirectory: root.appendingPathComponent("config", isDirectory: true)
        )
        var config = AppConfig.default
        config.matugenBinaryPath = "/bin/sh"
        config.walBinaryPath = "/bin/sh"

        do {
            _ = try await service.generate(sourceURL: sourceURL, inputURL: sourceURL, config: config)
            XCTFail("Malformed Matugen output should fail generation")
        } catch {
            XCTAssertTrue(error is MatugenThemeError)
        }

        XCTAssertEqual(
            try String(contentsOf: pywalCache.appendingPathComponent("colors"), encoding: .utf8),
            existingColors
        )
        let calls = await runner.callCount
        XCTAssertEqual(calls, 1)
    }

    private static let matugenFixture: String = {
        let roleNames = [
            "background", "error", "error_container", "inverse_on_surface", "inverse_primary",
            "inverse_surface", "on_background", "on_error", "on_error_container", "on_primary",
            "on_primary_container", "on_primary_fixed", "on_primary_fixed_variant", "on_secondary",
            "on_secondary_container", "on_secondary_fixed", "on_secondary_fixed_variant", "on_surface",
            "on_surface_variant", "on_tertiary", "on_tertiary_container", "on_tertiary_fixed",
            "on_tertiary_fixed_variant", "outline", "outline_variant", "primary", "primary_container",
            "primary_fixed", "primary_fixed_dim", "scrim", "secondary", "secondary_container",
            "secondary_fixed", "secondary_fixed_dim", "shadow", "source_color", "surface", "surface_bright",
            "surface_container", "surface_container_high", "surface_container_highest", "surface_container_low",
            "surface_container_lowest", "surface_dim", "surface_tint", "surface_variant", "tertiary",
            "tertiary_container", "tertiary_fixed", "tertiary_fixed_dim",
        ]
        let base16Names = (0..<16).map { String(format: "base%02x", $0) }
        let toneNames = ["0", "5", "10", "15", "20", "25", "30", "35", "40", "50", "60", "70", "80", "90", "95", "98", "99", "100"]

        var colors: [String: Any] = [:]
        for (index, name) in roleNames.enumerated() {
            colors[name] = [
                "dark": ["color": String(format: "#%06x", 0x100000 + index)],
                "default": ["color": String(format: "#%06x", 0x100000 + index)],
                "light": ["color": String(format: "#%06x", 0x200000 + index)],
            ]
        }
        colors["surface"] = ["dark": ["color": "#101010"], "light": ["color": "#fefefe"]]
        colors["on_surface"] = ["dark": ["color": "#f0f0f0"], "light": ["color": "#101010"]]
        colors["on_background"] = ["dark": ["color": "#eeeeee"], "light": ["color": "#101010"]]
        colors["surface_container_highest"] = ["dark": ["color": "#202020"], "light": ["color": "#dddddd"]]
        colors["primary"] = ["dark": ["color": "#0088ff"], "light": ["color": "#445566"]]
        colors["on_primary"] = ["dark": ["color": "#001122"], "light": ["color": "#ffffff"]]

        var base16: [String: Any] = [:]
        for (index, name) in base16Names.enumerated() {
            base16[name] = [
                "dark": ["color": String(format: "#%06x", 0x300000 + index)],
                "default": ["color": String(format: "#%06x", 0x300000 + index)],
                "light": ["color": String(format: "#%06x", 0x400000 + index)],
            ]
        }

        var palettes: [String: Any] = [:]
        for (familyIndex, family) in ["error", "neutral", "neutral_variant", "primary", "secondary", "tertiary"].enumerated() {
            var tones: [String: Any] = [:]
            for (toneIndex, tone) in toneNames.enumerated() {
                tones[tone] = ["color": String(format: "#%06x", 0x500000 + familyIndex * 0x1000 + toneIndex)]
            }
            palettes[family] = tones
        }

        let object: [String: Any] = [
            "mode": "dark",
            "is_dark_mode": true,
            "image": "/tmp/wallpaper.jpg",
            "base16": base16,
            "colors": colors,
            "palettes": palettes,
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }()

    private static func legacyMatugenFixture(primary: String = "112233") -> Data {
        let base16Names = [
            "base00", "base03", "base05", "base07", "base08",
            "base0a", "base0b", "base0c", "base0d", "base0e",
        ]
        var base16: [String: Any] = [:]
        for (index, name) in base16Names.enumerated() {
            base16[name] = [
                "dark": String(format: "%06x", 0x100000 + index),
                "light": String(format: "%06x", 0x200000 + index),
            ]
        }
        base16["base00"] = ["dark": "101010", "light": "fefefe"]
        base16["base03"] = ["dark": "303030", "light": "cccccc"]
        base16["base05"] = ["dark": "505050", "light": "dddddd"]
        base16["base07"] = ["dark": "707070", "light": "eeeeee"]

        let colors: [String: Any] = [
            "surface": ["dark": "101010", "light": "fefefe"],
            "on_surface": ["dark": "f0f0f0", "light": "101010"],
            "on_background": ["dark": "eeeeee", "light": "101010"],
            "surface_container_highest": ["dark": "202020", "light": "dddddd"],
            "primary": ["dark": primary, "light": "445566"],
            "on_primary": ["dark": "ffffff", "light": "ffffff"],
        ]

        return try! JSONSerialization.data(withJSONObject: [
            "base16": base16,
            "colors": colors,
        ])
    }
}

private actor RecordingThemeProcessRunner: ThemeProcessRunning {
    let matugenOutput: String
    let matugenDiagnostics: String
    private(set) var callCount = 0

    init(matugenOutput: String, matugenDiagnostics: String = "") {
        self.matugenOutput = matugenOutput
        self.matugenDiagnostics = matugenDiagnostics
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ThemeProcessOutput {
        callCount += 1

        if arguments.first == "image" {
            let combinedOutput = [matugenOutput, matugenDiagnostics]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return ThemeProcessOutput(
                exitCode: 0,
                output: combinedOutput,
                standardOutput: matugenOutput,
                standardError: matugenDiagnostics
            )
        }

        guard let outDirectoryIndex = arguments.firstIndex(of: "--out-dir"),
              arguments.indices.contains(outDirectoryIndex + 1)
        else {
            return ThemeProcessOutput(exitCode: 1, output: "missing out directory")
        }

        let directory = URL(fileURLWithPath: arguments[outDirectoryIndex + 1])
        let colors = (0..<16).map { index in "#\(String(format: "%06x", index * 0x10101))" }.joined(separator: "\n") + "\n"
        try colors.write(to: directory.appendingPathComponent("colors"), atomically: true, encoding: .utf8)
        try "{\"colors\": {}}".write(to: directory.appendingPathComponent("colors.json"), atomically: true, encoding: .utf8)
        try "color0='0x000000'".write(to: directory.appendingPathComponent("colors.sh"), atomically: true, encoding: .utf8)
        let tilix: [String: Any] = [
            "cursor-background-color": "#101010",
            "cursor-foreground-color": "#f0f0f0",
            "foreground-color": "#f0f0f0",
            "highlight-background-color": "#101010",
            "highlight-foreground-color": "#f0f0f0",
            "use-cursor-color": false,
            "use-highlight-color": false,
        ]
        let tilixData = try JSONSerialization.data(withJSONObject: tilix, options: [])
        try tilixData.write(to: directory.appendingPathComponent("colors-tilix.json"))
        return ThemeProcessOutput(exitCode: 0, output: "")
    }
}
