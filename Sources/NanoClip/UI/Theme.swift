import AppKit

/// Shared visual language for every surface NanoClip shows: the history panel, the preferences
/// window and the status-bar menu. Keeping the tokens here means a single edit restyles the app.
@MainActor
enum Theme {

    // MARK: - Metrics

    enum Metrics {
        static let panelSize = NSSize(width: 384, height: 566)
        static let panelCornerRadius: CGFloat = 16

        static let rowHeight: CGFloat = 54
        static let rowCornerRadius: CGFloat = 9
        /// Horizontal inset of the rounded selection pill inside a table row.
        static let rowSelectionInset: CGFloat = 7

        static let searchBarHeight: CGFloat = 32
        static let searchBarCornerRadius: CGFloat = 9

        static let cardCornerRadius: CGFloat = 12
        static let cardPadding: CGFloat = 14
    }

    // MARK: - Typography

    enum Font {
        // Computed, not stored: NSFont is not Sendable and is cheap to build.
        static var rowTitle: NSFont { .systemFont(ofSize: 13, weight: .medium) }
        static var rowSubtitle: NSFont { .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular) }
        static var body: NSFont { .systemFont(ofSize: 12.5) }
        static var label: NSFont { .systemFont(ofSize: 12) }
        static var caption: NSFont { .systemFont(ofSize: 11) }
        static var hint: NSFont { .systemFont(ofSize: 10.5) }
        static var sectionHeader: NSFont { .systemFont(ofSize: 11.5, weight: .semibold) }
        static var button: NSFont { .systemFont(ofSize: 11.5) }
        static var buttonSmall: NSFont { .systemFont(ofSize: 10.5) }
    }

    // MARK: - Colors

    /// Builds a color that resolves differently in light and dark appearance.
    static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        }
    }

    /// Tint painted over the blur so text stays legible above a busy desktop. Opaque enough that
    /// the panel never inherits the brightness of whatever happens to be behind it.
    static let backdropTint = dynamic(
        NSColor(calibratedWhite: 0.99, alpha: 0.86),
        NSColor(calibratedWhite: 0.12, alpha: 0.80)
    )

    static let searchBackground = dynamic(
        NSColor(calibratedWhite: 0, alpha: 0.055),
        NSColor(calibratedWhite: 1, alpha: 0.085)
    )

    static let rowHover = dynamic(
        NSColor(calibratedWhite: 0, alpha: 0.045),
        NSColor(calibratedWhite: 1, alpha: 0.055)
    )

    /// Accent-tinted selection pill. Deliberately not the stock full-width blue bar.
    static let rowSelection = NSColor.controlAccentColor.withAlphaComponent(0.20)
    static let rowSelectionBorder = NSColor.controlAccentColor.withAlphaComponent(0.30)

    static let cardBackground = dynamic(
        NSColor(calibratedWhite: 1, alpha: 0.78),
        NSColor(calibratedWhite: 1, alpha: 0.055)
    )

    static let cardBorder = dynamic(
        NSColor(calibratedWhite: 0, alpha: 0.07),
        NSColor(calibratedWhite: 1, alpha: 0.075)
    )

    static let hairlineColor = dynamic(
        NSColor(calibratedWhite: 0, alpha: 0.09),
        NSColor(calibratedWhite: 1, alpha: 0.10)
    )

    static let iconWell = dynamic(
        NSColor(calibratedWhite: 0, alpha: 0.045),
        NSColor(calibratedWhite: 1, alpha: 0.07)
    )

    // MARK: - Small reusable views

    /// One-pixel separator that stays crisp on Retina.
    static func hairline() -> NSView {
        let view = FlippedView()
        view.wantsLayer = true
        view.layer?.backgroundColor = hairlineColor.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    static func label(
        _ text: String,
        font: NSFont,
        color: NSColor = .labelColor,
        alignment: NSTextAlignment = .natural
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }
}

/// Plain flipped container used for separators and cards so top-down layout maths stay readable.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Root view that reports light/dark switches to its owner (NSViewController has no such hook).
@MainActor
final class AppearanceObservingView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

/// Rounded card that groups related settings rows. Rows are stacked by hand (not with an
/// `NSStackView`) so every row is pinned to the card's full content width.
@MainActor
final class CardView: NSView {
    init(rows: [NSView], spacing: CGFloat = 11) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.Metrics.cardCornerRadius
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        let padding = Theme.Metrics.cardPadding
        var previous: NSView?
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = false
            addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
                row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            ])
            if let previous {
                row.topAnchor.constraint(equalTo: previous.bottomAnchor, constant: spacing).isActive = true
            } else {
                row.topAnchor.constraint(equalTo: topAnchor, constant: padding).isActive = true
            }
            previous = row
        }
        if let previous {
            previous.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding).isActive = true
        } else {
            heightAnchor.constraint(equalToConstant: padding * 2).isActive = true
        }
        refreshColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = Theme.cardBackground.cgColor
            layer?.borderColor = Theme.cardBorder.cgColor
        }
    }
}
