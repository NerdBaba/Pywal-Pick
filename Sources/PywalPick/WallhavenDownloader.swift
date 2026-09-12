import Foundation

struct DownloadProgress: Sendable {
    let bytesDownloaded: Int64
    let totalBytes: Int64

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesDownloaded) / Double(totalBytes)
    }
}

final class WallhavenDownloadState: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destinationURL: URL
    let progressHandler: (@Sendable (DownloadProgress) -> Void)?
    var continuation: CheckedContinuation<URL, Error>?

    init(
        destinationURL: URL,
        progressHandler: (@Sendable (DownloadProgress) -> Void)?
    ) {
        self.destinationURL = destinationURL
        self.progressHandler = progressHandler
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progressHandler?(DownloadProgress(bytesDownloaded: totalBytesWritten, totalBytes: totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let continuation else { return }
        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            continuation.resume(returning: destinationURL)
        } catch {
            continuation.resume(throwing: WallhavenError.networkError(error.localizedDescription))
        }
        self.continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let continuation else { return }
        if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                continuation.resume(throwing: CancellationError())
            } else {
                continuation.resume(throwing: WallhavenError.networkError(error.localizedDescription))
            }
            self.continuation = nil
        }
    }
}

@MainActor
final class WallhavenDownloader: @unchecked Sendable {
    static let shared = WallhavenDownloader()

    private var sessions: [String: URLSession] = [:]
    private var states: [String: WallhavenDownloadState] = [:]
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]

    private init() {}

    private static func makeSession(delegate: WallhavenDownloadState) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = [
            "User-Agent": "PywalPick/1.0 (macOS wallpaper switcher)"
        ]
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    func download(
        wallpaper: WallhavenWallpaper,
        to destinationFolder: String,
        progressHandler: (@Sendable (DownloadProgress) -> Void)? = nil
    ) async throws -> URL {
        let destinationURL = buildDestinationURL(for: wallpaper, in: destinationFolder)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            progressHandler?(DownloadProgress(bytesDownloaded: 1, totalBytes: 1))
            return destinationURL
        }

        guard let downloadURL = URL(string: wallpaper.path) else {
            throw WallhavenError.invalidResponse
        }

        cancelDownload(wallpaper.id)

        let state = WallhavenDownloadState(
            destinationURL: destinationURL,
            progressHandler: progressHandler
        )
        let session = Self.makeSession(delegate: state)
        sessions[wallpaper.id] = session
        states[wallpaper.id] = state

        do {
            return try await withCheckedThrowingContinuation { continuation in
                state.continuation = continuation
                let task = session.downloadTask(with: downloadURL)
                self.activeDownloads[wallpaper.id] = task
                task.resume()
            }
        } catch is CancellationError {
            cleanupDownload(wallpaper.id)
            throw CancellationError()
        } catch {
            cleanupDownload(wallpaper.id)
            throw error
        }
    }

    func isDownloaded(wallpaperId: String, in folder: String) -> Bool {
        findDownloadedFile(wallpaperId: wallpaperId, in: folder) != nil
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

    func downloadedIds(in folder: String) -> Set<String> {
        Self.downloadedIdsStatic(in: folder)
    }

    nonisolated static func downloadedIdsStatic(in folder: String) -> Set<String> {
        guard !folder.isEmpty else { return [] }
        let folderURL = URL(fileURLWithPath: folder)
        let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var ids = Set<String>()
        while let fileURL = enumerator?.nextObject() as? URL {
            let name = fileURL.lastPathComponent
            guard name.hasPrefix("wallhaven-") else { continue }
            let stem = fileURL.deletingPathExtension().lastPathComponent
            let id = String(stem.dropFirst("wallhaven-".count))
            if !id.isEmpty { ids.insert(id) }
        }
        return ids
    }

    func cancelDownload(_ wallpaperId: String) {
        activeDownloads[wallpaperId]?.cancel()
        cleanupDownload(wallpaperId)
    }

    func cancelAllDownloads() {
        for (_, task) in activeDownloads {
            task.cancel()
        }
        for id in Array(activeDownloads.keys) {
            cleanupDownload(id)
        }
    }

    private func cleanupDownload(_ wallpaperId: String) {
        activeDownloads.removeValue(forKey: wallpaperId)
        states.removeValue(forKey: wallpaperId)
        if let session = sessions.removeValue(forKey: wallpaperId) {
            session.invalidateAndCancel()
        }
    }

    private func buildDestinationURL(for wallpaper: WallhavenWallpaper, in folder: String) -> URL {
        let filename = "wallhaven-\(wallpaper.id).\(wallpaper.fileExtension)"
        return URL(fileURLWithPath: folder).appendingPathComponent(filename)
    }
}
