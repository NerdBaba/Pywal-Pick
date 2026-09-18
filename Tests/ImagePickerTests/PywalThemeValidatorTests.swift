import Foundation
import XCTest
@testable import PywalPick

final class PywalThemeValidatorTests: XCTestCase {
    func testRejectsUnreadableAnsiSlotBeforePublication() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = try writeTheme(
            directory: directory,
            background: "#101010",
            foreground: "#f0f0f0",
            slots: (0..<16).map { $0 == 1 ? "#111111" : "#f0f0f0" }
        )

        XCTAssertThrowsError(try PywalThemeValidator.validate(
            directory: directory,
            expectedScheme: expected,
            enforceStandardContrast: true
        )) { error in
            guard case PywalThemeValidationError.unreadableColor("color1", _, 4.5) = error else {
                return XCTFail("Expected color1 readability failure, got \(error)")
            }
        }
    }

    func testRejectsInvisibleGhosttySelection() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = try writeTheme(
            directory: directory,
            background: "#101010",
            foreground: "#f0f0f0",
            slots: Array(repeating: "#f0f0f0", count: 16)
        )
        try "background = #101010\nforeground = #f0f0f0\nselection-background = #101010\nselection-foreground = #f0f0f0\n".write(
            to: directory.appendingPathComponent("colors-ghostty"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try PywalThemeValidator.validate(
            directory: directory,
            expectedScheme: expected,
            enforceStandardContrast: true
        )) { error in
            guard case PywalThemeValidationError.invalidSchema(let message) = error,
                  message.contains("Ghostty selection") else {
                return XCTFail("Expected Ghostty selection failure, got \(error)")
            }
        }
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pywal-validator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeTheme(directory: URL, background: String, foreground: String, slots: [String]) throws -> Data {
        let colors = Dictionary(uniqueKeysWithValues: slots.enumerated().map { ("color\($0.offset)", $0.element) })
        let scheme: [String: Any] = [
            "wallpaper": "/fixture.jpg",
            "alpha": "100",
            "special": ["background": background, "foreground": foreground, "cursor": foreground],
            "colors": colors,
        ]
        let data = try JSONSerialization.data(withJSONObject: scheme)
        try data.write(to: directory.appendingPathComponent("colors.json"))
        try slots.joined(separator: "\n").appending("\n").write(
            to: directory.appendingPathComponent("colors"), atomically: true, encoding: .utf8
        )
        let shell = slots.enumerated().map { "color\($0.offset)='\($0.element)'" }.joined(separator: "\n") + "\n"
        try shell.write(to: directory.appendingPathComponent("colors.sh"), atomically: true, encoding: .utf8)
        return data
    }
}
