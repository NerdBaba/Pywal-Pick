import AppKit
import Foundation
import ImageIO

/// Cached, downsampled, cancellable image loader for remote Wallhaven images.
///
/// Fixes the CPU/hang problems from the old card code:
/// - Unbounded `URLSession.shared.data(from:)` loads decoded full JPEGs on
///   the main actor and never cancelled when cards scrolled away.
/// - `thumbs.original`/`wallpaper.path` are multi-megabyte originals — this
///   downsamples at decode time via ImageIO so thumbnails cost a thumbnail,
///   not a full desktop-size image.
actor WallhavenImageLoader {
    static let shared = WallhavenImageLoader()

    private let session: URLSession
    private var memoryCache: [String: NSImage] = [:]
    private var cacheOrder: [String] = []
    private let maxMemoryEntries = 200
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let diskCacheDir: URL

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 6
        config.httpAdditionalHeaders = [
            "User-Agent": "PywalPick/1.0 (macOS wallpaper switcher)"
        ]
        self.session = URLSession(configuration: config)

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheDir = caches.appendingPathComponent("PywalPick/Wallhaven", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    func load(urlString: String, maxPixelSize: Int) async -> NSImage? {
        let key = "\(urlString)|\(maxPixelSize)"
        if let cached = memoryCache[key] {
            touch(key)
            return cached
        }
        if Task.isCancelled { return nil }
        if let diskImage = loadFromDisk(key: key) {
            if Task.isCancelled { return nil }
            store(key, image: diskImage)
            return diskImage
        }
        if let existing = inFlight[key] {
            return await existing.value
        }
        let task = Task<NSImage?, Never> { [session] in
            guard let url = URL(string: urlString) else { return nil }
            do {
                let (data, _) = try await session.data(from: url)
                if Task.isCancelled { return nil }
                let image = Self.downsampledImage(from: data, maxPixelSize: maxPixelSize)
                if Task.isCancelled { return nil }
                if let image {
                    self.cache(key: key, image: image, data: data, maxPixelSize: maxPixelSize)
                }
                return image
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight.removeValue(forKey: key)
        return result
    }

    func cancel(urlString: String, maxPixelSize: Int) {
        let key = "\(urlString)|\(maxPixelSize)"
        inFlight[key]?.cancel()
        inFlight.removeValue(forKey: key)
    }

    private static let maxDiskBytes: Int64 = 500 * 1024 * 1024

    private func cache(key: String, image: NSImage, data: Data, maxPixelSize: Int) {
        store(key, image: image)
        let sanitized = key
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "?", with: "_")
        let fileURL = diskCacheDir.appendingPathComponent("\(sanitized).jpg")
        if maxPixelSize >= 1024 {
            try? data.write(to: fileURL, options: .atomic)
        } else if let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            try? jpeg.write(to: fileURL, options: .atomic)
        }
        evictDiskCacheIfNeeded()
    }

    private func evictDiskCacheIfNeeded() {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: diskCacheDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        var entries: [(URL, Int64, Date)] = []
        var total: Int64 = 0
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let date = values.contentModificationDate
            else { continue }
            total += Int64(size)
            entries.append((url, Int64(size), date))
        }
        guard total > Self.maxDiskBytes else { return }
        entries.sort { $0.2 < $1.2 }
        for (url, size, _) in entries {
            try? fileManager.removeItem(at: url)
            total -= size
            if total <= Self.maxDiskBytes { break }
        }
    }

    private func store(_ key: String, image: NSImage) {
        memoryCache[key] = image
        touch(key)
        while cacheOrder.count > maxMemoryEntries, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            memoryCache.removeValue(forKey: oldest)
        }
    }

    private func touch(_ key: String) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    private func loadFromDisk(key: String) -> NSImage? {
        let sanitized = key
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "?", with: "_")
        let fileURL = diskCacheDir.appendingPathComponent("\(sanitized).jpg")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return NSImage(data: data)
    }

    private nonisolated static func downsampledImage(from data: Data, maxPixelSize: Int) -> NSImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return NSImage(data: data)
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
