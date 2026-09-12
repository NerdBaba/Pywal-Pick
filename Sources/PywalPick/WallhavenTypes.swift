import Foundation
import SwiftUI

// MARK: - API Response Models

struct WallhavenSearchResponse: Codable, Sendable {
    let data: [WallhavenWallpaper]
    let meta: WallhavenMeta
}

struct WallhavenWallpaper: Codable, Sendable, Identifiable {
    let id: String
    let url: String
    let shortUrl: String
    let views: Int
    let favorites: Int
    let source: String?
    let purity: String
    let category: String
    let dimensionX: Int
    let dimensionY: Int
    let resolution: String
    let ratio: String
    let fileSize: Int
    let fileType: String
    let createdAt: String
    let colors: [String]
    let path: String
    let thumbs: WallhavenThumbs

    enum CodingKeys: String, CodingKey {
        case id, url, views, favorites, source, purity, category
        case dimensionX = "dimension_x"
        case dimensionY = "dimension_y"
        case resolution, ratio
        case fileSize = "file_size"
        case fileType = "file_type"
        case createdAt = "created_at"
        case colors, path, thumbs
        case shortUrl = "short_url"
    }

    var purityEnum: WallhavenPurity {
        WallhavenPurity(rawValue: purity) ?? .sfw
    }

    var categoryEnum: WallhavenCategory {
        WallhavenCategory(rawValue: category) ?? .general
    }

    var fileExtension: String {
        if fileType.contains("png") { return "png" }
        if fileType.contains("jpeg") || fileType.contains("jpg") { return "jpg" }
        if fileType.contains("webp") { return "webp" }
        return "jpg"
    }

    var aspectRatio: Double {
        guard dimensionY > 0 else { return 16.0 / 9.0 }
        return Double(dimensionX) / Double(dimensionY)
    }
}

struct WallhavenThumbs: Codable, Sendable {
    let large: String
    let original: String
    let small: String
}

struct WallhavenMeta: Codable, Sendable {
    let currentPage: Int
    let lastPage: Int
    let perPage: Int
    let total: Int
    let query: WallhavenQuery?
    let seed: String?

    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case lastPage = "last_page"
        case perPage = "per_page"
        case total, query, seed
    }
}

struct WallhavenQuery: Codable, Sendable {
    let id: Int?
    let tag: String?
}

struct WallhavenCollection: Codable, Sendable, Identifiable {
    let id: Int
    let label: String
    let views: Int
    let `public`: Int
    let count: Int
}

// MARK: - Enums

enum WallhavenPurity: String, Codable, CaseIterable, Sendable, Identifiable {
    case sfw = "sfw"
    case sketchy = "sketchy"
    case nsfw = "nsfw"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sfw: return "SFW"
        case .sketchy: return "Sketchy"
        case .nsfw: return "NSFW"
        }
    }

    var icon: String {
        switch self {
        case .sfw: return "checkmark.shield.fill"
        case .sketchy: return "exclamationmark.shield.fill"
        case .nsfw: return "xmark.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .sfw: return .green
        case .sketchy: return .orange
        case .nsfw: return .red
        }
    }
}

enum WallhavenCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case general = "general"
    case anime = "anime"
    case people = "people"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return "General"
        case .anime: return "Anime"
        case .people: return "People"
        }
    }

    var icon: String {
        switch self {
        case .general: return "photo.on.rectangle"
        case .anime: return "tv"
        case .people: return "person.2"
        }
    }
}

enum WallhavenRatio: String, Codable, CaseIterable, Sendable, Identifiable {
    case ratio16x9 = "16x9"
    case ratio16x10 = "16x10"
    case ratio4x3 = "4x3"
    case ratio5x4 = "5x4"
    case ratio21x9 = "21x9"
    case ratio32x9 = "32x9"
    case ratio1x1 = "1x1"
    case ratio3x2 = "3x2"
    case ratio4x5 = "4x5"
    case ratio9x16 = "9x16"
    case ratio9x18 = "9x18"
    case ratio48x9 = "48x9"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ratio16x9: return "16:9"
        case .ratio16x10: return "16:10"
        case .ratio4x3: return "4:3"
        case .ratio5x4: return "5:4"
        case .ratio21x9: return "21:9"
        case .ratio32x9: return "32:9"
        case .ratio1x1: return "1:1"
        case .ratio3x2: return "3:2"
        case .ratio4x5: return "4:5"
        case .ratio9x16: return "9:16"
        case .ratio9x18: return "9:18"
        case .ratio48x9: return "48:9"
        }
    }

    var ratioString: String {
        rawValue
    }
}

enum WallhavenSorting: String, CaseIterable, Sendable, Identifiable {
    case dateAdded = "date_added"
    case relevance = "relevance"
    case random = "random"
    case views = "views"
    case favorites = "favorites"
    case toplist = "toplist"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dateAdded: return "Date Added"
        case .relevance: return "Relevance"
        case .random: return "Random"
        case .views: return "Views"
        case .favorites: return "Favorites"
        case .toplist: return "Toplist"
        }
    }
}

enum WallhavenRelevanceSorting: String, CaseIterable, Sendable, Identifiable {
    case relevance = "relevance"
    case dateAdded = "date_added"
    case random = "random"
    case views = "views"
    case favorites = "favorites"
    case toplist = "toplist"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .relevance: return "Relevance"
        case .dateAdded: return "Date Added"
        case .random: return "Random"
        case .views: return "Views"
        case .favorites: return "Favorites"
        case .toplist: return "Toplist"
        }
    }
}

enum WallhavenToplistRange: String, CaseIterable, Sendable, Identifiable {
    case oneDay = "1d"
    case threeDays = "3d"
    case oneWeek = "1w"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1y"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oneDay: return "1 Day"
        case .threeDays: return "3 Days"
        case .oneWeek: return "1 Week"
        case .oneMonth: return "1 Month"
        case .threeMonths: return "3 Months"
        case .sixMonths: return "6 Months"
        case .oneYear: return "1 Year"
        }
    }
}

enum WallhavenColor: String, CaseIterable, Sendable, Identifiable {
    case red = "660000"
    case darkRed = "990000"
    case brightRed = "cc0000"
    case rose = "cc3333"
    case pink = "ea4c88"
    case purple = "993399"
    case deepPurple = "663399"
    case indigo = "333399"
    case blue = "0066cc"
    case cyan = "0099cc"
    case teal = "66cccc"
    case green = "77cc33"
    case olive = "669900"
    case darkGreen = "336600"
    case darkOlive = "666600"
    case yellowGreen = "999900"
    case lime = "cccc33"
    case yellow = "ffff00"
    case gold = "ffcc33"
    case orange = "ff9900"
    case darkOrange = "ff6600"
    case brown = "cc6633"
    case tan = "996633"
    case darkBrown = "663300"
    case black = "000000"
    case gray = "999999"
    case silver = "cccccc"
    case white = "ffffff"
    case slate = "424153"

    var id: String { rawValue }

    var color: Color {
        let r = Double(Int(rawValue.prefix(2), radix: 16) ?? 0) / 255.0
        let g = Double(Int(rawValue.dropFirst(2).prefix(2), radix: 16) ?? 0) / 255.0
        let b = Double(Int(rawValue.suffix(2), radix: 16) ?? 0) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    var displayName: String {
        switch self {
        case .red: return "Red"
        case .darkRed: return "Dark Red"
        case .brightRed: return "Bright Red"
        case .rose: return "Rose"
        case .pink: return "Pink"
        case .purple: return "Purple"
        case .deepPurple: return "Deep Purple"
        case .indigo: return "Indigo"
        case .blue: return "Blue"
        case .cyan: return "Cyan"
        case .teal: return "Teal"
        case .green: return "Green"
        case .olive: return "Olive"
        case .darkGreen: return "Dark Green"
        case .darkOlive: return "Dark Olive"
        case .yellowGreen: return "Yellow Green"
        case .lime: return "Lime"
        case .yellow: return "Yellow"
        case .gold: return "Gold"
        case .orange: return "Orange"
        case .darkOrange: return "Dark Orange"
        case .brown: return "Brown"
        case .tan: return "Tan"
        case .darkBrown: return "Dark Brown"
        case .black: return "Black"
        case .gray: return "Gray"
        case .silver: return "Silver"
        case .white: return "White"
        case .slate: return "Slate"
        }
    }
}

// MARK: - Search Parameters

struct WallhavenSearchParams: Sendable {
    var query: String = ""
    var categories: Set<WallhavenCategory> = [.general, .anime, .people]
    var purity: Set<WallhavenPurity> = [.sfw]
    var sorting: WallhavenSorting = .dateAdded
    var order: String = "desc"
    var topRange: WallhavenToplistRange = .oneMonth
    var atLeast: String? = nil
    var resolutions: [String] = []
    var ratios: [String] = []
    var color: WallhavenColor? = nil
    var page: Int = 1
    var seed: String? = nil
    var relevanceSorting: WallhavenRelevanceSorting? = nil

    func buildQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []

        if !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }

        let catString = [
            categories.contains(.general) ? "1" : "0",
            categories.contains(.anime) ? "1" : "0",
            categories.contains(.people) ? "1" : "0"
        ].joined()
        items.append(URLQueryItem(name: "categories", value: catString))

        let purityString = [
            purity.contains(.sfw) ? "1" : "0",
            purity.contains(.sketchy) ? "1" : "0",
            purity.contains(.nsfw) ? "1" : "0"
        ].joined()
        items.append(URLQueryItem(name: "purity", value: purityString))

        items.append(URLQueryItem(name: "sorting", value: sorting.rawValue))
        items.append(URLQueryItem(name: "order", value: order))

        if sorting == .toplist {
            items.append(URLQueryItem(name: "topRange", value: topRange.rawValue))
        }

        if let atLeast, !atLeast.isEmpty {
            items.append(URLQueryItem(name: "atleast", value: atLeast))
        }

        if !resolutions.isEmpty {
            items.append(URLQueryItem(name: "resolutions", value: resolutions.joined(separator: ",")))
        }

        if !ratios.isEmpty {
            items.append(URLQueryItem(name: "ratios", value: ratios.joined(separator: ",")))
        }

        if let relevanceSorting {
            items.append(URLQueryItem(name: "sorting", value: relevanceSorting.rawValue))
        }

        if let color {
            items.append(URLQueryItem(name: "colors", value: color.rawValue))
        }

        if page > 1 {
            items.append(URLQueryItem(name: "page", value: String(page)))
        }

        if let seed, !seed.isEmpty {
            items.append(URLQueryItem(name: "seed", value: seed))
        }

        return items
    }
}

// MARK: - Errors

enum WallhavenError: LocalizedError, Sendable {
    case invalidResponse
    case unauthorized
    case rateLimited
    case httpError(Int)
    case networkError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Invalid API key or NSFW content requires authentication"
        case .rateLimited:
            return "Rate limit exceeded. Please wait a moment."
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let message):
            return "Failed to parse response: \(message)"
        }
    }
}
