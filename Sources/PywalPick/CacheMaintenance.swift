import Foundation

/// Clears PywalPick wallpaper-related caches and signals the main UI to reload.
enum CacheMaintenance {
    static let rebuildNotification = Notification.Name("PywalPick.rebuildWallpaperCache")

    /// Wipes thumbnail, in-memory image, and dominant-color caches.
    static func clearAllCaches() {
        ThumbnailCache.shared.clearAll()
        OptimizedImageCache.shared.clearAll()
        DominantColorCache.shared.clearAll()
    }

    /// Clears caches and asks the wallpaper browser to regenerate them.
    static func rebuildAndReload() {
        clearAllCaches()
        NotificationCenter.default.post(name: rebuildNotification, object: nil)
    }
}
