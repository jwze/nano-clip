import Foundation
import CoreGraphics

/// Detects a quick double tap of one modifier key (⌥ by default).
///
/// macOS only delivers global key events to apps that hold Accessibility / Input Monitoring
/// permission, but the *current modifier state* is readable for any process through
/// `CGEventSource.flagsState`. Polling that state therefore keeps the "no permission" promise,
/// which is why this class exists instead of an `NSEvent` global monitor or a `CGEventTap`.
public final class DoubleTapMonitor: @unchecked Sendable {
    public var onTrigger: (@MainActor () -> Void)?

    /// Poll interval. Short enough to see a 60ms tap, long enough to stay off the power radar.
    private let interval: TimeInterval = 0.025
    /// Longest press that still counts as a tap, measured from the polled transitions.
    private let maxTapDuration: TimeInterval = 0.45
    /// Longest gap between the release of the first tap and the press of the second.
    private let maxTapGap: TimeInterval = 0.45

    private let queue = DispatchQueue(label: "com.jvz.nanoclip.double-tap", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var modifier: ModifierKey = .option

    private var isDown = false
    private var downAt: TimeInterval = 0
    private var lastTapEnd: TimeInterval = 0
    private var isContaminated = false

    private static let otherModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    public init() {}

    deinit {
        stop()
    }

    public var isRunning: Bool { timer != nil }

    public func start(modifier: ModifierKey) {
        stop()
        self.modifier = modifier
        isDown = false
        lastTapEnd = 0
        isContaminated = false

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(10)
        )
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let target = flags.contains(modifier.cgFlag)
        let others = !flags.intersection(Self.otherModifiers.subtracting(modifier.cgFlag)).isEmpty
        let now = ProcessInfo.processInfo.systemUptime

        if target {
            if !isDown {
                isDown = true
                downAt = now
                isContaminated = others
                // Second tap: fire on the press so the panel opens the instant the key goes down.
                if !isContaminated, lastTapEnd > 0, now - lastTapEnd <= maxTapGap {
                    lastTapEnd = 0
                    fire()
                }
            } else if others {
                // The modifier became part of a shortcut (⌥⌘…), so it is not a tap.
                isContaminated = true
            }
        } else if isDown {
            isDown = false
            let duration = now - downAt
            if !isContaminated, duration <= maxTapDuration {
                lastTapEnd = now
            } else {
                lastTapEnd = 0
            }
            isContaminated = false
        } else if lastTapEnd > 0, now - lastTapEnd > maxTapGap {
            lastTapEnd = 0
        }
    }

    private func fire() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.onTrigger?()
            }
        }
    }
}
