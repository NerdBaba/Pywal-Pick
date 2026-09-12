import Foundation

struct DownloadProgress: Sendable {
    let bytesDownloaded: Int64
    let totalBytes: Int64

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesDownloaded) / Double(totalBytes)
    }
}

final class WallhavenDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var progressHandler: (@Sendable (DownloadProgress) -> Void)?
    var continuation: CheckedContinuation<URL, Error>?
    var destinationURL: URL?
    var wallpaperId: String = ""

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
        guard let continuation, let destinationURL else { return }
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
        if let error, let continuation {
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

    private let delegate = WallhavenDownloadDelegate()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = [
            "User-Agent": "PywalPick/1.0 (macOS wallpaper switcher)"
        ]
        return URLSession(configuration: config, delegate: self.delegate, delegateQueue: nil)
    }()
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]

    private init() {}

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

        do {
            return try await withCheckedThrowingContinuation { continuation in
                delegate.progressHandler = progressHandler
                delegate.continuation = continuation
                delegate.destinationURL = destinationURL
                delegate.wallpaperId = wallpaper.id

                let task = self.session.downloadTask(with: downloadURL)
                self.activeDownloads[wallpaper.id] = task
                task.resume()
            }
        } catch is CancellationError {
            activeDownloads.removeValue(forKey: wallpaper.id)
            throw CancellationError()
        } catch {
            activeDownloads.removeValue(forKey: wallpaper.id)
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
