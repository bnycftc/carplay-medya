import Foundation

/// A titled group of items, e.g. one section of a CarPlay list.
public struct ListSection<Item> {
    /// Section header (`nil` for none).
    public var header: String?
    /// Items in display order.
    public var items: [Item]

    /// Creates a section.
    public init(header: String?, items: [Item]) {
        self.header = header
        self.items = items
    }
}

extension ListSection: Sendable where Item: Sendable {}
extension ListSection: Equatable where Item: Equatable {}

/// The result of fitting sections into a list with section/item limits.
public struct CappedList<Item> {
    /// Sections that fit, never empty ones.
    public var sections: [ListSection<Item>]
    /// Items that did not fit.
    public var omittedItemCount: Int

    /// Total number of items kept.
    public var itemCount: Int { sections.reduce(0) { $0 + $1.items.count } }
}

extension CappedList: Sendable where Item: Sendable {}

/// Fits content into limits such as `CPListTemplate.maximumSectionCount` / `maximumItemCount`.
///
/// CarPlay reports these per vehicle and may lower them while driving; lists must never exceed them.
public enum ListCapping {
    /// Keeps sections in order, dropping empty ones, until either limit is reached.
    ///
    /// - Parameters:
    ///   - maxSections: maximum number of sections (values below 1 yield an empty list).
    ///   - maxItems: maximum number of items across all sections (values below 1 yield an empty list).
    public static func cap<Item>(_ sections: [ListSection<Item>], maxSections: Int, maxItems: Int) -> CappedList<Item> {
        let total = sections.reduce(0) { $0 + $1.items.count }
        var kept: [ListSection<Item>] = []
        var remaining = max(0, maxItems)
        for section in sections where !section.items.isEmpty {
            guard kept.count < max(0, maxSections), remaining > 0 else { break }
            let items = Array(section.items.prefix(remaining))
            remaining -= items.count
            kept.append(ListSection(header: section.header, items: items))
        }
        let keptCount = kept.reduce(0) { $0 + $1.items.count }
        return CappedList(sections: kept, omittedItemCount: total - keptCount)
    }

    /// Caps a flat list.
    public static func cap<Item>(_ items: [Item], maxItems: Int) -> [Item] {
        Array(items.prefix(max(0, maxItems)))
    }
}
