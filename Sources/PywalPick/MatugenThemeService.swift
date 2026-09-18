import Foundation

public struct ThemeProcessOutput: Sendable {
    public let exitCode: Int32
    public let output: String
    public let standardOutput: String
    public let standardError: String

    public init(
        exitCode: Int32,
        output: String,
        standardOutput: String? = nil,
        standardError: String = ""
    ) {
        self.exitCode = exitCode
        self.output = output
        self.standardOutput = standardOutput ?? output
        self.standardError = standardError
    }
}

private final class ThemePipeReader: @unchecked Sendable {
    private let pipe: Pipe

    init(pipe: Pipe) {
        self.pipe = pipe
    }

    func readToEnd() -> Data {
        pipe.fileHandleForReading.readDataToEndOfFile()
    }
}

public protocol ThemeProcessRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ThemeProcessOutput
}

public struct SystemThemeProcessRunner: ThemeProcessRunning {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ThemeProcessOutput {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            var processEnvironment = ProcessInfo.processInfo.environment
            processEnvironment.merge(environment) { _, newValue in newValue }
            process.environment = processEnvironment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
            } catch {
                throw MatugenThemeServiceError.processLaunchFailed(
                    executable,
                    error.localizedDescription
                )
            }

            let outputTask = Task.detached(priority: .utility) {
                ThemePipeReader(pipe: outputPipe).readToEnd()
            }
            let errorTask = Task.detached(priority: .utility) {
                ThemePipeReader(pipe: errorPipe).readToEnd()
            }

            process.waitUntilExit()

            let standardOutput = String(
                data: await outputTask.value,
                encoding: .utf8
            ) ?? ""
            let standardError = String(
                data: await errorTask.value,
                encoding: .utf8
            ) ?? ""
            let combinedOutput = [standardOutput, standardError]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            return ThemeProcessOutput(
                exitCode: process.terminationStatus,
                output: combinedOutput,
                standardOutput: standardOutput,
                standardError: standardError
            )
        }.value
    }
}

public enum MatugenThemeServiceError: LocalizedError, Sendable {
    case sourceMissing(String)
    case executableMissing(String)
    case processLaunchFailed(String, String)
    case processFailed(String)
    case cacheValidationFailed(String)
    case cachePublicationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sourceMissing(let path):
            return "Wallpaper file not found: \(path)"
        case .executableMissing(let name):
            return "Required executable not found: \(name)"
        case .processLaunchFailed(let executable, let message):
            return "Could not launch \(executable): \(message)"
        case .processFailed(let output):
            return output.isEmpty ? "Theme generation failed" : output
        case .cacheValidationFailed(let message):
            return "Generated theme cache is invalid: \(message)"
        case .cachePublicationFailed(let message):
            return "Could not publish generated theme cache: \(message)"
        }
    }
}

public struct MatugenThemeResult: Sendable {
    public let reused: Bool
    public let cacheDirectory: URL
    public let duration: TimeInterval

    public init(reused: Bool, cacheDirectory: URL, duration: TimeInterval) {
        self.reused = reused
        self.cacheDirectory = cacheDirectory
        self.duration = duration
    }
}

public actor MatugenThemeService {
    public static let shared = MatugenThemeService()

    private struct Manifest: Codable, Equatable, Sendable {
        let mappingVersion: Int
        let sourcePath: String
        let sourceSize: Int64
        let sourceModificationDate: TimeInterval
        let sourceResourceIdentifier: String
        let inputPath: String
        let matugenBinaryPath: String
        let matugenBinarySize: Int64
        let matugenBinaryModificationDate: TimeInterval
        let walBinaryPath: String
        let walBinarySize: Int64
        let walBinaryModificationDate: TimeInterval
        let inputSize: Int64
        let inputModificationDate: TimeInterval
        let mode: MatugenMode
        let schemeType: MatugenSchemeType
        let contrast: Double
    }

    private static let requiredFiles = ["colors", "colors.json", "colors.sh"]
    private static let manifestName = "pywalpick-matugen-manifest.json"
    private static let rawMatugenColorsName = "matugen-colors.json"
    private static let mappingVersion = 2

    private let processRunner: any ThemeProcessRunning
    private let fileManager: FileManager
    private let cacheRoot: URL
    private let pywalCacheDirectory: URL
    private let configDirectory: URL

    public init(
        processRunner: any ThemeProcessRunning = SystemThemeProcessRunner(),
        cacheRoot: URL? = nil,
        pywalCacheDirectory: URL? = nil,
        configDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.processRunner = processRunner
        self.fileManager = fileManager

        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")

        self.cacheRoot = cacheRoot ?? cachesDirectory.appendingPathComponent("PywalPick/Matugen")
        self.pywalCacheDirectory = pywalCacheDirectory
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cache/wal")
        self.configDirectory = configDirectory
            ?? applicationSupportDirectory.appendingPathComponent("PywalPick/Matugen")
    }

    public func generate(
        sourceURL: URL,
        inputURL: URL,
        config: AppConfig
    ) async throws -> MatugenThemeResult {
        let start = Date()
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw MatugenThemeServiceError.sourceMissing(sourceURL.path)
        }
        guard fileManager.fileExists(atPath: inputURL.path) else {
            throw MatugenThemeServiceError.sourceMissing(inputURL.path)
        }

        let matugenPath = try resolveExecutable(
            configuredPath: config.matugenBinaryPath,
            candidates: [
                NSHomeDirectory() + "/.cargo/bin/matugen",
                "/opt/homebrew/bin/matugen",
                "/usr/local/bin/matugen",
                "/usr/bin/matugen",
            ],
            name: "matugen"
        )
        let walPath = try resolveExecutable(
            configuredPath: config.walBinaryPath,
            candidates: [
                "/usr/local/bin/wal",
                "/opt/homebrew/bin/wal",
                "/usr/bin/wal",
                NSHomeDirectory() + "/.local/bin/wal",
                NSHomeDirectory() + "/bin/wal",
            ],
            name: "wal"
        )

        let manifest = try makeManifest(
            sourceURL: sourceURL,
            inputURL: inputURL,
            matugenPath: matugenPath,
            walPath: walPath,
            config: config
        )

        try ensureDirectories()
        if try isReusable(manifest: manifest) {
            return MatugenThemeResult(
                reused: true,
                cacheDirectory: pywalCacheDirectory,
                duration: Date().timeIntervalSince(start)
            )
        }

        let stagingDirectory = cacheRoot.appendingPathComponent("staging", isDirectory: true)
        try resetDirectory(stagingDirectory)
        let matugenConfigURL = configDirectory.appendingPathComponent("config.toml")
        try ensureMatugenConfig(at: matugenConfigURL)

        let matugenOutput = try await processRunner.run(
            executable: matugenPath,
            arguments: [
                "image",
                inputURL.path,
                "--config",
                matugenConfigURL.path,
                "--json",
                "hex",
                "--include-image-in-json",
                "true",
                "--base16-backend",
                "wal",
                "--mode",
                config.matugenMode.rawValue,
                "--type",
                config.matugenSchemeType.rawValue,
                "--contrast",
                String(
                    format: "%.3f",
                    locale: Locale(identifier: "en_US_POSIX"),
                    config.matugenContrast
                ),
                "--source-color-index",
                "0",
                "--quiet",
            ],
            environment: ["NO_FUN": "1"]
        )

        guard matugenOutput.exitCode == 0 else {
            throw MatugenThemeServiceError.processFailed(matugenOutput.output)
        }

        let matugenJSON = Data(matugenOutput.standardOutput.utf8)
        let schemeJSON = try MatugenThemeConverter.makePywalScheme(
            from: matugenJSON,
            wallpaperPath: inputURL.path,
            mode: config.matugenMode,
            schemeType: config.matugenSchemeType
        )

        let schemeURL = stagingDirectory.appendingPathComponent("matugen-pywal-scheme.json")
        try schemeJSON.write(to: schemeURL, options: .atomic)

        let walOutput = try await processRunner.run(
            executable: walPath,
            arguments: [
                "--theme",
                schemeURL.path,
                "--out-dir",
                stagingDirectory.path,
                "-n",
                "-q",
                "-e",
                "-s",
            ],
            environment: [
                "NO_FUN": "1",
                "PYWAL_CACHE_DIR": stagingDirectory.path,
            ]
        )

        guard walOutput.exitCode == 0 else {
            throw MatugenThemeServiceError.processFailed(walOutput.output)
        }

        let accent = try MatugenThemeConverter.materialAccent(
            from: matugenJSON,
            mode: config.matugenMode
        )
        try MatugenThemeConverter.applyGeneratedThemeOverrides(
            at: stagingDirectory,
            primary: accent.primary,
            onPrimary: accent.onPrimary
        )

        try validateGeneratedCache(at: stagingDirectory)
        try PywalThemeValidator.validate(
            directory: stagingDirectory,
            expectedScheme: schemeJSON,
            enforceStandardContrast: config.matugenContrast == 0
        )
        try matugenJSON.write(
            to: stagingDirectory.appendingPathComponent(Self.rawMatugenColorsName),
            options: .atomic
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(
            to: stagingDirectory.appendingPathComponent(Self.manifestName),
            options: .atomic
        )
        try publishGeneratedCache(from: stagingDirectory)

        return MatugenThemeResult(
            reused: false,
            cacheDirectory: pywalCacheDirectory,
            duration: Date().timeIntervalSince(start)
        )
    }

    private func resolveExecutable(
        configuredPath: String,
        candidates: [String],
        name: String
    ) throws -> String {
        let paths = [configuredPath] + candidates
        for path in paths where !path.isEmpty && fileManager.isExecutableFile(atPath: path) {
            return path
        }
        throw MatugenThemeServiceError.executableMissing(name)
    }

    private func makeManifest(
        sourceURL: URL,
        inputURL: URL,
        matugenPath: String,
        walPath: String,
        config: AppConfig
    ) throws -> Manifest {
        let values = try sourceURL.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
        ])
        let inputValues = try inputURL.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
        ])
        let matugenValues = try URL(fileURLWithPath: matugenPath).resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
        ])
        let walValues = try URL(fileURLWithPath: walPath).resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
        ])
        return Manifest(
            mappingVersion: Self.mappingVersion,
            sourcePath: sourceURL.standardizedFileURL.path,
            sourceSize: Int64(values.fileSize ?? 0),
            sourceModificationDate: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
            sourceResourceIdentifier: String(describing: values.fileResourceIdentifier as Any),
            inputPath: inputURL.standardizedFileURL.path,
            matugenBinaryPath: matugenPath,
            matugenBinarySize: Int64(matugenValues.fileSize ?? 0),
            matugenBinaryModificationDate: matugenValues.contentModificationDate?.timeIntervalSince1970 ?? 0,
            walBinaryPath: walPath,
            walBinarySize: Int64(walValues.fileSize ?? 0),
            walBinaryModificationDate: walValues.contentModificationDate?.timeIntervalSince1970 ?? 0,
            inputSize: Int64(inputValues.fileSize ?? 0),
            inputModificationDate: inputValues.contentModificationDate?.timeIntervalSince1970 ?? 0,
            mode: config.matugenMode,
            schemeType: config.matugenSchemeType,
            contrast: config.matugenContrast
        )
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: pywalCacheDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    }

    private func ensureMatugenConfig(at url: URL) throws {
        // Matugen requires a [config] table even when the app does not use
        // its template/reload features. Disabling wallpaper writes keeps the
        // generated scheme side-effect free; Pywal performs the actual cache
        // publication below.
        let contents = """
        # Managed by Pywal Pick. Templates are intentionally disabled.
        [config]
        version_check = false
        caching = false

        [config.wallpaper]
        command = "/usr/bin/true"
        set = false

        [templates]
        """
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == contents {
            return
        }
        try Data(contents.utf8).write(to: url, options: .atomic)
    }

    private func isReusable(manifest: Manifest) throws -> Bool {
        let manifestURL = pywalCacheDirectory.appendingPathComponent(Self.manifestName)
        guard let data = try? Data(contentsOf: manifestURL),
              let cached = try? JSONDecoder().decode(Manifest.self, from: data),
              cached == manifest
        else {
            return false
        }

        guard Self.requiredFiles.allSatisfy({
            let url = pywalCacheDirectory.appendingPathComponent($0)
            return fileManager.fileExists(atPath: url.path)
                && ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
        }) else { return false }

        guard let rawData = try? Data(contentsOf: pywalCacheDirectory.appendingPathComponent(Self.rawMatugenColorsName)),
              let scheme = try? MatugenThemeConverter.makePywalScheme(
                  from: rawData,
                  wallpaperPath: manifest.inputPath,
                  mode: manifest.mode,
                  schemeType: manifest.schemeType
              )
        else { return false }
        do {
            try PywalThemeValidator.validate(
                directory: pywalCacheDirectory,
                expectedScheme: scheme,
                enforceStandardContrast: manifest.contrast == 0
            )
            return true
        } catch {
            return false
        }
    }

    private func resetDirectory(_ directory: URL) throws {
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func validateGeneratedCache(at directory: URL) throws {
        for name in Self.requiredFiles {
            let url = directory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path),
                  ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
            else {
                throw MatugenThemeServiceError.cacheValidationFailed("missing \(name)")
            }
        }

        guard let colors = try? String(
            contentsOf: directory.appendingPathComponent("colors"),
            encoding: .utf8
        ) else {
            throw MatugenThemeServiceError.cacheValidationFailed("colors is not UTF-8")
        }
        let colorLines = colors.components(separatedBy: .newlines).filter {
            !$0.isEmpty && $0.hasPrefix("#")
        }
        guard colorLines.count >= 16 else {
            throw MatugenThemeServiceError.cacheValidationFailed(
                "colors contains only \(colorLines.count) ANSI colors"
            )
        }

        guard let colorsData = try? Data(contentsOf: directory.appendingPathComponent("colors.json")),
              (try? JSONSerialization.jsonObject(with: colorsData)) != nil
        else {
            throw MatugenThemeServiceError.cacheValidationFailed("colors.json is not valid JSON")
        }
    }

    private func publishGeneratedCache(from directory: URL) throws {
        do {
            let files = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            for file in files {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let data = try Data(contentsOf: file)
                let destination = pywalCacheDirectory.appendingPathComponent(file.lastPathComponent)
                try data.write(to: destination, options: .atomic)
            }
        } catch {
            throw MatugenThemeServiceError.cachePublicationFailed(error.localizedDescription)
        }
    }
}
