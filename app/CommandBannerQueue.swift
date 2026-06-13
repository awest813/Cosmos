import Foundation

/// Queues transient dashboard banners so rapid events are not lost.
struct CommandBannerQueue {
    private(set) var items: [CommandBanner] = []

    var current: CommandBanner? { items.first }

    var pendingCount: Int { max(0, items.count - 1) }

    mutating func enqueue(_ banner: CommandBanner, coalesceDuplicates: Bool = true) {
        if coalesceDuplicates, items.last?.message == banner.message { return }
        items.append(banner)
    }

    mutating func dismissCurrent() {
        if !items.isEmpty {
            items.removeFirst()
        }
    }

    /// Drop success/info banners when a new command starts; keep failures visible.
    mutating func clearTransient() {
        items.removeAll { $0.kind == .success || $0.kind == .info }
    }
}
