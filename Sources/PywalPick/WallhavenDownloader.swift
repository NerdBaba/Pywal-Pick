import Foundation

struct DownloadProgress: Sendable {
    let bytesDownloaded: Int64
    let totalBytes: Int64

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesDownloaded) / Double(totalBytes)
    }
}

@MainActor
final class WallhavenDownloader: @unchecked Sendable {
    static let shared = WallhavenDownloader()

    private let session: URLSession
    private var activeDownloads: [String: URLSessionDataTask] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = [
            "User-Agent": "PywalPick/1.0 (macOS wallpaper switcher)"
        ]
        self.session = URLSession(configuration: config)
    }

    func download(
        wallpaper: WallhavenWallpaper,
        to destinationFolder: String,
        progressHandler: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        let destinationURL = buildDestinationURL(for: wallpaper, in: destinationFolder)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            progressHandler(DownloadProgress(bytesDownloaded: 1, totalBytes: 1))
            return destinationURL
        }

        guard let downloadURL = URL(string: wallpaper.path) else {
            throw WallhavenError.invalidResponse
        }

        return try await withCheckedThrowingContinuation { continuation in
            let task = self.session.dataTask(with: downloadURL) { data, response, error in
                if let error {
                    continuation.resume(throwing: WallhavenError.networkError(error.localizedDescription))
                    return
                }

                guard let data, !data.isEmpty else {
                    continuation.resume(throwing: WallhavenError.networkError("No data received"))
                    return
                }

                do {
                    try FileManager.default.createDirectory(
                        at: destinationURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try data.write(to: destinationURL, options: .atomic)
                    continuation.resume(returning: destinationURL)
                } catch {
                    continuation.resume(throwing: WallhavenError.networkError(error.localizedDescription))
                }

                Task { @MainActor in
                    self.activeDownloads.removeValue(forKey: wallpaper.id)
                }
            }

            self.activeDownloads[wallpaper.id] = task
            task.resume()
        }
    }

    func isDownloaded(wallpaperId: String, in folder: String) -> Bool {
        let folderURL = URL(fileURLWithPath: folder)
        let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent.hasPrefix("wallhaven-\(wallpaperId)") {
                return true
            }
        }
        return false
    }

    func findDownloadedFile(wallpaperId: String, in folder: String) -> URL? {
        let folderURL = URL(fileURLWithPath: folder)
        let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent.hasPrefix("wallhaven-\(wallpaperId)") {
                return fileURL
            }
        }
        return nil
    }

    func cancelDownload(_ wallpaperId: String) {
        activeDownloads[wallpaperId]?.cancel()
        activeDownloads.removeValue(forKey: wallpaperId)
    }

    func cancelAllDownloads() {
        for (_, task) in activeDownloads {
            task.cancel()
        }
        activeDownloads.removeAll()
    }

    private func buildDestinationURL(for wallpaper: WallhavenWallpaper, in folder: String) -> URL {
        let filename = "wallhaven-\(wallpaper.id).\(wallpaper.fileExtension)"
        return URL(fileURLWithPath: folder).appendingPathComponent(filename)
    }
}
