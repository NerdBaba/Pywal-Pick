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

    // Matugen has already filtered for contrast and extremes and sorted by
    // tone, so two nearby candidates preserve a safe local fallback while
    // giving TypeSafe a meaningful aesthetic choice.
    private static let maximumOptionsPerQuestion = 2

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
        let preparedRequest = try makeRequestBody(candidates: candidates)
        request.httpBody = preparedRequest.data

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
                return try acceptedChoices(
                    from: data,
                    candidates: candidates,
                    optionIDs: preparedRequest.optionIDs
                )
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
        (try? makeRequestBody(candidates: candidates, model: "jev-latest").data.count) ?? 0
    }

    static func estimatedInputTokens(for candidates: MatugenThemeCandidateSet) -> Int {
        let bytes = estimatedRequestBytes(for: candidates)
        return (bytes + 3) / 4
    }

    private struct PreparedRequest: Sendable {
        let data: Data
        let optionIDs: [String: [String: String]]
    }

    private struct RequestBody: Encodable {
        let state: String
        let model: String
        let questions: [String: Question]
    }

    private struct CompactOption: Sendable {
        let key: String
        let candidate: MatugenColorCandidate
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

    private func makeRequestBody(candidates: MatugenThemeCandidateSet) throws -> PreparedRequest {
        try Self.makeRequestBody(candidates: candidates, model: model)
    }

    private static func makeRequestBody(
        candidates: MatugenThemeCandidateSet,
        model: String
    ) throws -> PreparedRequest {
        var questions: [String: Question] = [:]
        var optionIDs: [String: [String: String]] = [:]
        var compactOptions: [String: [CompactOption]] = [:]

        for slot in candidates.choices.keys.sorted() {
            guard let options = candidates.choices[slot] else { continue }
            let selected = options.prefix(maximumOptionsPerQuestion).enumerated().map { index, option in
                CompactOption(key: compactOptionKey(index), candidate: option)
            }
            compactOptions[slot] = selected
            questions[slot] = Question(
                instructions: "Readable \(compactSlotName(slot))?",
                criteria: Dictionary(uniqueKeysWithValues: selected.map { ($0.key, "") })
            )
            optionIDs[slot] = Dictionary(uniqueKeysWithValues: selected.map { ($0.key, $0.candidate.id) })
        }

        let selectedCursor = candidates.cursorChoices.prefix(maximumOptionsPerQuestion).enumerated().map { index, option in
            CompactOption(key: compactOptionKey(index), candidate: option)
        }
        questions["cursor"] = Question(
            instructions: "Readable x?",
            criteria: Dictionary(uniqueKeysWithValues: selectedCursor.map { ($0.key, "") })
        )
        compactOptions["cursor"] = selectedCursor
        optionIDs["cursor"] = Dictionary(uniqueKeysWithValues: selectedCursor.map { ($0.key, $0.candidate.id) })

        let state = compactState(candidates: candidates, options: compactOptions)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return PreparedRequest(
                data: try encoder.encode(RequestBody(state: state, model: model, questions: questions)),
                optionIDs: optionIDs
            )
        } catch {
            throw TypeSafeColorPreferenceError.decoding(error.localizedDescription)
        }
    }

    private static func compactOptionKey(_ index: Int) -> String {
        String(UnicodeScalar(97 + index)!)
    }

    private static func compactState(
        candidates: MatugenThemeCandidateSet,
        options: [String: [CompactOption]]
    ) -> String {
        let slotDescriptions = options.keys.sorted().compactMap { slot -> String? in
            guard let choices = options[slot], !choices.isEmpty else { return nil }
            let values = choices.map { option in
                return "\(option.key)=\(option.candidate.hex)"
            }
            return "\(compactSlotName(slot))[\(values.joined(separator: ","))]"
        }

        return [
            "theme=\(candidates.mode.rawValue)/\(candidates.schemeType.rawValue)",
            "bg=\(candidates.background.hex)",
            "fg=\(candidates.foreground.hex)",
            "roles=e:error,t:tertiary,s:secondary,p:primary,n:neutral slots=1e,2t,3s,4p,5s,6t,8n,9e,10t,11s,12p,13s,14t,xp",
            "fmt=id=hex",
            "safe=contrast>=4.5",
            slotDescriptions.joined(separator: ";"),
        ]
        .joined(separator: " ")
    }

    private static func compactSlotName(_ slot: String) -> String {
        if slot == "cursor" {
            return "x"
        }
        return String(slot.dropFirst("color".count))
    }

    private func acceptedChoices(
        from data: Data,
        candidates: MatugenThemeCandidateSet,
        optionIDs: [String: [String: String]]
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

            let candidateID = optionIDs[slot]?[choice] ?? choice
            if slot == "cursor" {
                if let candidate = candidates.cursorChoices.first(where: { $0.id == candidateID }) {
                    accepted[slot] = candidate.hex
                }
            } else if let candidate = candidates.choices[slot]?.first(where: { $0.id == candidateID }) {
                accepted[slot] = candidate.hex
            }
        }
        return candidates.acceptedPreferences(accepted)
    }
}
