import AppKit
import CoreGraphics
import ImageIO

/// Caches `NSImage`s decoded from clipboard data. Cards are recreated constantly
/// inside the lazy stack (and re-rendered on every selection animation), so without
/// this each frame would re-decode the same image data — a major source of jank.
final class DecodedImageCache {
    static let shared = DecodedImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 600
    }

    /// Full-size decode (used for the small, already-compact app icons).
    func image(forKey key: String, data: Data?) -> NSImage? {
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        guard let data, let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    /// Downsampled thumbnail for card previews. A clipboard image can be a full 4K
    /// screenshot; rendering that into a 160pt card re-rasterizes the whole bitmap
    /// every frame, so we decode a small thumbnail once and cache it.
    func thumbnail(forKey key: String, data: Data?, maxPixel: CGFloat) -> NSImage? {
        let cacheKey = "\(key)-thumb" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        guard let data else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            // Fall back to a full decode if thumbnailing fails (e.g. unusual format).
            return image(forKey: key, data: data)
        }

        let thumb = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(thumb, forKey: cacheKey)
        return thumb
    }
}
