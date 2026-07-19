import XCTest
@testable import PywalPick

final class TransitionTypeTests: XCTestCase {
    func testCodableRoundTrip() throws {
        for type in TransitionType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(TransitionType.self, from: data)
            XCTAssertEqual(decoded, type, "\(type) should survive encode/decode")
        }
    }

    func testResolvedIsConcrete() {
        XCTAssertEqual(TransitionType.fade.resolved, .fade)
        XCTAssertEqual(TransitionType.wipe.resolved, .wipe)
        XCTAssertEqual(TransitionType.grow.resolved, .grow)

        let resolved = TransitionType.random.resolved
        XCTAssertTrue(
            [.fade, .wipe, .grow].contains(resolved),
            "random should resolve to a concrete effect")
    }

    func testConfigDefaults() {
        let config = AppConfig.default
        XCTAssertEqual(config.transitionType, .fade)
        XCTAssertEqual(config.transitionDuration, 1.0)
        XCTAssertEqual(config.transitionFPS, 60)
    }

    func testConfigTransitionFieldsCodable() throws {
        var config = AppConfig.default
        config.transitionType = .grow
        config.transitionDuration = 2.5
        config.transitionFPS = 30

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded.transitionType, .grow)
        XCTAssertEqual(decoded.transitionDuration, 2.5)
        XCTAssertEqual(decoded.transitionFPS, 30)
    }
}
