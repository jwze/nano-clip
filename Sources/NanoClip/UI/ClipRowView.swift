import AppKit

/// One history row: icon or thumbnail, single-line preview, source/time subtitle, pin marker.
@MainActor
final class ClipRowView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ClipRow")
    static let rowHeight: CGFloat = 48

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let pinLabel = NSTextField(labelWithString: "📌")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func setup() {
        identifier = Self.reuseIdentifier

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 5
        iconView.layer?.masksToBounds = true
        iconView.contentTintColor = .secondaryLabelColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.truncatesLastVisibleLine = true

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 10.5)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.cell?.truncatesLastVisibleLine = true

        pinLabel.translatesAutoresizingMaskIntoConstraints = false
        pinLabel.font = .systemFont(ofSize: 11)
        pinLabel.isHidden = true
        pinLabel.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(pinLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: pinLabel.leadingAnchor, constant: -8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            pinLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            pinLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(icon: NSImage?, text: String, subtitle: String, pinned: Bool) {
        iconView.image = icon
        titleLabel.stringValue = text
        subtitleLabel.stringValue = subtitle
        pinLabel.isHidden = !pinned
    }
}