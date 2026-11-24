import Foundation

/// Images live as individual PNG files named by content hash, so re-capturing the same
/// image never duplicates bytes on disk.
public final class ImageStore: @unchecked Sendable {
    public let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) throws {
        self.directory = directory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func write(png: Data, hash: String) throws -> String {
        let name = "\(hash).png"
        let url = directory.appendingPathComponent(name)
        if !fileManager.fileExists(atPath: url.path) {
            try png.write(to: url, options: .atomic)
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
            guard name.hasSuffix(".png"), !paths.contains(name) else { continue }
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
            removed += 1
        }
        return removed
    }
}