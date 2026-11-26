// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import Foundation
import SQLite3

enum SQLiteConst {
    /// `SQLITE_TRANSIENT` is a C macro that Swift cannot import; it is `(sqlite3_destructor_type)-1`.
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

public enum SQLiteError: Error, CustomStringConvertible {
    case open(code: Int32, message: String)
    case prepare(code: Int32, message: String, sql: String)
    case step(code: Int32, message: String, sql: String)
    case exec(code: Int32, message: String, sql: String)

    public var description: String {
        switch self {
        case .open(let code, let message):
            return "sqlite open failed (\(code)): \(message)"
        case .prepare(let code, let message, let sql):
            return "sqlite prepare failed (\(code)): \(message) [\(sql)]"
        case .step(let code, let message, let sql):
            return "sqlite step failed (\(code)): \(message) [\(sql)]"
        case .exec(let code, let message, let sql):
            return "sqlite exec failed (\(code)): \(message) [\(sql)]"
        }
    }
}

final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    private var statements: [String: Statement] = [:]

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &db, flags, nil)
        guard result == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let db { sqlite3_close(db) }
            throw SQLiteError.open(code: result, message: message)
        }
        handle = db
    }

    deinit {
        statements.removeAll()
        if let handle { sqlite3_close(handle) }
    }

    private var db: OpaquePointer {
        guard let handle else { preconditionFailure("sqlite handle already closed") }
        return handle
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(db) }
    var changes: Int32 { sqlite3_changes(db) }

    func exec(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorMessage)
            throw SQLiteError.exec(code: result, message: message, sql: sql)
        }
    }

    /// Prepared statements are cached and reused, which matters because the capture path
    /// runs on every pasteboard change.
    func statement(_ sql: String) throws -> Statement {
        if let cached = statements[sql] {
            cached.reset()
            return cached
        }
        let statement = try Statement(database: db, sql: sql)
        statements[sql] = statement
        return statement
    }
}

final class Statement: @unchecked Sendable {
    private let raw: OpaquePointer
    private let sql: String

    init(database: OpaquePointer, sql: String) throws {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteError.prepare(
                code: result,
                message: String(cString: sqlite3_errmsg(database)),
                sql: sql
            )
        }
        raw = statement
        self.sql = sql
    }

    deinit {
        sqlite3_finalize(raw)
    }

    func reset() {
        sqlite3_reset(raw)
        sqlite3_clear_bindings(raw)
    }

    func bind(_ index: Int32, text: String?) {
        if let text {
            sqlite3_bind_text(raw, index, text, -1, SQLiteConst.transient)
        } else {
            sqlite3_bind_null(raw, index)
        }
    }

    func bind(_ index: Int32, int: Int64) {
        sqlite3_bind_int64(raw, index, int)
    }

    func bind(_ index: Int32, int: Int) {
        sqlite3_bind_int64(raw, index, Int64(int))
    }

    func bind(_ index: Int32, bool: Bool) {
        sqlite3_bind_int64(raw, index, bool ? 1 : 0)
    }

    func bind(_ index: Int32, double: Double) {
        sqlite3_bind_double(raw, index, double)
    }

    /// Returns `true` while rows are available.
    func step() throws -> Bool {
        let result = sqlite3_step(raw)
        switch result {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default:
            throw SQLiteError.step(
                code: result,
                message: String(cString: sqlite3_errmsg(sqlite3_db_handle(raw))),
                sql: sql
            )
        }
    }

    func run() throws {
        while try step() {}
    }

    func text(_ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(raw, index) else { return nil }
        return String(cString: pointer)
    }

    func int(_ index: Int32) -> Int64 {
        sqlite3_column_int64(raw, index)
    }

    func double(_ index: Int32) -> Double {
        sqlite3_column_double(raw, index)
    }

    func bool(_ index: Int32) -> Bool {
        sqlite3_column_int64(raw, index) != 0
    }
}