import Foundation

final class TempDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NanoClipTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    var imagesDirectory: URL {
        url.appendingPathComponent("images", isDirectory: true)
    }

    func imageFiles() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path)) ?? []
    }
}