import AppKit
import CoreImage
import Foundation

/// Persistent dominant color cache with disk storage.
/// Colors are saved to disk and loaded on startup. Only new wallpapers are computed.
class DominantColorCache: @unchecked Sendable {
    static let shared = DominantColorCache()

    private let queue = DispatchQueue(label: "com.imagepicker.dominantcolorcache", attributes: .concurrent)
    private var cache: [String: NSColor] = [:]
    private let cacheURL: URL

    private init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheURL = cachesDir.appendingPathComponent("ImagePicker/DominantColors.json")
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        loadFromDiskSync()
    }

    /// Returns the dominant color for an image at the given URL.
    /// Computes on first access, caches forever, persists to disk. Thread-safe.
    func dominantColor(for url: URL) -> NSColor? {
        let key = url.path

        var cached: NSColor?
        queue.sync { cached = cache[key] }
        if let cached { return cached }

        guard let color = extractDominantColor(from: url) else { return nil }

        queue.async(flags: .barrier) {
            self.cache[key] = color
            self.saveToDisk()
        }
        return color
    }

    /// Remove cache entries for URLs that no longer exist.
    func cleanup(for validURLs: Set<URL>) {
        queue.async(flags: .barrier) {
            self.cache = self.cache.filter { key, _ in
                validURLs.contains(URL(fileURLWithPath: key))
            }
            self.saveToDisk()
        }
    }

    private func loadFromDiskSync() {
        guard let data = try? Data(contentsOf: cacheURL),
              let dict = try? JSONDecoder().decode([String: [Double]].self, from: data)
        else { return }

        for (key, components) in dict {
            if components.count == 3 {
                cache[key] = NSColor(
                    red: components[0],
                    green: components[1],
                    blue: components[2],
                    alpha: 1.0
                )
            }
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: cacheURL),
              let dict = try? JSONDecoder().decode([String: [Double]].self, from: data)
        else { return }

        var loaded: [String: NSColor] = [:]
        for (key, components) in dict {
            if components.count == 3 {
                loaded[key] = NSColor(
                    red: components[0],
                    green: components[1],
                    blue: components[2],
                    alpha: 1.0
                )
            }
        }
        queue.async(flags: .barrier) { self.cache = loaded }
    }

    private func saveToDisk() {
        var dict: [String: [Double]] = [:]
        for (key, color) in cache {
            guard let rgb = color.usingColorSpace(.sRGB) else { continue }
            dict[key] = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        }
        try? JSONEncoder().encode(dict).write(to: cacheURL)
    }

    private func extractDominantColor(from url: URL) -> NSColor? {
        guard let imageData = try? Data(contentsOf: url),
              let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let inputImage = CIImage(cgImage: cgImage)

        let extentVector = CIVector(
            x: inputImage.extent.origin.x,
            y: inputImage.extent.origin.y,
            z: inputImage.extent.size.width,
            w: inputImage.extent.size.height
        )

        let ciContext = CIContext(options: [.workingColorSpace: kCFNull!])

        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]
        ),
        let outputImage = filter.outputImage
        else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        return NSColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: CGFloat(bitmap[3]) / 255
        )
    }
}
