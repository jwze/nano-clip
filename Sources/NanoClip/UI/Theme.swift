// nano-clip — 轻量 macOS 剪贴板历史
// Copyright © 2026 jvz <them@live.cn>. All rights reserved.
// Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

import AppKit

/// One design language for every surface NanoClip draws: a dark HUD of frosted glass, hairline
/// borders, a faint engineering grid and a single cyan accent. Every surface forces the dark
/// appearance so the HUD looks the same in a light or dark system.
@MainActor
enum Theme {

    // MARK: - Metrics

    enum Metrics {
        static let panelSize = NSSize(width: 420, height: 620)
        static let panelCornerRadius: CGFloat = 18

        static let rowHeight: CGFloat = 56
        static let rowCornerRadius: CGFloat = 9
        /// Horizontal inset of the selection pill inside a table row.
        static let rowSelectionInset: CGFloat = 8

        static let railWidth: CGFloat = 52
        static let searchBarHeight: CGFloat = 36
        static let chipHeight: CGFloat = 24
        static let footerHeight: CGFloat = 34

        static let cardCornerRadius: CGFloat = 12
        static let cardPadding: CGFloat = 14
        static let controlCornerRadius: CGFloat = 8
        static let gridSpacing: CGFloat = 22
    }

    // MARK: - Palette

    /// Light HUD: white glass, ink text, one cold accent. Everything "live" (focus, selection,
    /// brand) uses the accent, everything structural uses faint ink hairlines.
    static let neon = NSColor(srgbRed: 0.055, green: 0.647, blue: 0.718, alpha: 1.0)
    static let neonBright = NSColor(srgbRed: 0.133, green: 0.827, blue: 0.933, alpha: 1.0)
    static let neonSoft = NSColor(srgbRed: 0.055, green: 0.647, blue: 0.718, alpha: 0.45)
    static let neonFaint = NSColor(srgbRed: 0.055, green: 0.647, blue: 0.718, alpha: 0.12)

    static let base = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    static let baseLift = NSColor(srgbRed: 0.957, green: 0.969, blue: 0.980, alpha: 1.0)
    static let tint = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.94)

    /// Sidebar tint behind the navigation rail.
    static let railBackground = NSColor(srgbRed: 0.973, green: 0.984, blue: 0.988, alpha: 1.0)

    static let glass = NSColor(white: 0.0, alpha: 0.035)
    static let glassStrong = NSColor(white: 0.0, alpha: 0.06)
    static let glassHover = NSColor(white: 0.0, alpha: 0.05)

    static let border = NSColor(white: 0.0, alpha: 0.13)
    static let borderSoft = NSColor(white: 0.0, alpha: 0.07)

    static let textPrimary = NSColor(srgbRed: 0.063, green: 0.094, blue: 0.157, alpha: 1.0)
    static let textSecondary = NSColor(white: 0.0, alpha: 0.55)
    static let textTertiary = NSColor(white: 0.0, alpha: 0.33)

    static let selectionFill = NSColor(srgbRed: 0.055, green: 0.647, blue: 0.718, alpha: 0.13)
    static let selectionBorder = NSColor(srgbRed: 0.055, green: 0.647, blue: 0.718, alpha: 0.42)

    // MARK: - Typography

    enum Font {
        static var brand: NSFont { mono(11, weight: .semibold) }
        static var monoLarge: NSFont { mono(14, weight: .medium) }
        static var monoSmall: NSFont { mono(10, weight: .regular) }
        static var monoHint: NSFont { mono(9.5, weight: .regular) }
        static var rowTitle: NSFont { .systemFont(ofSize: 13, weight: .medium) }
        static var rowSubtitle: NSFont { mono(9.5, weight: .regular) }
        static var body: NSFont { .systemFont(ofSize: 12.5, weight: .regular) }
        static var label: NSFont { .systemFont(ofSize: 12, weight: .regular) }
        static var caption: NSFont { .systemFont(ofSize: 11, weight: .regular) }
        static var section: NSFont { mono(9.5, weight: .semibold) }

        static func mono(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
            .monospacedSystemFont(ofSize: size, weight: weight)
        }
    }

    // MARK: - Small reusable views

    /// One-pixel separator that stays crisp on Retina.
    static func hairline(_ color: NSColor = borderSoft) -> NSView {
        let view = FlippedView()
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    static func label(
        _ text: String,
        font: NSFont,
        color: NSColor = textPrimary,
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

    /// Monospaced label with tracking, the HUD's voice for anything technical.
    static func monoLabel(
        _ text: String,
        size: CGFloat = 10,
        weight: NSFont.Weight = .regular,
        color: NSColor = textSecondary,
        tracking: CGFloat = 0.8
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Font.mono(size, weight: weight)
        label.textColor = color
        label.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: Font.mono(size, weight: weight),
                .foregroundColor: color,
                .kern: tracking,
            ]
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func symbol(
        _ name: String,
        pointSize: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSImage? {
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

/// The panel/window backdrop: frosted glass, a dark tint, a faint engineering grid and a soft glow
/// along the top edge. All HUD surfaces are built on this view.
@MainActor
final class HUDView: NSVisualEffectView {
    var onAppearanceChange: (() -> Void)?

    private let tintLayer = FlippedView()
    private let grid = HUDGridView()
    private let edge = HUDEdgeView()

    init(cornerRadius: CGFloat = Theme.Metrics.panelCornerRadius, showsEdge: Bool = true) {
        super.init(frame: .zero)
        wantsLayer = true
        material = .popover
        blendingMode = .behindWindow
        state = .active
        appearance = NSAppearance(named: .aqua)
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true

        tintLayer.wantsLayer = true
        tintLayer.layer?.backgroundColor = Theme.tint.cgColor
        tintLayer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tintLayer)

        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)

        edge.isHidden = !showsEdge
        edge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(edge)

        for child in [tintLayer, grid, edge] {
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: topAnchor),
                child.leadingAnchor.constraint(equalTo: leadingAnchor),
                child.trailingAnchor.constraint(equalTo: trailingAnchor),
                child.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

/// Opaque HUD surface for real windows: white gradient, the same grid, no glass. A window that
/// shows the desktop through its own content reads as a bug, so settings/popup surfaces are solid.
@MainActor
final class HUDSolidView: NSView {
    private let grid = HUDGridView()

    init(inset: CGFloat = 0) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
            NSColor(srgbRed: 0.961, green: 0.976, blue: 0.984, alpha: 1.0),
        ])
        gradient?.draw(in: bounds, angle: -90)
    }
}

/// Engineering grid plus a top light bar. Drawn once per resize, cheap to keep on screen.
@MainActor
final class HUDGridView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let spacing = Theme.Metrics.gridSpacing
        Theme.neon.withAlphaComponent(0.045).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 0.5

        var x = bounds.minX
        while x <= bounds.maxX {
            path.move(to: NSPoint(x: x, y: bounds.minY))
            path.line(to: NSPoint(x: x, y: bounds.maxY))
            x += spacing
        }
        var y = bounds.minY
        while y <= bounds.maxY {
            path.move(to: NSPoint(x: bounds.minX, y: y))
            path.line(to: NSPoint(x: bounds.maxX, y: y))
            y += spacing
        }
        path.stroke()

        // A faint horizontal glow under the header reads as a scanner bar.
        let glow = NSGradient(colors: [
            Theme.neonBright.withAlphaComponent(0.09),
            Theme.neonBright.withAlphaComponent(0.0),
        ])
        glow?.draw(
            in: NSBezierPath(rect: NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 70)),
            angle: -90
        )
    }
}

/// Hairline border plus corner ticks, the "instrument panel" detail of the HUD.
@MainActor
final class HUDEdgeView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let radius = max(Theme.Metrics.panelCornerRadius, 10)
        let outline = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: radius,
            yRadius: radius
        )
        Theme.border.setStroke()
        outline.lineWidth = 1
        outline.stroke()

    }
}

/// Dark glass card that groups settings rows.
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
        layer?.backgroundColor = Theme.glass.cgColor
        layer?.borderColor = Theme.borderSoft.cgColor
    }
}

/// Bezel-less glass button with a cyan hover: the HUD's only button shape.
/// The caption lives in a label subview — `NSButton` keeps drawing its own cell title under a custom
/// attributed title, which showed up as doubled text.
@MainActor
class TechButton: NSButton {
    private var isHovered = false
    private var isPressed = false
    private let caption = NSTextField(labelWithString: "")

    private(set) var displayTitle: String = ""
    /// Overrides the resolved caption colour (e.g. while a recorder is armed).
    var captionColor: NSColor? {
        didSet { refresh() }
    }

    init(title: String) {
        super.init(frame: .zero)
        self.title = ""
        isBordered = false
        bezelStyle = .inline
        wantsLayer = true
        layer?.cornerRadius = Theme.Metrics.controlCornerRadius
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 24).isActive = true

        caption.font = Theme.Font.mono(10.5, weight: .medium)
        caption.textColor = Theme.textPrimary
        caption.alignment = .center
        caption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(caption)
        NSLayoutConstraint.activate([
            caption.centerXAnchor.constraint(equalTo: centerXAnchor),
            caption.centerYAnchor.constraint(equalTo: centerYAnchor),
            caption.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
        ])

        setDisplayTitle(title)
        addTrackingAreaPair()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setDisplayTitle(_ text: String) {
        displayTitle = text
        caption.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: Theme.Font.mono(10.5, weight: .medium),
                .kern: 0.6,
            ]
        )
    }

    override var isEnabled: Bool {
        didSet { refresh() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        addTrackingAreaPair()
    }

    private func addTrackingAreaPair() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        refresh()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        refresh()
        super.mouseDown(with: event)
        isPressed = false
        refresh()
    }

    /// Padding for the caption, so the glass pill never crowds its text.
    override var intrinsicContentSize: NSSize {
        let size = caption.intrinsicContentSize
        return NSSize(width: size.width + 26, height: 24)
    }

    func refresh() {
        let active = isEnabled
        if isPressed {
            layer?.backgroundColor = Theme.neon.withAlphaComponent(0.18).cgColor
            layer?.borderColor = Theme.neonSoft.cgColor
        } else if isHovered, active {
            layer?.backgroundColor = Theme.glassStrong.cgColor
            layer?.borderColor = Theme.neonSoft.cgColor
        } else {
            layer?.backgroundColor = Theme.glass.cgColor
            layer?.borderColor = Theme.borderSoft.cgColor
        }
        let color = captionColor ?? (active
            ? (isHovered ? Theme.neon : Theme.textPrimary)
            : Theme.textTertiary)
        caption.textColor = color
    }
}

/// Filter chip: a small glass pill that turns cyan when selected. Cheaper and far more co-operative
/// with the light HUD than a stock `NSSegmentedControl`.
@MainActor
final class TechChip: NSButton {
    private var isHovered = false
    private let caption = NSTextField(labelWithString: "")

    private(set) var displayTitle: String = ""

    private(set) var isActive = false {
        didSet { refresh() }
    }

    init(title: String) {
        super.init(frame: .zero)
        self.title = ""
        isBordered = false
        bezelStyle = .inline
        wantsLayer = true
        layer?.cornerRadius = Theme.Metrics.chipHeight / 2
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Theme.Metrics.chipHeight).isActive = true

        caption.font = Theme.Font.mono(10, weight: .regular)
        caption.alignment = .center
        caption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(caption)
        NSLayoutConstraint.activate([
            caption.centerXAnchor.constraint(equalTo: centerXAnchor),
            caption.centerYAnchor.constraint(equalTo: centerYAnchor),
            caption.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 9),
        ])

        setDisplayTitle(title)
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setDisplayTitle(_ text: String) {
        displayTitle = text
        caption.stringValue = text
        refresh()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: caption.intrinsicContentSize.width + 24, height: Theme.Metrics.chipHeight)
    }

    func setActive(_ active: Bool) {
        isActive = active
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refresh()
    }

    func refresh() {
        if isActive {
            layer?.backgroundColor = Theme.selectionFill.cgColor
            layer?.borderColor = Theme.neonSoft.cgColor
        } else if isHovered {
            layer?.backgroundColor = Theme.glass.cgColor
            layer?.borderColor = Theme.border.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = Theme.borderSoft.cgColor
        }
        caption.font = Theme.Font.mono(10, weight: isActive ? .semibold : .regular)
        caption.textColor = isActive ? Theme.neon : (isHovered ? Theme.textPrimary : Theme.textSecondary)
    }
}

/// Thin status pill used for the panel's live counters (item count, clock).
@MainActor
final class HUDBadge: NSView {
    private let label: NSTextField

    init(text: String, color: NSColor = Theme.textSecondary) {
        label = Theme.monoLabel(text, size: 9, weight: .medium, color: color, tracking: 1.0)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.backgroundColor = Theme.glass.cgColor
        layer?.borderColor = Theme.borderSoft.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setText(_ text: String, color: NSColor? = nil) {
        label.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: Theme.Font.mono(9, weight: .medium),
                .foregroundColor: color ?? Theme.textSecondary,
                .kern: 1.0,
            ]
        )
    }
}

/// Icon-only rail button. The panel's navigation is a vertical rail of glyphs, so this is the one
/// control that has to express hover, active and inactive states with a single symbol.
@MainActor
final class HUDIconButton: NSButton {
    private let symbolName: String
    private var isHovered = false

    private(set) var isActive = false {
        didSet { refresh() }
    }

    init(symbol: String, tooltip: String, side: CGFloat = 30) {
        symbolName = symbol
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .inline
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 8
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side),
            heightAnchor.constraint(equalToConstant: side),
        ])
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setActive(_ active: Bool) {
        isActive = active
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refresh()
    }

    func refresh() {
        if isActive {
            layer?.backgroundColor = Theme.selectionFill.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = Theme.selectionBorder.cgColor
        } else if isHovered {
            layer?.backgroundColor = Theme.glass.cgColor
            layer?.borderWidth = 0
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
        }
        let tint = isActive ? Theme.neon : (isHovered ? Theme.textPrimary : Theme.textSecondary)
        image = Theme.symbol(symbolName, pointSize: 12.5, weight: isActive ? .semibold : .regular)
        contentTintColor = tint
    }
}
