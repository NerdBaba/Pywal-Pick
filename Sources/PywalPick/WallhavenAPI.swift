import Foundation

protocol WallhavenSearching: Sendable {
    func search(params: WallhavenSearchParams, apiKey: String?) async throws -> WallhavenSearchResponse
}

actor WallhavenAPI: WallhavenSearching {
    static let shared = WallhavenAPI()

    private let session: URLSession
    private let baseURL = "https://wallhaven.cc/api/v1"
    private var lastRequestTime: Date = .distantPast
    private let minRequestInterval: TimeInterval = 1.5

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "PywalPick/1.0 (macOS wallpaper switcher; https://github.com/ozone-oasis/wal-pick)"
        ]
        self.session = URLSession(configuration: config)
    }

    func search(params: WallhavenSearchParams, apiKey: String?) async throws -> WallhavenSearchResponse {
        try await rateLimit()

        guard var components = URLComponents(string: "\(baseURL)/search") else {
            throw WallhavenError.invalidResponse
        }
        components.queryItems = params.buildQueryItems()

        guard let url = components.url else {
            throw WallhavenError.invalidResponse
        }

        var request = URLRequest(url: url)
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw WallhavenError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WallhavenError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(WallhavenSearchResponse.self, from: data)
            } catch {
                throw WallhavenError.decodingError(error.localizedDescription)
            }
        case 401:
            throw WallhavenError.unauthorized
        case 429:
            throw WallhavenError.rateLimited
        default:
            throw WallhavenError.httpError(httpResponse.statusCode)
        }
    }

    private func rateLimit() async throws {
        let elapsed = Date().timeIntervalSince(lastRequestTime)
        if elapsed < minRequestInterval {
            let waitTime = minRequestInterval - elapsed
            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
        lastRequestTime = Date()
    }
}
