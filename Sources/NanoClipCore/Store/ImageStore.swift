import Foundation

/// Images live as individual files named by content hash, so re-capturing the same image never
/// duplicates bytes on disk. The stored bytes are exactly what the pasteboard delivered, which
/// means the file extension reflects the user's original format (png, tiff, jpg, heic, …).
public final class ImageStore: @unchecked Sendable {
    public let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) throws {
        self.directory = directory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func write(data: Data, hash: String, fileExtension: String) throws -> String {
        let name = "\(hash).\(fileExtension)"
        let url = directory.appendingPathComponent(name)
        if !fileManager.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
        }
        return name
    }

    public func url(for relativePath: String) -> URL {
        directory.appendingPathComponent(relativePath)
    }

    public func remove(relativePath: String) {
        try? fileManager.removeItem(at: url(for: relativePath))
    }

    public func removeAll() {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Deletes image files whose rows no longer exist. Returns the number removed.
    @discardableResult
    public func gcOrphans(keeping paths: Set<String>) -> Int {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in names {
            guard !name.hasPrefix("."), !paths.contains(name) else { continue }
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
            removed += 1
        }
        return removed
    }
}
