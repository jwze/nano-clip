import AppKit

/// Polls `changeCount` — macOS offers no clipboard-change notification — and hands each new
/// state to the capture pipeline. Writes performed by this app are whitelisted so they do not
/// loop back into the history.
@MainActor
public final class PasteboardMonitor {
    public var onCapture: ((PasteboardSnapshot, Int) -> Void)?
    public var sourceAppProvider: (@MainActor () -> String?)?

    private let pasteboard: NSPasteboard
    private var timer: DispatchSourceTimer?
    private var expectedChangeCounts: Set<Int> = []
    private var lastChangeCount: Int

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    public var isRunning: Bool { timer != nil }

    public func start(interval: TimeInterval = 0.35) {
        stop()
        lastChangeCount = pasteboard.changeCount
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(200)
        )
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Call right after writing to the pasteboard ourselves.
    public func expectChange(_ changeCount: Int) {
        expectedChangeCounts.insert(changeCount)
    }

    private func tick() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        expectedChangeCounts = expectedChangeCounts.filter { $0 >= current }
        if expectedChangeCounts.remove(current) != nil {
            Log.info("pasteboard change \(current) is our own write; ignored")
            return
        }
        guard let snapshot = PasteboardReader.snapshot(
            from: pasteboard,
            sourceApp: sourceAppProvider?()
        ) else { return }
        onCapture?(snapshot, current)
    }
}