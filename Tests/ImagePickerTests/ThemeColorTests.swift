import XCTest
@testable import PywalPick

final class ThemeColorTests: XCTestCase {
    func testReferenceContrast() throws {
        let black = try ThemeColor(hex: "#000000")
        let white = try ThemeColor(hex: "#ffffff")
        XCTAssertEqual(black.contrastRatio(to: white), 21, accuracy: 0.000001)
        XCTAssertEqual(white.contrastRatio(to: white), 1, accuracy: 0.000001)
        XCTAssertLessThan(try ThemeColor(hex: "#777777").contrastRatio(to: white), 4.5)
        XCTAssertGreaterThan(try ThemeColor(hex: "#767676").contrastRatio(to: white), 4.5)
    }

    func testNormalizesHexAndRejectsUnsupportedValues() throws {
        XCTAssertEqual(try ThemeColor(hex: "  AABBcc ").hex, "#aabbcc")
        for value in ["#fff", "#fffffff", "#gggggg", "#１２３４５６", "rgba(0,0,0,1)"] {
            XCTAssertThrowsError(try ThemeColor(hex: value), value)
        }
    }

    func testContrastIsSymmetric() throws {
        let first = try ThemeColor(hex: "#112233")
        let second = try ThemeColor(hex: "#ddeeff")
        XCTAssertEqual(first.contrastRatio(to: second), second.contrastRatio(to: first), accuracy: 0.000001)
    }
}
