// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import Foundation

public enum ClipKind: Int, Sendable, Codable {
    case text = 0
    case image = 1
}

/// Coarse content type shown in the history filter bar. Links are text, but users think of them
/// as their own bucket, so the category is derived once at capture time and stored.
public enum ClipCategory: Int, Sendable, Codable, CaseIterable {
    case text = 0
    case link = 1
    case image = 2

    public var title: String {
        switch self {
        case .text: return "文本"
        case .link: return "链接"
        case .image: return "图片"
        }
    }

    public static func detect(kind: ClipKind, text: String?) -> ClipCategory {
        switch kind {
        case .image:
            return .image
        case .text:
            return isLink(text) ? .link : .text
        }
    }

    /// A whole payload that is nothing but one URL counts as a link.
    static func isLink(_ text: String?) -> Bool {
        guard let text else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2048,
              !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "ftp"].contains(scheme),
              let host = url.host, !host.isEmpty
        else { return false }
        return true
    }
}

/// Time buckets for the history filter bar.
public enum ClipDateRange: Int, Sendable, Codable, CaseIterable {
    case all = 0
    case today = 1
    case yesterday = 2
    case last7Days = 3
    case last30Days = 4

    public var title: String {
        switch self {
        case .all: return "全部时间"
        case .today: return "今天"
        case .yesterday: return "昨天"
        case .last7Days: return "最近 7 天"
        case .last30Days: return "最近 30 天"
        }
    }

    /// Half-open `[from, to)` bounds, or `nil` for "no bound".
    public func bounds(now: Date = Date(), calendar: Calendar = .current) -> (from: Date?, to: Date?) {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .all:
            return (nil, nil)
        case .today:
            return (startOfToday, nil)
        case .yesterday:
            let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)
            return (startOfYesterday, startOfToday)
        case .last7Days:
            return (calendar.date(byAdding: .day, value: -6, to: startOfToday), nil)
        case .last30Days:
            return (calendar.date(byAdding: .day, value: -29, to: startOfToday), nil)
        }
    }
}

public struct ClipItem: Sendable, Identifiable, Equatable {
    public let id: Int64
    public let kind: ClipKind
    public let category: ClipCategory
    public let text: String?
    /// File name inside the store's `images/` folder (`<sha256>.<ext>`, original format kept).
    public let imagePath: String?
    /// Uniform type identifier of the stored image, e.g. `public.png`.
    public let imageUTI: String?
    public let imageBytes: Int
    public let sourceApp: String?
    public let createdAt: Date
    public let truncated: Bool

    public init(
        id: Int64,
        kind: ClipKind,
        category: ClipCategory? = nil,
        text: String?,
        imagePath: String?,
        imageUTI: String? = nil,
        imageBytes: Int,
        sourceApp: String?,
        createdAt: Date,
        truncated: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.category = category ?? ClipCategory.detect(kind: kind, text: text)
        self.text = text
        self.imagePath = imagePath
        self.imageUTI = imageUTI
        self.imageBytes = imageBytes
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.truncated = truncated
    }
}

/// Retention policy. Images are never capped or trimmed, so the entry count is the only knob;
/// `maxItems == 0` means unlimited.
public struct ClipLimits: Sendable, Equatable {
    public var maxItems: Int

    public init(maxItems: Int) {
        self.maxItems = maxItems
    }

    public var isUnlimited: Bool { maxItems <= 0 }

    public static let `default` = ClipLimits(maxItems: 0)
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
