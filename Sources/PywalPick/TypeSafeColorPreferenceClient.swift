import Foundation

public protocol TypeSafeHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionTypeSafeTransport: TypeSafeHTTPTransport, Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.httpAdditionalHeaders = [
            "User-Agent": "PywalPick/1.0 (macOS wallpaper switcher)"
        ]
        self.session = URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public protocol MatugenColorPreferenceRanking: Sendable {
    func rank(
        candidates: MatugenThemeCandidateSet,
        apiKey: String
    ) async throws -> [String: String]
}

public enum TypeSafeColorPreferenceError: LocalizedError, Sendable, Equatable {
    case missingAPIKey
    case invalidEndpoint
    case invalidResponse
    case unauthorized
    case httpStatus(Int)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "TypeSafe API key is not configured."
        case .invalidEndpoint:
            return "TypeSafe endpoint is invalid."
        case .invalidResponse:
            return "TypeSafe returned an invalid response."
        case .unauthorized:
            return "TypeSafe rejected the configured API key."
        case .httpStatus(let status):
            return "TypeSafe returned HTTP status \(status)."
        case .decoding(let message):
            return "TypeSafe returned an unreadable answer: \(message)"
        }
    }
}

public struct TypeSafeColorPreferenceClient: MatugenColorPreferenceRanking, Sendable {
    public static let shared = TypeSafeColorPreferenceClient()

    private let transport: any TypeSafeHTTPTransport
    private let endpoint: URL
    private let model: String
    private let retryBaseDelay: TimeInterval
    private let minimumConfidence = 0.45

    public init(
        transport: any TypeSafeHTTPTransport = URLSessionTypeSafeTransport(),
        endpoint: URL = URL(string: "https://api.typesafe.ai/v1/systemone")!,
        model: String = "jev-latest",
        retryBaseDelay: TimeInterval = 0.25
    ) {
        self.transport = transport
        self.endpoint = endpoint
        self.model = model
        self.retryBaseDelay = max(0, retryBaseDelay)
    }

    public func rank(
        candidates: MatugenThemeCandidateSet,
        apiKey: String
    ) async throws -> [String: String] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw TypeSafeColorPreferenceError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeRequestBody(candidates: candidates)

        for attempt in 0..<3 {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await transport.data(for: request)
            } catch {
                throw TypeSafeColorPreferenceError.invalidResponse
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TypeSafeColorPreferenceError.invalidResponse
            }
            switch httpResponse.statusCode {
            case 200..<300:
                return try acceptedChoices(from: data, candidates: candidates)
            case 401:
                throw TypeSafeColorPreferenceError.unauthorized
            case 429, 529:
                guard attempt < 2 else {
                    throw TypeSafeColorPreferenceError.httpStatus(httpResponse.statusCode)
                }
                let delay = retryBaseDelay * pow(2, Double(attempt))
                if delay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            default:
                throw TypeSafeColorPreferenceError.httpStatus(httpResponse.statusCode)
            }
        }

        throw TypeSafeColorPreferenceError.invalidResponse
    }

    static func estimatedRequestBytes(for candidates: MatugenThemeCandidateSet) -> Int {
        (try? makeRequestBody(candidates: candidates, model: "jev-latest").count) ?? 0
    }

    static func estimatedInputTokens(for candidates: MatugenThemeCandidateSet) -> Int {
        let bytes = estimatedRequestBytes(for: candidates)
        return (bytes + 3) / 4
    }

    private struct RequestBody: Encodable {
        let state: State
        let model: String
        let questions: [String: Question]
    }

    private struct State: Encodable {
        let purpose: String
        let mode: String
        let scheme: String
        let background: String
        let foreground: String
    }

    private struct Question: Encodable {
        let type = "choice"
        let instructions: String
        let criteria: [String: String]
    }

    private struct ResponseBody: Decodable {
        let answers: [String: Answer]
    }

    private struct Answer: Decodable {
        let type: String
        let choice: String?
        let confidence: Double?
    }

    private func makeRequestBody(candidates: MatugenThemeCandidateSet) throws -> Data {
        try Self.makeRequestBody(candidates: candidates, model: model)
    }

    private static func makeRequestBody(
        candidates: MatugenThemeCandidateSet,
        model: String
    ) throws -> Data {
        var questions: [String: Question] = [:]
        for (slot, options) in candidates.choices {
            questions[slot] = Question(
                instructions: "Pick the safest readable color for \(slot).",
                criteria: criteria(for: options)
            )
        }
        questions["cursor"] = Question(
            instructions: "Pick the safest readable cursor color.",
            criteria: criteria(for: candidates.cursorChoices)
        )

        let state = State(
            purpose: "Choose only supplied safe colors for a terminal/browser theme.",
            mode: candidates.mode.rawValue,
            scheme: candidates.schemeType.rawValue,
            background: candidates.background.hex,
            foreground: candidates.foreground.hex
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(RequestBody(state: state, model: model, questions: questions))
        } catch {
            throw TypeSafeColorPreferenceError.decoding(error.localizedDescription)
        }
    }

    private static func criteria(for options: [MatugenColorCandidate]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: options.map { option in
            let tone = option.tone.map { String(format: "%.0f", $0) } ?? "semantic"
            let contrast = String(format: "%.1f", option.contrast)
            let chroma = String(format: "%.2f", option.chroma)
            return (
                option.id,
                "\(option.hex) \(option.family) t:\(tone) c:\(contrast) h:\(chroma)"
            )
        })
    }

    private func acceptedChoices(
        from data: Data,
        candidates: MatugenThemeCandidateSet
    ) throws -> [String: String] {
        let response: ResponseBody
        do {
            response = try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw TypeSafeColorPreferenceError.decoding(error.localizedDescription)
        }

        var accepted: [String: String] = [:]
        for (slot, answer) in response.answers {
            guard answer.type == "choice",
                  let choice = answer.choice,
                  let confidence = answer.confidence,
                  confidence >= minimumConfidence
            else { continue }

            if slot == "cursor" {
                if let candidate = candidates.cursorChoices.first(where: { $0.id == choice }) {
                    accepted[slot] = candidate.hex
                }
            } else if let candidate = candidates.choices[slot]?.first(where: { $0.id == choice }) {
                accepted[slot] = candidate.hex
            }
        }
        return candidates.acceptedPreferences(accepted)
    }
}
