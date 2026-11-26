// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import Foundation

/// SQLite-backed history store. All access is serialised on one queue; every public method is
/// synchronous and cheap (single-digit milliseconds), so the UI can call it from the main thread.
public final class ClipStore: @unchecked Sendable {
    public let directory: URL
    public let imageDirectory: URL

    private let queue = DispatchQueue(label: "com.jvz.nanoclip.store", qos: .userInitiated)
    private let db: SQLiteDatabase
    private let images: ImageStore

    private static let columns = """
    id, kind, content, image_path, image_bytes, image_uti, source_app, created_at, truncated, category
    """

    private static let schema = """
    PRAGMA journal_mode=WAL;
    PRAGMA synchronous=NORMAL;
    PRAGMA temp_store=MEMORY;
    PRAGMA cache_size=-512;
    CREATE TABLE IF NOT EXISTS items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind INTEGER NOT NULL,
        content TEXT,
        image_path TEXT,
        image_bytes INTEGER NOT NULL DEFAULT 0,
        image_uti TEXT,
        hash TEXT NOT NULL UNIQUE,
        source_app TEXT,
        created_at REAL NOT NULL,
        truncated INTEGER NOT NULL DEFAULT 0,
        category INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS idx_items_created ON items(created_at DESC);
    """

    public init(directory: URL = AppInfo.applicationSupportDirectory()) throws {
        self.directory = directory
        let imageDirectory = directory.appendingPathComponent("images", isDirectory: true)
        self.imageDirectory = imageDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        images = try ImageStore(directory: imageDirectory)
        db = try SQLiteDatabase(path: directory.appendingPathComponent("history.sqlite3").path)
        try db.exec(Self.schema)
        try migrate()
    }

    /// Adds the columns introduced after 1.0.0 to an existing database and backfills them, so a
    /// history collected by an older build keeps working (and gains its categories).
    private func migrate() throws {
        let existing = try Set(columnNames())
        var addedCategory = false
        if !existing.contains("category") {
            try db.exec("ALTER TABLE items ADD COLUMN category INTEGER NOT NULL DEFAULT 0")
            addedCategory = true
        }
        if !existing.contains("image_uti") {
            try db.exec("ALTER TABLE items ADD COLUMN image_uti TEXT")
            try db.exec("""
            UPDATE items SET image_uti = 'public.png'
            WHERE kind = \(ClipKind.image.rawValue) AND image_uti IS NULL
            """)
        }
        try db.exec("CREATE INDEX IF NOT EXISTS idx_items_category ON items(category, created_at DESC)")
        if addedCategory {
            try backfillCategories()
        }
    }

    private func columnNames() throws -> [String] {
        let statement = try db.statement("PRAGMA table_info(items)")
        statement.reset()
        var names: [String] = []
        while try statement.step() {
            if let name = statement.text(1) { names.append(name) }
        }
        return names
    }

    private func backfillCategories() throws {
        try db.exec("""
        UPDATE items SET category = \(ClipCategory.image.rawValue)
        WHERE kind = \(ClipKind.image.rawValue)
        """)
        let select = try db.statement("SELECT id, content FROM items WHERE kind = 0 AND category = 0")
        select.reset()
        var links: [Int64] = []
        while try select.step() {
            let id = select.int(0)
            if ClipCategory.isLink(select.text(1)) { links.append(id) }
        }
        guard !links.isEmpty else { return }
        let update = try db.statement("UPDATE items SET category = ? WHERE id = ?")
        for id in links {
            update.reset()
            update.bind(1, int: ClipCategory.link.rawValue)
            update.bind(2, int: id)
            _ = try update.step()
        }
    }

    // MARK: - Insert

    @discardableResult
    public func insertText(
        _ text: String,
        sourceApp: String?,
        truncated: Bool = false,
        limits: ClipLimits = .default
    ) throws -> InsertResult {
        let hash = Hashing.sha256Hex("t" + text)
        let category = ClipCategory.detect(kind: .text, text: text)
        return try queue.sync {
            let now = Date().timeIntervalSince1970
            if let existing = try item(hash: hash) {
                try touchInternal(id: existing.id, at: now, sourceApp: sourceApp)
                try trimInternal(limits)
                return .deduped(try itemInternal(id: existing.id) ?? existing)
            }
            let statement = try db.statement("""
            INSERT INTO items(kind, content, image_path, image_bytes, image_uti, hash, source_app, created_at, truncated, category)
            VALUES(?, ?, NULL, 0, NULL, ?, ?, ?, ?, ?)
            """)
            statement.reset()
            statement.bind(1, int: ClipKind.text.rawValue)
            statement.bind(2, text: text)
            statement.bind(3, text: hash)
            statement.bind(4, text: sourceApp)
            statement.bind(5, double: now)
            statement.bind(6, bool: truncated)
            statement.bind(7, int: category.rawValue)
            _ = try statement.step()
            let id = db.lastInsertRowID
            let stored = try itemInternal(id: id)
            try trimInternal(limits)
            if let stored { return .inserted(stored) }
            return .rejected("插入后无法读回条目")
        }
    }

    /// Stores image bytes verbatim — the original format is kept, nothing is re-encoded.
    @discardableResult
    public func insertImage(
        _ payload: ImagePayload,
        sourceApp: String?,
        limits: ClipLimits = .default
    ) throws -> InsertResult {
        var hashInput = Data("i".utf8)
        hashInput.append(payload.data)
        let hash = Hashing.sha256Hex(hashInput)
        return try queue.sync {
            let now = Date().timeIntervalSince1970
            if let existing = try item(hash: hash) {
                try touchInternal(id: existing.id, at: now, sourceApp: sourceApp)
                try trimInternal(limits)
                return .deduped(try itemInternal(id: existing.id) ?? existing)
            }
            let path = try images.write(
                data: payload.data,
                hash: hash,
                fileExtension: payload.fileExtension
            )
            do {
                let statement = try db.statement("""
                INSERT INTO items(kind, content, image_path, image_bytes, image_uti, hash, source_app, created_at, truncated, category)
                VALUES(?, NULL, ?, ?, ?, ?, ?, ?, 0, ?)
                """)
                statement.reset()
                statement.bind(1, int: ClipKind.image.rawValue)
                statement.bind(2, text: path)
                statement.bind(3, int: payload.data.count)
                statement.bind(4, text: payload.uti)
                statement.bind(5, text: hash)
                statement.bind(6, text: sourceApp)
                statement.bind(7, double: now)
                statement.bind(8, int: ClipCategory.image.rawValue)
                _ = try statement.step()
            } catch {
                images.remove(relativePath: path)
                throw error
            }
            let id = db.lastInsertRowID
            let stored = try itemInternal(id: id)
            try trimInternal(limits)
            if let stored { return .inserted(stored) }
            return .rejected("插入后无法读回条目")
        }
    }

    // MARK: - Query

    public func fetch(
        query: String = "",
        category: ClipCategory? = nil,
        dateRange: ClipDateRange = .all,
        limit: Int = 300
    ) -> [ClipItem] {
        (try? queue.sync { () -> [ClipItem] in
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            var conditions: [String] = []
            var bindings: [Binding] = []

            if !trimmed.isEmpty {
                // Images carry no text, so a search always means "text or its source app".
                conditions.append(
                    "(kind = 0 AND (content LIKE ? ESCAPE '\\' OR IFNULL(source_app, '') LIKE ? ESCAPE '\\'))"
                )
                let pattern = "%\(Self.escapeLike(trimmed))%"
                bindings.append(.text(pattern))
                bindings.append(.text(pattern))
            }
            if let category {
                conditions.append("category = ?")
                bindings.append(.int(category.rawValue))
            }
            let (from, to) = dateRange.bounds()
            if let from {
                conditions.append("created_at >= ?")
                bindings.append(.double(from.timeIntervalSince1970))
            }
            if let to {
                conditions.append("created_at < ?")
                bindings.append(.double(to.timeIntervalSince1970))
            }

            var sql = "SELECT \(Self.columns) FROM items"
            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }
            sql += " ORDER BY created_at DESC LIMIT ?"

            let statement = try db.statement(sql)
            statement.reset()
            for (index, binding) in bindings.enumerated() {
                binding.apply(to: statement, at: Int32(index + 1))
            }
            statement.bind(Int32(bindings.count + 1), int: max(1, limit))

            var result: [ClipItem] = []
            while try statement.step() {
                result.append(item(from: statement))
            }
            return result
        }) ?? []
    }

    public func item(id: Int64) -> ClipItem? {
        (try? queue.sync { try itemInternal(id: id) }) ?? nil
    }

    private func itemInternal(id: Int64) throws -> ClipItem? {
        let statement = try db.statement("SELECT \(Self.columns) FROM items WHERE id = ?")
        statement.reset()
        statement.bind(1, int: id)
        guard try statement.step() else { return nil }
        return item(from: statement)
    }

    public func imageURL(for item: ClipItem) -> URL? {
        guard let path = item.imagePath else { return nil }
        return images.url(for: path)
    }

    /// UTI to write the image back with. Rows created before the `image_uti` column fall back to
    /// the extension of the stored file.
    public func imageUTI(for item: ClipItem) -> String {
        if let uti = item.imageUTI, !uti.isEmpty { return uti }
        guard let path = item.imagePath else { return "public.png" }
        let ext = (path as NSString).pathExtension
        return ImageFormats.uti(forPathExtension: ext)
    }

    public func statistics() -> ClipStatistics {
        (try? queue.sync { try statsInternal() }) ?? .empty
    }

    public func totalImageBytes() -> Int {
        statistics().imageBytes
    }

    // MARK: - Mutation

    public func touch(id: Int64) {
        try? queue.sync { try touchInternal(id: id, at: Date().timeIntervalSince1970, sourceApp: nil) }
    }

    public func delete(id: Int64) {
        try? queue.sync {
            guard let stored = try itemInternal(id: id) else { return }
            let statement = try db.statement("DELETE FROM items WHERE id = ?")
            statement.reset()
            statement.bind(1, int: id)
            _ = try statement.step()
            if let path = stored.imagePath { images.remove(relativePath: path) }
        }
    }

    public func clearAll() {
        try? queue.sync {
            let statement = try db.statement("DELETE FROM items")
            statement.reset()
            _ = try statement.step()
            images.removeAll()
        }
    }

    public func trim(limits: ClipLimits = .default) {
        try? queue.sync { try trimInternal(limits) }
    }

    /// Removes image files that no row references (crash-safety net). Returns the removed count.
    @discardableResult
    public func gcOrphanImages() -> Int {
        (try? queue.sync { () -> Int in
            let statement = try db.statement("SELECT image_path FROM items WHERE image_path IS NOT NULL")
            statement.reset()
            var keep = Set<String>()
            while try statement.step() {
                if let path = statement.text(0) { keep.insert(path) }
            }
            return images.gcOrphans(keeping: keep)
        }) ?? 0
    }

    // MARK: - Internals (queue-isolated)

    private enum Binding {
        case int(Int)
        case text(String)
        case double(Double)

        func apply(to statement: Statement, at index: Int32) {
            switch self {
            case .int(let value): statement.bind(index, int: value)
            case .text(let value): statement.bind(index, text: value)
            case .double(let value): statement.bind(index, double: value)
            }
        }
    }

    private func item(hash: String) throws -> ClipItem? {
        let statement = try db.statement("SELECT \(Self.columns) FROM items WHERE hash = ?")
        statement.reset()
        statement.bind(1, text: hash)
        guard try statement.step() else { return nil }
        return item(from: statement)
    }

    private func item(from statement: Statement) -> ClipItem {
        ClipItem(
            id: statement.int(0),
            kind: ClipKind(rawValue: Int(statement.int(1))) ?? .text,
            category: ClipCategory(rawValue: Int(statement.int(9))),
            text: statement.text(2),
            imagePath: statement.text(3),
            imageUTI: statement.text(5),
            imageBytes: Int(statement.int(4)),
            sourceApp: statement.text(6),
            createdAt: Date(timeIntervalSince1970: statement.double(7)),
            truncated: statement.bool(8)
        )
    }

    private func touchInternal(id: Int64, at timestamp: TimeInterval, sourceApp: String?) throws {
        let statement = try db.statement(
            "UPDATE items SET created_at = ?, source_app = COALESCE(?, source_app) WHERE id = ?"
        )
        statement.reset()
        statement.bind(1, double: timestamp)
        statement.bind(2, text: sourceApp)
        statement.bind(3, int: id)
        _ = try statement.step()
    }

    private func statsInternal() throws -> ClipStatistics {
        let statement = try db.statement(
            "SELECT COUNT(*), COALESCE(SUM(image_bytes), 0), COALESCE(SUM(CASE WHEN kind = 1 THEN 1 ELSE 0 END), 0) FROM items"
        )
        statement.reset()
        guard try statement.step() else { return .empty }
        return ClipStatistics(
            count: Int(statement.int(0)),
            imageBytes: Int(statement.int(1)),
            imageCount: Int(statement.int(2))
        )
    }

    /// Only the entry count is enforced: images are kept in their original size and format, so
    /// there is no byte budget to trim against.
    private func trimInternal(_ limits: ClipLimits) throws {
        let maxItems = limits.maxItems
        guard maxItems > 0 else { return }
        let overflow = try db.statement(
            "SELECT id, image_path FROM items ORDER BY created_at DESC LIMIT -1 OFFSET ?"
        )
        overflow.reset()
        overflow.bind(1, int: maxItems)
        var doomed: [(Int64, String?)] = []
        while try overflow.step() {
            doomed.append((overflow.int(0), overflow.text(1)))
        }
        try deleteRows(doomed)
    }

    private func deleteRows(_ rows: [(Int64, String?)]) throws {
        guard !rows.isEmpty else { return }
        let statement = try db.statement("DELETE FROM items WHERE id = ?")
        for (id, path) in rows {
            statement.reset()
            statement.bind(1, int: id)
            _ = try statement.step()
            if let path { images.remove(relativePath: path) }
        }
    }

    static func escapeLike(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "%", with: "\\%")
        escaped = escaped.replacingOccurrences(of: "_", with: "\\_")
        return escaped
    }
}
