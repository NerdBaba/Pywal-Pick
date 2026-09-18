import Foundation
import CryptoKit
import XCTest

final class MatugenWallpaperMatrixTests: XCTestCase {
    func testOptInManifestIsReplayable() throws {
        guard let manifestPath = ProcessInfo.processInfo.environment["MATUGEN_AUDIT_MANIFEST"] else {
            throw XCTSkip("Set MATUGEN_AUDIT_MANIFEST to validate a real wallpaper audit manifest")
        }
        let url = URL(fileURLWithPath: manifestPath)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let wallpapers = try XCTUnwrap(object["wallpapers"] as? [[String: Any]])
        let schemes = try XCTUnwrap(object["schemes"] as? [String])
        let modes = try XCTUnwrap(object["modes"] as? [String])
        XCTAssertEqual(wallpapers.count, object["count"] as? Int)
        XCTAssertEqual(schemes.count, 9)
        XCTAssertEqual(modes, ["dark", "light"])
        XCTAssertEqual(object["contrast"] as? Double, 0)
        for wallpaper in wallpapers {
            let path = try XCTUnwrap(wallpaper["path"] as? String)
            let file = URL(fileURLWithPath: path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), path)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int,
                           wallpaper["size"] as? Int)
            let digest = try SHA256.file(at: file)
            XCTAssertEqual(digest, wallpaper["sha256"] as? String, path)
        }
    }
}

private enum SHA256 {
    static func file(at url: URL) throws -> String {
        CryptoKit.SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
}
