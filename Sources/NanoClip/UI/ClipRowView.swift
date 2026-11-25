import AppKit

/// One history row: icon well or thumbnail, single-line preview, source/time subtitle.
///
/// The row paints its own rounded selection pill instead of using `NSTableView`'s stock full-width
/// highlight, which is what makes the list read as a modern popover rather than a 2005 table.
@MainActor
final class ClipRowView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ClipRow")
    static var rowHeight: CGFloat { Theme.Metrics.rowHeight }

    private let pill = FlippedView()
    private let iconWell = FlippedView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    private var isPillSelected = false
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: - Setup

    private func setup() {
        identifier = Self.reuseIdentifier
        wantsLayer = true

        pill.wantsLayer = true
        pill.layer?.cornerRadius = Theme.Metrics.rowCornerRadius
        pill.layer?.borderWidth = 1
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)

        iconWell.wantsLayer = true
        iconWell.layer?.cornerRadius = 7
        iconWell.translatesAutoresizingMaskIntoConstraints = false
        iconWell.addSubview(iconView)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = Theme.Font.rowTitle
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = Theme.Font.rowSubtitle
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.cell?.truncatesLastVisibleLine = true
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconWell)
        addSubview(titleLabel)
        addSubview(subtitleLabel)

        let inset = Theme.Metrics.rowSelectionInset
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

            iconWell.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset + 9),
            iconWell.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWell.widthAnchor.constraint(equalToConstant: 30),
            iconWell.heightAnchor.constraint(equalToConstant: 30),

            iconView.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: iconWell.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(inset + 11)),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(inset + 11)),
        ])

        refreshPill()
    }

    // MARK: - Content

    func configure(icon: NSImage?, text: String, subtitle: String, isImage: Bool) {
        iconView.image = icon
        // Thumbnails keep their own colours; text rows use a tinted glyph on a soft well.
        iconView.contentTintColor = isImage ? nil : .secondaryLabelColor
        iconView.imageScaling = isImage ? .scaleProportionallyUpOrDown : .scaleProportionallyDown
        iconWell.isHidden = false
        titleLabel.stringValue = text
        subtitleLabel.stringValue = subtitle
    }

    func setPillSelected(_ selected: Bool) {
        guard selected != isPillSelected else { return }
        isPillSelected = selected
        refreshPill()
    }

    func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        refreshPill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshPill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    private func refreshPill() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let background: NSColor?
            let border: NSColor?
            if isPillSelected {
                background = Theme.rowSelection
                border = Theme.rowSelectionBorder
            } else if isHovered {
                background = Theme.rowHover
                border = .clear
            } else {
                background = .clear
                border = .clear
            }
            pill.layer?.backgroundColor = background?.cgColor
            pill.layer?.borderColor = border?.cgColor
            iconWell.layer?.backgroundColor = Theme.iconWell.cgColor
        }
    }
}
