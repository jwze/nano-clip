import Foundation

public enum ClipKind: Int, Sendable, Codable {
    case text = 0
    case image = 1
}

public struct ClipItem: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let kind: ClipKind
    public let text: String?
    /// File name inside the store's `images/` folder (`<sha256>.png`).
    public let imagePath: String?
    public let imageBytes: Int
    public let sourceApp: String?
    public let createdAt: Date
    public let pinned: Bool
    public let truncated: Bool

    public init(
        id: Int64,
        kind: ClipKind,
        text: String?,
        imagePath: String?,
        imageBytes: Int,
        sourceApp: String?,
        createdAt: Date,
        pinned: Bool,
        truncated: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.imageBytes = imageBytes
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.pinned = pinned
        self.truncated = truncated
    }
}

public struct ClipLimits: Sendable, Equatable {
    public var maxItems: Int
    public var maxImageBytes: Int
    public var maxTotalImageBytes: Int

    public init(maxItems: Int, maxImageBytes: Int, maxTotalImageBytes: Int) {
        self.maxItems = maxItems
        self.maxImageBytes = maxImageBytes
        self.maxTotalImageBytes = maxTotalImageBytes
    }

    public static let `default` = ClipLimits(
        maxItems: 500,
        maxImageBytes: 20 * 1024 * 1024,
        maxTotalImageBytes: 500 * 1024 * 1024
    )
}

public enum InsertResult: Sendable {
    case inserted(ClipItem)
    case deduped(ClipItem)
    case rejected(String)

    public var item: ClipItem? {
        switch self {
        case .inserted(let item), .deduped(let item): return item
        case .rejected: return nil
        }
    }
}

public struct ClipStatistics: Sendable, Equatable {
    public var count: Int
    public var imageBytes: Int
    public var imageCount: Int

    public static let empty = ClipStatistics(count: 0, imageBytes: 0, imageCount: 0)
}