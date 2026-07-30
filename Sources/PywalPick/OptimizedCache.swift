import AppKit
import Foundation
import ImageIO

/// Fast, size-keyed in-memory thumbnail cache backed by ImageIO (no full-decode resize).
class OptimizedImageCache: @unchecked Sendable {
    static let shared = OptimizedImageCache()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let cacheQueue = DispatchQueue(
        label: "com.pywalpick.image.cache",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private init() {
        memoryCache.countLimit = 400
        memoryCache.totalCostLimit = 150 * 1024 * 1024  // 150MB
    }

    func getCachedImage(for url: URL) -> NSImage? {
        // Legacy API: path-only key; prefer sized lookups.
        memoryCache.object(forKey: url.path as NSString)
    }

    func cacheImage(_ image: NSImage, for url: URL) {
        let key = url.path as NSString
        let cost = Int(image.size.width * image.size.height * 4)
        memoryCache.setObject(image, forKey: key, cost: cost)
    }

    func clearAll() {
        memoryCache.removeAllObjects()
    }

    func loadThumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let pixelSize = max(size.width, size.height) * 2  // retina-ish budget
        let bucket = Self.sizeBucket(for: pixelSize)
        let keyString = "\(url.path)#\(Int(bucket))"
        let key = keyString as NSString

        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        // Prefer pre-generated disk thumbnails when they cover the request.
        if let diskThumb = ThumbnailCache.shared.getCachedThumbnailImage(
            for: url,
            size: Self.thumbnailSize(for: bucket)
        ) {
            memoryCache.setObject(diskThumb, forKey: key, cost: cost(of: diskThumb))
            return diskThumb
        }

        return await withCheckedContinuation { continuation in
            cacheQueue.async { [keyString] in
                let key = keyString as NSString
                if let cached = self.memoryCache.object(forKey: key) {
                    continuation.resume(returning: cached)
                    return
                }

                guard let thumbnail = Self.makeImageIOThumbnail(url: url, maxPixelSize: bucket)
                else {
                    continuation.resume(returning: nil)
                    return
                }

                self.memoryCache.setObject(thumbnail, forKey: key, cost: self.cost(of: thumbnail))
                // Also stash under path-only key for callers that still use it.
                self.cacheImage(thumbnail, for: url)
                continuation.resume(returning: thumbnail)
            }
        }
    }

    // MARK: - Helpers

    private func cost(of image: NSImage) -> Int {
        Int(image.size.width * image.size.height * 4)
    }

    /// Round requested size up to a stable bucket to improve cache hits.
    private static func sizeBucket(for maxPixel: CGFloat) -> CGFloat {
        let clamped = max(maxPixel, 64)
        if clamped <= 160 { return 160 }
        if clamped <= 320 { return 320 }
        if clamped <= 512 { return 512 }
        if clamped <= 768 { return 768 }
        return 1024
    }

    private static func thumbnailSize(for bucket: CGFloat) -> ThumbnailSize {
        if bucket <= 160 { return .small }
        if bucket <= 320 { return .medium }
        return .large
    }

    /// Decode only a thumbnail via ImageIO — avoids loading multi‑MB wallpapers into memory.
    private static func makeImageIOThumbnail(url: URL, maxPixelSize: CGFloat) -> NSImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary)
        else { return nil }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard
            let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source, 0, thumbOptions as CFDictionary)
        else { return nil }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}
