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
                    "on_surface": {"dark": {"color": "#f0f0f0"}}
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
        XCTAssertEqual(special["cursor"], "#f0f0f0")
        XCTAssertEqual(colors["color0"], "#100000")
        XCTAssertEqual(colors["color1"], "#800000")
        XCTAssertEqual(colors["color2"], "#b00000")
        XCTAssertEqual(colors["color7"], "#500000")
        XCTAssertEqual(colors["color8"], "#300000")
        XCTAssertEqual(colors["color15"], "#700000")
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

    private static let matugenFixture = """
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
        "on_surface": {"dark": {"color": "#f0f0f0"}}
      }
    }
    """
}

private actor RecordingThemeProcessRunner: ThemeProcessRunning {
    let matugenOutput: String
    private(set) var callCount = 0

    init(matugenOutput: String) {
        self.matugenOutput = matugenOutput
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ThemeProcessOutput {
        callCount += 1

        if arguments.first == "image" {
            return ThemeProcessOutput(exitCode: 0, output: matugenOutput)
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
        return ThemeProcessOutput(exitCode: 0, output: "")
    }
}
