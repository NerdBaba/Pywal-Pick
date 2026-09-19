import Foundation
import XCTest
@testable import PywalPick

final class TypeSafeColorPreferenceClientTests: XCTestCase {
    func testRequestUsesBearerAuthAndStructuredChoiceQuestions() async throws {
        let transport = MockTypeSafeHTTPTransport(responses: [
            .success(Self.response(
                answers: [
                    "color1": Self.choiceAnswer(choice: "a", confidence: 0.92),
                    "cursor": Self.choiceAnswer(choice: "a", confidence: 0.88),
                ]
            ))
        ])
        let client = TypeSafeColorPreferenceClient(
            transport: transport,
            retryBaseDelay: 0.001
        )

        let result = try await client.rank(candidates: Self.candidates(), apiKey: "secret-key")
        XCTAssertEqual(result["color1"], "#cc3344")
        XCTAssertEqual(result["cursor"], "#4488cc")

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "jev-latest")
        let questions = try XCTUnwrap(object["questions"] as? [String: Any])
        XCTAssertNotNil(questions["color1"])
        XCTAssertNotNil(questions["cursor"])
        let state = try XCTUnwrap(object["state"] as? String)
        XCTAssertTrue(state.contains("1["))
        XCTAssertTrue(state.contains("#cc3344"))
        XCTAssertFalse(state.contains("wallpaperPath"))
        let color1 = try XCTUnwrap(questions["color1"] as? [String: Any])
        let criteria = try XCTUnwrap(color1["criteria"] as? [String: Any])
        XCTAssertLessThanOrEqual(criteria.count, 2)
    }

    func testRequestEstimateMatchesSerializedCompactPayload() async throws {
        let transport = MockTypeSafeHTTPTransport(responses: [
            .success(Self.response(answers: [:]))
        ])
        let client = TypeSafeColorPreferenceClient(
            transport: transport,
            retryBaseDelay: 0.001
        )

        let candidates = Self.candidates()
        _ = try await client.rank(candidates: candidates, apiKey: "secret-key")

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(
            TypeSafeColorPreferenceClient.estimatedRequestBytes(for: candidates),
            body.count
        )
        XCTAssertEqual(
            TypeSafeColorPreferenceClient.estimatedInputTokens(for: candidates),
            (body.count + 3) / 4
        )
    }

    func testDenseCompactRequestStaysBelow500EstimatedTokens() {
        let base = Self.candidates()
        let red = base.choices["color1"]!.first!
        let blue = base.cursorChoices.first!
        let slots = [
            "color1", "color2", "color3", "color4", "color5", "color6",
            "color8", "color9", "color10", "color11", "color12", "color13", "color14",
        ]
        let dense = MatugenThemeCandidateSet(
            mode: base.mode,
            schemeType: base.schemeType,
            background: base.background,
            foreground: base.foreground,
            choices: Dictionary(uniqueKeysWithValues: slots.map { ($0, [red, blue]) }),
            cursorChoices: [blue],
            localColors: base.localColors,
            localCursor: base.localCursor
        )

        XCTAssertLessThan(
            TypeSafeColorPreferenceClient.estimatedInputTokens(for: dense),
            500
        )
    }

    func testLowConfidenceAndUnknownChoicesAreIgnored() async throws {
        let transport = MockTypeSafeHTTPTransport(responses: [
            .success(Self.response(
                answers: [
                    "color1": Self.choiceAnswer(choice: "red", confidence: 0.44),
                    "cursor": Self.choiceAnswer(choice: "missing", confidence: 0.99),
                ]
            ))
        ])
        let client = TypeSafeColorPreferenceClient(transport: transport, retryBaseDelay: 0.001)

        let result = try await client.rank(candidates: Self.candidates(), apiKey: "secret-key")
        XCTAssertTrue(result.isEmpty)
    }

    func testRateLimitRetriesOnceThenAcceptsResponse() async throws {
        let transport = MockTypeSafeHTTPTransport(responses: [
            .success((Data("{}".utf8), Self.httpResponse(status: 429, data: Data("{}".utf8)))),
            .success(Self.response(
                answers: ["color1": Self.choiceAnswer(choice: "red", confidence: 0.8)]
            )),
        ])
        let client = TypeSafeColorPreferenceClient(transport: transport, retryBaseDelay: 0.001)

        let result = try await client.rank(candidates: Self.candidates(), apiKey: "secret-key")
        XCTAssertEqual(result["color1"], "#cc3344")
        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 2)
    }

    func testUnauthorizedResponseThrowsWithoutLeakingKey() async throws {
        let transport = MockTypeSafeHTTPTransport(responses: [
            .success((Data("invalid secret-key".utf8), Self.httpResponse(status: 401, data: Data("invalid secret-key".utf8))))
        ])
        let client = TypeSafeColorPreferenceClient(transport: transport, retryBaseDelay: 0.001)

        do {
            _ = try await client.rank(candidates: Self.candidates(), apiKey: "secret-key")
            XCTFail("Expected unauthorized response to throw")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("secret-key"))
        }
    }

    private static func candidates() -> MatugenThemeCandidateSet {
        let background = try! ThemeColor(hex: "#101010")
        let foreground = try! ThemeColor(hex: "#f0f0f0")
        let red = MatugenColorCandidate(
            id: "red", hex: "#cc3344", family: "error", tone: 60,
            contrast: 5.7, chroma: 0.6, nearExtreme: false
        )
        let blue = MatugenColorCandidate(
            id: "blue", hex: "#4488cc", family: "primary", tone: 60,
            contrast: 5.1, chroma: 0.53, nearExtreme: false
        )
        return MatugenThemeCandidateSet(
            mode: .dark,
            schemeType: .schemeTonalSpot,
            background: background,
            foreground: foreground,
            choices: ["color1": [red], "cursor": [blue]],
            cursorChoices: [blue],
            localColors: ["color1": red.hex],
            localCursor: blue.hex
        )
    }

    private static func choiceAnswer(choice: String, confidence: Double) -> [String: Any] {
        [
            "type": "choice",
            "choice": choice,
            "probabilities": [choice: confidence, "other": 1 - confidence],
            "confidence": confidence,
        ]
    }

    private static func response(answers: [String: [String: Any]]) -> (Data, HTTPURLResponse) {
        let object: [String: Any] = [
            "model": "jev-latest",
            "answers": answers,
            "usage": ["input_tokens": 10, "output_tokens": 10],
        ]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return (data, httpResponse(status: 200, data: data))
    }

    private static func httpResponse(status: Int, data: Data) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.typesafe.ai/v1/systemone")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}

private actor MockTypeSafeHTTPTransport: TypeSafeHTTPTransport {
    enum Response: Sendable {
        case success((Data, HTTPURLResponse))
        case failure(String)
    }

    private var responses: [Response]
    private(set) var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        switch responses.removeFirst() {
        case .success(let response):
            return response
        case .failure(let message):
            throw NSError(domain: "TypeSafeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
