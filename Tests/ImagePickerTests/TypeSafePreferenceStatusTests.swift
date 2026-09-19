import Foundation
import XCTest
@testable import PywalPick

final class TypeSafePreferenceStatusTests: XCTestCase {
    func testSummaryIdentifiesRankedSlotsAndEstimatedTokens() {
        let status = TypeSafePreferenceStatus(
            outcome: .ranked,
            timestamp: Date(timeIntervalSince1970: 0),
            selectedColors: ["color2": "#4488cc", "cursor": "#66bb99"],
            requestByteCount: 12_000,
            estimatedInputTokens: 3_000
        )

        XCTAssertEqual(status.summary, "TypeSafe ranked 2 slots · ~3,000 input tokens")
    }

    func testStatusStoreRoundTripsOnlySanitizedRunData() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("typesafe-status-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TypeSafePreferenceStatusStore(fileURL: url)
        let status = TypeSafePreferenceStatus(
            outcome: .fallback,
            selectedColors: [:],
            requestByteCount: 800,
            estimatedInputTokens: 200
        )

        try store.save(status)

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.outcome, status.outcome)
        XCTAssertEqual(loaded.selectedColors, status.selectedColors)
        XCTAssertEqual(loaded.requestByteCount, status.requestByteCount)
        XCTAssertEqual(loaded.estimatedInputTokens, status.estimatedInputTokens)
        XCTAssertEqual(
            loaded.timestamp.timeIntervalSince1970,
            status.timestamp.timeIntervalSince1970,
            accuracy: 1
        )
        let raw = try String(contentsOf: url)
        XCTAssertFalse(raw.contains("api-key"))
        XCTAssertFalse(raw.contains("wallpaper"))
    }
}
