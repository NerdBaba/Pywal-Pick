import Foundation
import XCTest
@testable import PywalPick

final class TypeSafeAPIKeyStoreTests: XCTestCase {
    func testTypeSafeSettingDefaultsOffAndLegacyConfigUsesIt() throws {
        XCTAssertFalse(AppConfig.default.matugenTypeSafeEnabled)

        let legacy = Data("{\"wallpaperFolderPath\":\"/tmp/walls\"}".utf8)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: legacy)
        XCTAssertFalse(decoded.matugenTypeSafeEnabled)
    }

    func testKeyStoreRoundTripAndRemovalContract() throws {
        let store = InMemoryTypeSafeAPIKeyStore()
        XCTAssertNil(try store.load())

        try store.save("test-secret")
        XCTAssertEqual(try store.load(), "test-secret")

        try store.remove()
        XCTAssertNil(try store.load())
    }

    func testAPIKeyIsNotEncodedInAppConfig() throws {
        let data = try JSONEncoder().encode(AppConfig.default)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["typeSafeAPIKey"])
        XCTAssertNil(object["matugenTypeSafeAPIKey"])
    }
}

private final class InMemoryTypeSafeAPIKeyStore: TypeSafeAPIKeyStoring, @unchecked Sendable {
    private var value: String?

    func load() throws -> String? { value }

    func save(_ value: String) throws {
        self.value = value
    }

    func remove() throws {
        value = nil
    }
}
