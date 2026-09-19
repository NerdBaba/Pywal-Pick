import Foundation
import XCTest
@testable import PywalPick

final class MatugenPreferenceIntegrationTests: XCTestCase {
    func testRankedStatusIsSavedWithoutSecretOrWallpaperPath() async throws {
        let context = try Self.makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let statusURL = context.root.appendingPathComponent("last-status.json")
        let ranker = RecordingPreferenceRanker { candidates in
            ["color2": candidates.choices["color2"]!.first!.hex]
        }
        let service = MatugenThemeService(
            processRunner: context.runner,
            cacheRoot: context.root.appendingPathComponent("cache"),
            pywalCacheDirectory: context.root.appendingPathComponent("wal"),
            configDirectory: context.root.appendingPathComponent("config"),
            preferenceRanker: ranker,
            apiKeyStore: FixedTypeSafeAPIKeyStore(value: "integration-secret"),
            statusStore: TypeSafePreferenceStatusStore(fileURL: statusURL)
        )
        var config = AppConfig.default
        config.matugenBinaryPath = "/bin/sh"
        config.walBinaryPath = "/bin/sh"
        config.matugenTypeSafeEnabled = true

        _ = try await service.generate(sourceURL: context.sourceURL, inputURL: context.sourceURL, config: config)

        let status = try XCTUnwrap(TypeSafePreferenceStatusStore(fileURL: statusURL).load())
        XCTAssertEqual(status.outcome, .ranked)
        XCTAssertEqual(status.selectedColors.count, 1)
        XCTAssertGreaterThan(status.estimatedInputTokens, 0)
        let raw = try String(contentsOf: statusURL)
        XCTAssertFalse(raw.contains("integration-secret"))
        XCTAssertFalse(raw.contains(context.sourceURL.path))
    }

    func testFallbackStatusIsSavedWhenRankingFails() async throws {
        let context = try Self.makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let statusURL = context.root.appendingPathComponent("last-status.json")
        let service = MatugenThemeService(
            processRunner: context.runner,
            cacheRoot: context.root.appendingPathComponent("cache"),
            pywalCacheDirectory: context.root.appendingPathComponent("wal"),
            configDirectory: context.root.appendingPathComponent("config"),
            preferenceRanker: RecordingPreferenceRanker { _ in
                throw TypeSafeColorPreferenceError.invalidResponse
            },
            apiKeyStore: FixedTypeSafeAPIKeyStore(value: "integration-secret"),
            statusStore: TypeSafePreferenceStatusStore(fileURL: statusURL)
        )
        var config = AppConfig.default
        config.matugenBinaryPath = "/bin/sh"
        config.walBinaryPath = "/bin/sh"
        config.matugenTypeSafeEnabled = true

        _ = try await service.generate(sourceURL: context.sourceURL, inputURL: context.sourceURL, config: config)

        let status = try XCTUnwrap(TypeSafePreferenceStatusStore(fileURL: statusURL).load())
        XCTAssertEqual(status.outcome, .fallback)
        XCTAssertTrue(status.selectedColors.isEmpty)
    }

    func testCacheReuseStatusIsSavedAfterASecondGeneration() async throws {
        let context = try Self.makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let statusURL = context.root.appendingPathComponent("last-status.json")
        let service = MatugenThemeService(
            processRunner: context.runner,
            cacheRoot: context.root.appendingPathComponent("cache"),
            pywalCacheDirectory: context.root.appendingPathComponent("wal"),
            configDirectory: context.root.appendingPathComponent("config"),
            preferenceRanker: RecordingPreferenceRanker { candidates in
                ["color2": candidates.choices["color2"]!.first!.hex]
            },
            apiKeyStore: FixedTypeSafeAPIKeyStore(value: "integration-secret"),
            statusStore: TypeSafePreferenceStatusStore(fileURL: statusURL)
        )
        var config = AppConfig.default
        config.matugenBinaryPath = "/bin/sh"
        config.walBinaryPath = "/bin/sh"
        config.matugenTypeSafeEnabled = true

        _ = try await service.generate(sourceURL: context.sourceURL, inputURL: context.sourceURL, config: config)
        let second = try await service.generate(sourceURL: context.sourceURL, inputURL: context.sourceURL, config: config)
        XCTAssertTrue(second.reused)

        let status = try XCTUnwrap(TypeSafePreferenceStatusStore(fileURL: statusURL).load())
        XCTAssertEqual(status.outcome, .cacheReused)
        XCTAssertEqual(status.selectedColors.count, 1)
    }

    func testHighConfidenceChoiceIsPublishedAndStoredWithoutTheAPIKey() async throws {
        let context = try Self.makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let ranker = RecordingPreferenceRanker { candidates in
            ["color2": candidates.choices["color2"]!.first!.hex]
        }
        let keyStore = FixedTypeSafeAPIKeyStore(value: "integration-secret")
        let service = MatugenThemeService(
            processRunner: context.runner,
            cacheRoot: context.root.appendingPathComponent("cache"),
            pywalCacheDirectory: context.root.appendingPathComponent("wal"),
            configDirectory: context.root.appendingPathComponent("config"),
            preferenceRanker: ranker,
            apiKeyStore: keyStore
        )
        var config = AppConfig.default
        config.matugenBinaryPath = "/bin/sh"
        config.walBinaryPath = "/bin/sh"
        config.matugenTypeSafeEnabled = true

        _ = try await service.generate(
            sourceURL: context.sourceURL,
            inputURL: context.sourceURL,
            config: config
        )

        let colorsJSON = try Data(contentsOf: context.root.appendingPathComponent("wal/colors.json"))
        let colorsObject = try XCTUnwrap(JSONSerialization.jsonObject(with: colorsJSON) as? [String: Any])
        let colors = try XCTUnwrap(colorsObject["colors"] as? [String: String])
        let selected = await ranker.selectedColor(for: "color2")
        XCTAssertEqual(colors["color2"], selected)

        let manifest = try String(contentsOf: context.root.appendingPathComponent("wal/pywalpick-matugen-manifest.json"))
        XCTAssertFalse(manifest.contains("integration-secret"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.root.appendingPathComponent("wal/pywalpick-matugen-preferences.json").path))
    }

    func testRankerFailurePublishesTheDeterministicPalette() async throws {
        let context = try Self.makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let ranker = RecordingPreferenceRanker { _ in
            throw TypeSafeColorPreferenceError.invalidResponse
        }
        let service = MatugenThemeService(
            processRunner: context.runner,
            cacheRoot: context.root.appendingPathComponent("cache"),
            pywalCacheDirectory: context.root.appendingPathComponent("wal"),
            configDirectory: context.root.appendingPathComponent("config"),
            preferenceRanker: ranker,
            apiKeyStore: FixedTypeSafeAPIKeyStore(value: "integration-secret")
        )
        var config = AppConfig.default
        config.matugenBinaryPath = "/bin/sh"
        config.walBinaryPath = "/bin/sh"
        config.matugenTypeSafeEnabled = true

        do {
            _ = try await service.generate(
                sourceURL: context.sourceURL,
                inputURL: context.sourceURL,
                config: config
            )
        } catch {
            XCTFail("TypeSafe failure should fall back to local palette: \(error)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.root.appendingPathComponent("wal/colors").path))
    }

    func testInvalidRankerChoiceIsIgnoredAndNotStored() async throws {
        let context = try Self.makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let ranker = RecordingPreferenceRanker { _ in
            ["color2": "#ffffff", "color3": "#ffffff"]
        }
        let service = MatugenThemeService(
            processRunner: context.runner,
            cacheRoot: context.root.appendingPathComponent("cache"),
            pywalCacheDirectory: context.root.appendingPathComponent("wal"),
            configDirectory: context.root.appendingPathComponent("config"),
            preferenceRanker: ranker,
            apiKeyStore: FixedTypeSafeAPIKeyStore(value: "integration-secret")
        )
        var config = AppConfig.default
        config.matugenBinaryPath = "/bin/sh"
        config.walBinaryPath = "/bin/sh"
        config.matugenTypeSafeEnabled = true

        _ = try await service.generate(
            sourceURL: context.sourceURL,
            inputURL: context.sourceURL,
            config: config
        )

        let preferences = try String(
            contentsOf: context.root.appendingPathComponent("wal/pywalpick-matugen-preferences.json")
        )
        XCTAssertFalse(preferences.contains("#ffffff"))
    }

    func testChangingAPIKeyFingerprintInvalidatesPublishedPreferenceCache() async throws {
        let context = try Self.makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let keyStore = MutableTypeSafeAPIKeyStore(value: "first-secret")
        let ranker = RecordingPreferenceRanker { candidates in
            ["color2": candidates.choices["color2"]!.first!.hex]
        }
        let service = MatugenThemeService(
            processRunner: context.runner,
            cacheRoot: context.root.appendingPathComponent("cache"),
            pywalCacheDirectory: context.root.appendingPathComponent("wal"),
            configDirectory: context.root.appendingPathComponent("config"),
            preferenceRanker: ranker,
            apiKeyStore: keyStore
        )
        var config = AppConfig.default
        config.matugenBinaryPath = "/bin/sh"
        config.walBinaryPath = "/bin/sh"
        config.matugenTypeSafeEnabled = true

        let first = try await service.generate(sourceURL: context.sourceURL, inputURL: context.sourceURL, config: config)
        XCTAssertFalse(first.reused)
        let second = try await service.generate(sourceURL: context.sourceURL, inputURL: context.sourceURL, config: config)
        XCTAssertTrue(second.reused)

        keyStore.value = "second-secret"
        let third = try await service.generate(sourceURL: context.sourceURL, inputURL: context.sourceURL, config: config)
        XCTAssertFalse(third.reused)
        let rankerCallCount = await ranker.callCount
        XCTAssertEqual(rankerCallCount, 2)
    }

    private struct Context {
        let root: URL
        let sourceURL: URL
        let runner: RecordingThemeProcessRunner
    }

    private static func makeContext() throws -> Context {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pywalpick-preference-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("wallpaper.jpg")
        try Data("fixture".utf8).write(to: sourceURL)
        return Context(
            root: root,
            sourceURL: sourceURL,
            runner: RecordingThemeProcessRunner(matugenOutput: MatugenThemeTests.matugenFixture)
        )
    }
}

private actor RecordingPreferenceRanker: MatugenColorPreferenceRanking {
    private let behavior: @Sendable (MatugenThemeCandidateSet) throws -> [String: String]
    private var selections: [String: String] = [:]
    private(set) var callCount = 0

    init(behavior: @escaping @Sendable (MatugenThemeCandidateSet) throws -> [String: String]) {
        self.behavior = behavior
    }

    func rank(candidates: MatugenThemeCandidateSet, apiKey: String) async throws -> [String: String] {
        callCount += 1
        let result = try behavior(candidates)
        selections = result
        return result
    }

    func selectedColor(for slot: String) -> String? {
        selections[slot]
    }
}

private final class MutableTypeSafeAPIKeyStore: TypeSafeAPIKeyStoring, @unchecked Sendable {
    var value: String?

    init(value: String?) {
        self.value = value
    }

    func load() throws -> String? { value }
    func save(_ value: String) throws {}
    func remove() throws {}
}

private typealias FixedTypeSafeAPIKeyStore = MutableTypeSafeAPIKeyStore
