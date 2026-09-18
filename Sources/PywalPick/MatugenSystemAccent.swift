import Foundation

public enum MatugenSystemAccentError: LocalizedError, Sendable {
    case missingPalette(URL)

    public var errorDescription: String? {
        switch self {
        case .missingPalette(let url):
            return "Matugen palette is missing at \(url.path)."
        }
    }
}

public enum MatugenSystemAccent {
    public static func primary(in directory: URL, mode: MatugenMode) throws -> String {
        let url = directory.appendingPathComponent(MatugenPaletteCache.rawColorsFileName)
        guard let data = try? Data(contentsOf: url) else {
            throw MatugenSystemAccentError.missingPalette(url)
        }
        return try MatugenThemeConverter.materialAccent(from: data, mode: mode).primary
    }
}
