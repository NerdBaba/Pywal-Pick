import Foundation
import SwiftUI

class OptimizedImageCache: @unchecked Sendable {
    static let shared = OptimizedImageCache()
    
    private let memoryCache = NSCache<NSString, NSImage>()
    private let cacheQueue = DispatchQueue(label: "image.cache", qos: .userInitiated, attributes: .concurrent)
    
    private init() {
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }
    
    func getCachedImage(for url: URL) -> NSImage? {
        let key = url.path as NSString
        return memoryCache.object(forKey: key)
    }
    
    func cacheImage(_ image: NSImage, for url: URL) {
        let key = url.path as NSString
        let cost = Int(image.size.width * image.size.height * 4)
        memoryCache.setObject(image, forKey: key, cost: cost)
    }
    
    func loadThumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let key = url.path as NSString
        
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        
        return await withCheckedContinuation { continuation in
            cacheQueue.async {
                do {
                    let data = try Data(contentsOf: url)
                    guard let originalImage = NSImage(data: data) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    let thumbnail = self.resizeImage(originalImage, to: size)
                    self.cacheImage(thumbnail, for: url)
                    continuation.resume(returning: thumbnail)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func resizeImage(_ image: NSImage, to size: CGSize) -> NSImage {
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        thumbnail.unlockFocus()
        return thumbnail
    }
}
