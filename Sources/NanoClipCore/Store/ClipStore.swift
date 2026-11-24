import Foundation

/// SQLite-backed history store. All access is serialised on one queue; every public method is
/// synchronous and cheap (single-digit milliseconds), so the UI can call it from the main thread.
public final class ClipStore: @unchecked Sendable {
    public let directory: URL
    public let imageDirectory: URL

    private let queue = DispatchQueue(label: "com.jvz.nanoclip.store", qos: .userInitiated)
    private let db: SQLiteDatabase
    private let images: ImageStore

    private static let columns = "id, kind, content, image_path, image_bytes, source_app, created_at, pinned, truncated"

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
        hash TEXT NOT NULL UNIQUE,
        source_app TEXT,
        created_at REAL NOT NULL,
        pinned INTEGER NOT NULL DEFAULT 0,
        truncated INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS idx_items_order ON items(pinned DESC, created_at DESC);
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
        return try queue.sync {
            let now = Date().timeIntervalSince1970
            if let existing = try item(hash: hash) {
                try touchInternal(id: existing.id, at: now, sourceApp: sourceApp)
                try trimInternal(limits)
                return .deduped(try itemInternal(id: existing.id) ?? existing)
            }
            let statement = try db.statement("""
            INSERT INTO items(kind, content, image_path, image_bytes, hash, source_app, created_at, pinned, truncated)
            VALUES(?, ?, NULL, 0, ?, ?, ?, 0, ?)
            """)
            statement.reset()
            statement.bind(1, int: ClipKind.text.rawValue)
            statement.bind(2, text: text)
            statement.bind(3, text: hash)
            statement.bind(4, text: sourceApp)
            statement.bind(5, double: now)
            statement.bind(6, bool: truncated)
            _ = try statement.step()
            let id = db.lastInsertRowID
            let stored = try itemInternal(id: id)
            try trimInternal(limits)
            if let stored { return .inserted(stored) }
            return .rejected("插入后无法读回条目")
        }
    }

    @discardableResult
    public func insertImage(
        png: Data,
        sourceApp: String?,
        limits: ClipLimits = .default
    ) throws -> InsertResult {
        guard png.count <= limits.maxImageBytes else {
            return .rejected("图片超过单图上限（\(png.count) > \(limits.maxImageBytes) 字节）")
        }
        var payload = Data("i".utf8)
        payload.append(png)
        let hash = Hashing.sha256Hex(payload)
        return try queue.sync {
            let now = Date().timeIntervalSince1970
            if let existing = try item(hash: hash) {
                try touchInternal(id: existing.id, at: now, sourceApp: sourceApp)
                try trimInternal(limits)
                return .deduped(try itemInternal(id: existing.id) ?? existing)
            }
            let path = try images.write(png: png, hash: hash)
            do {
                let statement = try db.statement("""
                INSERT INTO items(kind, content, image_path, image_bytes, hash, source_app, created_at, pinned, truncated)
                VALUES(?, NULL, ?, ?, ?, ?, ?, 0, 0)
                """)
                statement.reset()
                statement.bind(1, int: ClipKind.image.rawValue)
                statement.bind(2, text: path)
                statement.bind(3, int: png.count)
                statement.bind(4, text: hash)
                statement.bind(5, text: sourceApp)
                statement.bind(6, double: now)
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

    public func fetch(query: String = "", limit: Int = 200) -> [ClipItem] {
        (try? queue.sync { () -> [ClipItem] in
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let sql = """
            SELECT \(Self.columns) FROM items
            WHERE (? = '' OR (kind = 0 AND (content LIKE ? ESCAPE '\\' OR IFNULL(source_app, '') LIKE ? ESCAPE '\\')))
            ORDER BY pinned DESC, created_at DESC
            LIMIT ?
            """
            let statement = try db.statement(sql)
            statement.reset()
            statement.bind(1, text: trimmed)
            let pattern = "%\(Self.escapeLike(trimmed))%"
            statement.bind(2, text: pattern)
            statement.bind(3, text: pattern)
            statement.bind(4, int: max(1, limit))
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

    public func setPinned(id: Int64, pinned: Bool) {
        try? queue.sync {
            let statement = try db.statement("UPDATE items SET pinned = ? WHERE id = ?")
            statement.reset()
            statement.bind(1, bool: pinned)
            statement.bind(2, int: id)
            _ = try statement.step()
        }
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

    /// Removes PNG files that no row references (crash-safety net). Returns the removed count.
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
            text: statement.text(2),
            imagePath: statement.text(3),
            imageBytes: Int(statement.int(4)),
            sourceApp: statement.text(5),
            createdAt: Date(timeIntervalSince1970: statement.double(6)),
            pinned: statement.bool(7),
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

    private func trimInternal(_ limits: ClipLimits) throws {
        let maxItems = max(0, limits.maxItems)
        let overflow = try db.statement(
            "SELECT id, image_path FROM items WHERE pinned = 0 ORDER BY created_at DESC LIMIT -1 OFFSET ?"
        )
        overflow.reset()
        overflow.bind(1, int: maxItems)
        var doomed: [(Int64, String?)] = []
        while try overflow.step() {
            doomed.append((overflow.int(0), overflow.text(1)))
        }
        try deleteRows(doomed)

        var total = try statsInternal().imageBytes
        guard total > limits.maxTotalImageBytes else { return }
        let candidates = try db.statement(
            "SELECT id, image_path, image_bytes FROM items WHERE pinned = 0 AND image_path IS NOT NULL ORDER BY created_at ASC"
        )
        candidates.reset()
        var bySize: [(Int64, String?)] = []
        while total > limits.maxTotalImageBytes, try candidates.step() {
            total -= Int(candidates.int(2))
            bySize.append((candidates.int(0), candidates.text(1)))
        }
        try deleteRows(bySize)
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