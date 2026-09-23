import UIKit

/// Loads and caches channel logos (phone rows, Now Playing artwork, CarPlay list items).
///
/// Logos are downscaled once and kept in an `NSCache`; concurrent requests for the same URL share one download.
@MainActor
final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
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
        cache.object(forKey: url as NSURL)
    }

    /// Loads a logo, downscaled so its longer side is at most `maxPixelSize` points × screen scale.
    func image(for url: URL, maxPixelSize: CGFloat = 96) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let running = inFlight[url] { return await running.value }
        let session = self.session
        let target = maxPixelSize * 3
        let task = Task<UIImage?, Never> {
            guard let result = try? await session.data(from: url) else { return nil }
            let (data, response) = result
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            return await ImageLoader.decode(data, maxPixelSize: target)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }

    private nonisolated static func decode(_ data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxPixelSize, longest > 0 else { return image }
        let scale = maxPixelSize / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return await image.byPreparingThumbnail(ofSize: target) ?? image
    }
}
