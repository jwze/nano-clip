import AppKit

/// One history row: icon well or thumbnail, single-line preview, source/time subtitle.
///
/// The row paints its own HUD pill: a cyan-tinted glass rectangle with a bright left rail when
/// selected, a whisper of light on hover. `NSTableView`'s stock highlight stays switched off.
@MainActor
final class ClipRowView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ClipRow")
    static var rowHeight: CGFloat { Theme.Metrics.rowHeight }

    private let pill = FlippedView()
    private let rail = FlippedView()
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

        rail.wantsLayer = true
        rail.layer?.cornerRadius = 1.25
        rail.layer?.backgroundColor = Theme.neon.cgColor
        rail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rail)

        iconWell.wantsLayer = true
        iconWell.layer?.cornerRadius = 8
        iconWell.layer?.borderWidth = 1
        iconWell.layer?.masksToBounds = true
        iconWell.translatesAutoresizingMaskIntoConstraints = false
        iconWell.addSubview(iconView)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = Theme.textSecondary
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = Theme.Font.rowTitle
        titleLabel.textColor = Theme.textPrimary
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = Theme.Font.rowSubtitle
        subtitleLabel.textColor = Theme.textSecondary
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

            rail.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
            rail.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            rail.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
            rail.widthAnchor.constraint(equalToConstant: 2.5),

            iconWell.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 9),
            iconWell.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWell.widthAnchor.constraint(equalToConstant: 30),
            iconWell.heightAnchor.constraint(equalToConstant: 30),

            iconView.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: iconWell.trailingAnchor, constant: 11),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            titleLabel.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -11),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subtitleLabel.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -11),
        ])

        refreshPill()
    }

    // MARK: - Content

    func configure(icon: NSImage?, text: String, subtitle: String, isImage: Bool) {
        iconView.image = icon
        // Thumbnails keep their own colours; text rows use a tinted glyph inside a glass well.
        iconView.contentTintColor = isImage ? nil : Theme.textSecondary
        iconView.imageScaling = isImage ? .scaleProportionallyUpOrDown : .scaleProportionallyDown
        titleLabel.stringValue = text
        subtitleLabel.stringValue = subtitle
        refreshPill()
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

    private func refreshPill() {
        let background: NSColor
        let border: NSColor
        if isPillSelected {
            background = Theme.selectionFill
            border = Theme.selectionBorder
        } else if isHovered {
            background = Theme.glass
            border = Theme.borderSoft
        } else {
            background = .clear
            border = .clear
        }
        pill.layer?.backgroundColor = background.cgColor
        pill.layer?.borderColor = border.cgColor
        rail.isHidden = !isPillSelected
        iconWell.layer?.backgroundColor = Theme.glass.cgColor
        iconWell.layer?.borderColor = (isPillSelected ? Theme.selectionBorder : Theme.borderSoft).cgColor
        titleLabel.textColor = Theme.textPrimary
        subtitleLabel.textColor = isPillSelected ? Theme.textSecondary : Theme.textTertiary
    }
}