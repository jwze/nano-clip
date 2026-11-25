import Foundation

/// Turns pasteboard snapshots into stored items. Hashing and SQLite writes all happen on one
/// background queue so the 200–350ms poll never blocks the main thread for long.
@MainActor
public final class CaptureService {
    public var onHistoryChanged: (@MainActor () -> Void)?

    private let store: ClipStore
    private let prefs: Prefs
    private let workQueue = DispatchQueue(label: "com.jvz.nanoclip.capture", qos: .utility)

    public init(store: ClipStore, prefs: Prefs) {
        self.store = store
        self.prefs = prefs
    }

    public func handle(_ snapshot: PasteboardSnapshot) {
        let notify: @MainActor @Sendable () -> Void = { [weak self] in self?.onHistoryChanged?() }

        if prefs.isIgnored(bundleID: snapshot.sourceApp) {
            Log.info("skip: ignored app \(snapshot.sourceApp ?? "unknown")")
            return
        }

        switch CaptureRules.decide(snapshot) {
        case .skip(let reason):
            Log.info("skip: \(reason.rawValue)")
            return

        case .text(let text, let truncated):
            let sourceApp = snapshot.sourceApp
            let limits = prefs.limits
            workQueue.async { [store] in
                autoreleasepool {
                    do {
                        let result = try store.insertText(
                            text,
                            sourceApp: sourceApp,
                            truncated: truncated,
                            limits: limits
                        )
                        switch result {
                        case .inserted: Log.info("captured text (\(text.count) chars)")
                        case .deduped: Log.info("deduped text (\(text.count) chars)")
                        case .rejected(let reason): Log.error("text rejected: \(reason)")
                        }
                        if case .rejected = result { return }
                        Task { @MainActor in notify() }
                    } catch {
                        Log.error("text insert failed: \(error)")
                    }
                }
            }

        case .image:
            guard prefs.recordImages else {
                Log.info("skip: imagesDisabled")
                return
            }
            let candidates = snapshot.images
            let sourceApp = snapshot.sourceApp
            let limits = prefs.limits
            workQueue.async { [store] in
                autoreleasepool {
                    // Keep the first representation that actually decodes; its bytes are stored
                    // untouched, so the original format survives.
                    guard let payload = candidates.lazy.compactMap({ candidate in
                        ImageFormats.payload(data: candidate.data, declaredUTI: candidate.uti)
                    }).first else {
                        Log.info("skip: imageUnreadable")
                        return
                    }
                    do {
                        let result = try store.insertImage(payload, sourceApp: sourceApp, limits: limits)
                        switch result {
                        case .inserted:
                            Log.info("captured image (\(payload.uti), \(payload.data.count) bytes)")
                        case .deduped:
                            Log.info("deduped image (\(payload.data.count) bytes)")
                        case .rejected(let reason):
                            Log.error("image rejected: \(reason)")
                        }
                        if case .rejected = result { return }
                        Task { @MainActor in notify() }
                    } catch {
                        Log.error("image insert failed: \(error)")
                    }
                }
            }
        }
    }
}
