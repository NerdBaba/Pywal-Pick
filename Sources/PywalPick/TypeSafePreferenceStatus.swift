import Foundation

public enum TypeSafePreferenceOutcome: String, Codable, Sendable, Equatable {
    case disabled
    case ranked
    case fallback
    case cacheReused

    public var displayName: String {
        switch self {
        case .disabled:
            return "TypeSafe disabled"
        case .ranked:
            return "TypeSafe ranked"
        case .fallback:
            return "Local fallback"
        case .cacheReused:
            return "Cached palette reused"
        }
    }
}

public struct TypeSafePreferenceStatus: Codable, Sendable, Equatable {
    public let outcome: TypeSafePreferenceOutcome
    public let timestamp: Date
    public let selectedColors: [String: String]
    public let requestByteCount: Int
    public let estimatedInputTokens: Int

    public init(
        outcome: TypeSafePreferenceOutcome,
        timestamp: Date = Date(),
        selectedColors: [String: String] = [:],
        requestByteCount: Int = 0,
        estimatedInputTokens: Int = 0
    ) {
        self.outcome = outcome
        self.timestamp = timestamp
        self.selectedColors = selectedColors
        self.requestByteCount = max(0, requestByteCount)
        self.estimatedInputTokens = max(0, estimatedInputTokens)
    }

    public var summary: String {
        var result = "\(outcome.displayName) \(selectedColors.count) slot"
        if selectedColors.count != 1 {
            result += "s"
        }
        if estimatedInputTokens > 0 {
            result += " · ~\(estimatedInputTokens.formatted()) input tokens"
        }
        return result
    }
}

public protocol TypeSafePreferenceStatusStoring: Sendable {
    func load() -> TypeSafePreferenceStatus?
    func save(_ status: TypeSafePreferenceStatus) throws
}

public struct TypeSafePreferenceStatusStore: TypeSafePreferenceStatusStoring, Sendable {
    public static let shared = TypeSafePreferenceStatusStore()

    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }

        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        self.fileURL = supportDirectory
            .appendingPathComponent("PywalPick/Matugen", isDirectory: true)
            .appendingPathComponent("typesafe-last-result.json")
    }

    public func load() -> TypeSafePreferenceStatus? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TypeSafePreferenceStatus.self, from: data)
    }

    public func save(_ status: TypeSafePreferenceStatus) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(status).write(to: fileURL, options: .atomic)
    }
}
