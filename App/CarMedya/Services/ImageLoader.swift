import UIKit

/// Loads and caches channel logos (phone rows, Now Playing artwork, CarPlay list items).
///
/// Logos are downscaled once and kept in an `NSCache`; concurrent requests for the same URL share one download.
/// A logo cached small (list rows) is loaded again when a larger size is asked for (Now Playing artwork).
@MainActor
final class ImageLoader {
    static let shared = ImageLoader()

    private final class Entry {
        let image: UIImage
        /// Longest side the image was decoded for; `.infinity` when it is the original size.
        let limit: CGFloat
        init(image: UIImage, limit: CGFloat) {
            self.image = image
            self.limit = limit
        }
    }

    private let cache = NSCache<NSURL, Entry>()
    private var inFlight: [URL: Task<(UIImage, CGFloat)?, Never>] = [:]
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 50 << 20)
        session = URLSession(configuration: configuration)
        cache.countLimit = 500
    }

    /// A cached logo, without loading.
    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)?.image
    }

    /// Loads a logo, downscaled so its longer side is at most `maxPixelSize` points × screen scale.
    func image(for url: URL, maxPixelSize: CGFloat = 96) async -> UIImage? {
        let target = maxPixelSize * 3
        if let cached = cache.object(forKey: url as NSURL), cached.limit >= target { return cached.image }
        if let running = inFlight[url], let result = await running.value, result.1 >= target { return result.0 }
        let session = self.session
        let task = Task<(UIImage, CGFloat)?, Never> {
            guard let result = try? await session.data(from: url) else { return nil }
            let (data, response) = result
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            return await ImageLoader.decode(data, maxPixelSize: target)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        guard let (image, limit) = result else { return cachedImage(for: url) }
        if (cache.object(forKey: url as NSURL)?.limit ?? 0) < limit {
            cache.setObject(Entry(image: image, limit: limit), forKey: url as NSURL)
        }
        return image
    }

    private nonisolated static func decode(_ data: Data, maxPixelSize: CGFloat) async -> (UIImage, CGFloat)? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxPixelSize, longest > 0 else { return (image, .infinity) }
        let scale = maxPixelSize / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return (await image.byPreparingThumbnail(ofSize: target) ?? image, maxPixelSize)
    }
}
