import UIKit

private let WFPluginCardButtonWidth: CGFloat = 124

func WFMakeSection(title: String, footer: String? = nil, contents: [UIView]) -> UIView {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 10

    let titleLabel = WFMakeTextLabel(title, font: .preferredFont(forTextStyle: .headline))
    stack.addArrangedSubview(titleLabel)

    contents.forEach { stack.addArrangedSubview($0) }

    if let footer, !footer.isEmpty {
        stack.addArrangedSubview(WFMakeFootnoteLabel(footer))
    }

    return stack
}

func WFMakeCard(_ arrangedSubviews: [UIView], spacing: CGFloat = 12) -> UIView {
    let stack = UIStackView(arrangedSubviews: arrangedSubviews)
    stack.axis = .vertical
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false

    let container = UIView()
    container.backgroundColor = .secondarySystemGroupedBackground
    container.layer.cornerRadius = 16
    container.layer.cornerCurve = .continuous
    container.addSubview(stack)

    NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
        stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
        stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
    ])

    return container
}

func WFMakeInfoCard(text: String) -> UIView {
    WFMakeCard([WFMakeSecondaryLabel(text)])
}

func WFMakeTextLabel(_ text: String, font: UIFont, color: UIColor = .label, lines: Int = 0) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = font
    label.textColor = color
    label.numberOfLines = lines
    label.adjustsFontForContentSizeCategory = true
    return label
}

func WFMakeSecondaryLabel(_ text: String) -> UILabel {
    WFMakeTextLabel(text, font: .preferredFont(forTextStyle: .subheadline), color: .secondaryLabel)
}

func WFMakeFootnoteLabel(_ text: String, color: UIColor = .secondaryLabel) -> UILabel {
    WFMakeTextLabel(text, font: .preferredFont(forTextStyle: .footnote), color: color)
}

func WFMakeActionButton(
    title: String,
    systemImage: String? = nil,
    isPrimary: Bool = true,
    isLoading: Bool = false,
    isEnabled: Bool = true,
    buttonSize: UIButton.Configuration.Size = .large,
    tintColor: UIColor? = nil,
    action: @escaping () -> Void
) -> UIButton {
    var configuration = isPrimary ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
    configuration.title = title
    configuration.cornerStyle = .large
    configuration.buttonSize = buttonSize
    configuration.imagePadding = 8
    configuration.showsActivityIndicator = isLoading
    if let systemImage {
        configuration.image = UIImage(systemName: systemImage)
    }

    let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in
        action()
    })
    button.isEnabled = isEnabled && !isLoading
    if let tintColor {
        button.tintColor = tintColor
    }
    return button
}

func WFMakeStatusBadge(state: WatchCompatibilityState, title: String? = nil) -> UIView {
    let imageView = UIImageView(image: UIImage(systemName: state.symbolName))
    imageView.tintColor = state.tintColor
    imageView.setContentHuggingPriority(.required, for: .horizontal)

    let label = WFMakeFootnoteLabel(title ?? state.title, color: state.tintColor)
    label.font = .preferredFont(forTextStyle: .caption1).withSize(12)

    let stack = UIStackView(arrangedSubviews: [imageView, label])
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false

    let container = UIView()
    container.backgroundColor = state.tintColor.withAlphaComponent(0.14)
    container.layer.cornerRadius = 999
    container.addSubview(stack)

    NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
        stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
        stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
        stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
    ])

    return container
}

func WFMakeValueRow(title: String, value: String) -> UIView {
    let titleLabel = WFMakeSecondaryLabel(title)
    titleLabel.numberOfLines = 1
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    let valueLabel = WFMakeTextLabel(value, font: .preferredFont(forTextStyle: .body), lines: 0)
    valueLabel.textAlignment = .right
    valueLabel.lineBreakMode = .byCharWrapping
    valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let spacer = UIView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let stack = UIStackView(arrangedSubviews: [titleLabel, spacer, valueLabel])
    stack.axis = .horizontal
    stack.alignment = .top
    stack.spacing = 8
    return stack
}

func WFMakeIconTile(image: UIImage?, symbolName: String, tintColor: UIColor) -> UIView {
    let resolvedImage = image ?? UIImage(systemName: symbolName)
    let imageView = UIImageView(image: resolvedImage)
    imageView.tintColor = image == nil ? tintColor : nil
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false

    let container = UIView()
    container.backgroundColor = image == nil ? tintColor.withAlphaComponent(0.14) : .secondarySystemGroupedBackground
    container.layer.cornerRadius = 12
    container.layer.cornerCurve = .continuous
    container.clipsToBounds = true
    container.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(imageView)

    NSLayoutConstraint.activate([
        container.widthAnchor.constraint(equalToConstant: 40),
        container.heightAnchor.constraint(equalToConstant: 40),
        imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        imageView.topAnchor.constraint(equalTo: container.topAnchor),
        imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    return container
}

func WFMakeCompatibilityCard(report: WatchCompatibilityReport) -> UIView {
    let titleLabel = WFMakeTextLabel(report.watchName, font: .preferredFont(forTextStyle: .headline))
    let sourceLabel = WFMakeFootnoteLabel(report.sourceLabel)
    let titleStack = UIStackView(arrangedSubviews: [titleLabel, sourceLabel])
    titleStack.axis = .vertical
    titleStack.spacing = 4

    let headerStack = UIStackView(arrangedSubviews: [titleStack, UIView(), WFMakeStatusBadge(state: report.state)])
    headerStack.axis = .horizontal
    headerStack.alignment = .top

    var arrangedSubviews: [UIView] = [headerStack, WFMakeSecondaryLabel(report.detailText)]
    if report.inferred {
        arrangedSubviews.append(WFMakeFootnoteLabel(L("compatibility.flag.inferred"), color: .systemOrange))
    }
    if let watchOSVersion = report.watchOSVersion {
        arrangedSubviews.append(WFMakeValueRow(title: L("compatibility.field.watchOS"), value: watchOSVersion))
    }
    if let productType = report.productType {
        arrangedSubviews.append(WFMakeValueRow(title: L("compatibility.field.product"), value: productType))
    }
    if let chipID = report.chipID {
        arrangedSubviews.append(WFMakeValueRow(title: L("compatibility.field.chipID"), value: chipID))
    }
    if let targetMax = report.deviceMaxCompatibilityVersion {
        arrangedSubviews.append(WFMakeValueRow(title: L("compatibility.field.target"), value: "\(targetMax)"))
    }
    if let systemMin = report.systemMinCompatibilityVersion {
        arrangedSubviews.append(WFMakeValueRow(title: L("compatibility.field.systemMin"), value: "\(systemMin)"))
    }
    if let systemMax = report.systemMaxCompatibilityVersion {
        arrangedSubviews.append(WFMakeValueRow(title: L("compatibility.field.systemMax"), value: "\(systemMax)"))
    }

    return WFMakeCard(arrangedSubviews)
}

func WFMakeUpdateCard(status: LatestUpdateStatus) -> UIView {
    let nameLabel = WFMakeTextLabel(
        status.updateName ?? L("update.none.title"),
        font: .preferredFont(forTextStyle: .headline)
    )
    let headerStack = UIStackView(arrangedSubviews: [nameLabel, UIView(), WFMakeStatusBadge(state: status.state, title: status.title)])
    headerStack.axis = .horizontal
    headerStack.alignment = .top

    var arrangedSubviews: [UIView] = [headerStack, WFMakeSecondaryLabel(status.detailText)]
    if let updateVersion = status.updateVersion {
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.version"), value: updateVersion))
    }
    if let buildVersion = status.buildVersion {
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.build"), value: buildVersion))
    }
    if let osName = status.osName {
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.osName"), value: osName))
    }
    if let publisher = status.publisher {
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.publisher"), value: publisher))
    }
    if let downloadSize = status.downloadSize {
        let formatted = ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.downloadSize"), value: formatted))
    }
    if let preparationSize = status.preparationSize {
        let formatted = ByteCountFormatter.string(fromByteCount: preparationSize, countStyle: .file)
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.preparationSize"), value: formatted))
    }
    if let installationSize = status.installationSize {
        let formatted = ByteCountFormatter.string(fromByteCount: installationSize, countStyle: .file)
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.installationSize"), value: formatted))
    }
    if let totalRequiredFreeSpace = status.totalRequiredFreeSpace {
        let formatted = ByteCountFormatter.string(fromByteCount: totalRequiredFreeSpace, countStyle: .file)
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.totalRequiredFreeSpace"), value: formatted))
    }
    if let marketingVersion = status.marketingVersion {
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.marketingVersion"), value: marketingVersion))
    }
    if let productSystemName = status.productSystemName {
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.productSystemName"), value: productSystemName))
    }
    if let documentationID = status.documentationID {
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.documentationID"), value: documentationID))
    }
    if let manifestLength = status.manifestLength {
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.manifestLength"), value: "\(manifestLength)"))
    }
    if let terms = status.terms {
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.terms"), value: terms ? L("common.yes") : L("common.no")))
    }
    if let installTonightScheduled = status.installTonightScheduled {
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.installTonightScheduled"), value: installTonightScheduled ? L("common.yes") : L("common.no")))
    }
    if let displayTermsRequested = status.displayTermsRequested {
        arrangedSubviews.append(WFMakeValueRow(title: L("update.field.displayTermsRequested"), value: displayTermsRequested ? L("common.yes") : L("common.no")))
    }

    return WFMakeCard(arrangedSubviews)
}

func WFMakePluginCard(
    plugin: PluginState,
    isBusy: Bool,
    actionTitle: String? = nil,
    systemImage: String? = nil,
    isPrimary: Bool? = nil,
    tintColor: UIColor? = nil,
    isActionEnabled: Bool? = nil,
    configurationTitle: String? = nil,
    configurationSystemImage: String? = nil,
    isConfigurationEnabled: Bool = true,
    onConfiguration: (() -> Void)? = nil,
    onAction: @escaping () -> Void
) -> UIView {
    let iconView = WFMakeIconTile(
        image: WFPluginBridge.pluginIcon(forScopeIdentifier: plugin.metadata.scopeIdentifier),
        symbolName: plugin.metadata.symbolName,
        tintColor: .systemBlue
    )
    let titleLabel = WFMakeTextLabel(plugin.title, font: .preferredFont(forTextStyle: .headline))
    let detailLabel = WFMakeSecondaryLabel(plugin.detail)

    let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
    textStack.axis = .vertical
    textStack.spacing = 4

    let actionButton = WFMakeActionButton(
        title: actionTitle ?? (plugin.available ? L("common.delete") : L("common.install")),
        systemImage: systemImage ?? (plugin.available ? "trash" : "square.and.arrow.down"),
        isPrimary: isPrimary ?? !plugin.available,
        isLoading: isBusy,
        isEnabled: isActionEnabled ?? (plugin.available || plugin.canInstall),
        buttonSize: .medium,
        tintColor: tintColor ?? (plugin.available ? .systemRed : nil)
    ) {
        onAction()
    }
    actionButton.translatesAutoresizingMaskIntoConstraints = false
    actionButton.widthAnchor.constraint(equalToConstant: WFPluginCardButtonWidth).isActive = true
    var buttonViews: [UIView] = []
    if let onConfiguration {
        let configurationButton = WFMakeActionButton(
            title: configurationTitle ?? L("features.plugins.configure"),
            systemImage: configurationSystemImage ?? "slider.horizontal.3",
            isPrimary: false,
            isLoading: false,
            isEnabled: isConfigurationEnabled && !isBusy,
            buttonSize: .medium
        ) {
            onConfiguration()
        }
        configurationButton.translatesAutoresizingMaskIntoConstraints = false
        configurationButton.widthAnchor.constraint(equalToConstant: WFPluginCardButtonWidth).isActive = true
        buttonViews.append(configurationButton)
    }
    buttonViews.append(actionButton)

    let buttonStack = UIStackView(arrangedSubviews: buttonViews)
    buttonStack.axis = .vertical
    buttonStack.alignment = .fill
    buttonStack.spacing = 8
    buttonStack.setContentHuggingPriority(.required, for: .horizontal)

    let rowStack = UIStackView(arrangedSubviews: [iconView, textStack, buttonStack])
    rowStack.axis = .horizontal
    rowStack.alignment = .center
    rowStack.spacing = 12

    var arrangedSubviews: [UIView] = [rowStack]
    if !plugin.available && plugin.canInstall {
        arrangedSubviews.append(WFMakeFootnoteLabel(L("features.plugins.unavailable"), color: .systemOrange))
    }
    if let validationMessage = plugin.validationMessage {
        let validationColor: UIColor
        switch plugin.validation.state {
        case .compatible:
            validationColor = .secondaryLabel
        case .incompatible:
            validationColor = .systemRed
        case .indeterminate:
            validationColor = .systemRed
        }
        arrangedSubviews.append(WFMakeFootnoteLabel(validationMessage, color: validationColor))
    }
    if let updateMessage = plugin.updateMessage {
        arrangedSubviews.append(WFMakeFootnoteLabel(updateMessage, color: .systemOrange))
    }

    return WFMakeCard(arrangedSubviews)
}

func WFMakePluginHeaderCard(plugin: PluginState) -> UIView {
    let iconView = WFMakeIconTile(
        image: WFPluginBridge.pluginIcon(forScopeIdentifier: plugin.metadata.scopeIdentifier),
        symbolName: plugin.metadata.symbolName,
        tintColor: .systemBlue
    )
    let titleLabel = WFMakeTextLabel(plugin.title, font: .preferredFont(forTextStyle: .headline))
    let detailLabel = WFMakeSecondaryLabel(plugin.detail)
    let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
    textStack.axis = .vertical
    textStack.spacing = 4

    let status = WFMakeStatusBadge(
        state: plugin.available ? .compatible : .unavailable,
        title: plugin.available ? L("plugin.configuration.status.installed") : L("plugin.configuration.status.notInstalled")
    )
    status.setContentHuggingPriority(.required, for: .horizontal)

    let rowStack = UIStackView(arrangedSubviews: [iconView, textStack, status])
    rowStack.axis = .horizontal
    rowStack.alignment = .center
    rowStack.spacing = 12

    var arrangedSubviews: [UIView] = [rowStack]
    if let validationMessage = plugin.validationMessage {
        arrangedSubviews.append(WFMakeFootnoteLabel(validationMessage, color: plugin.validation.state == .compatible ? .secondaryLabel : .systemRed))
    }
    if let updateMessage = plugin.updateMessage {
        arrangedSubviews.append(WFMakeFootnoteLabel(updateMessage, color: .systemOrange))
    }

    return WFMakeCard(arrangedSubviews)
}

func WFMakeToggleCard(
    title: String,
    detail: String,
    isOn: Bool,
    isEnabled: Bool = true,
    onChange: @escaping (Bool) -> Void
) -> UIView {
    let titleLabel = WFMakeTextLabel(title, font: .preferredFont(forTextStyle: .headline))
    let detailLabel = WFMakeSecondaryLabel(detail)
    let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
    textStack.axis = .vertical
    textStack.spacing = 4

    let toggle = UISwitch()
    toggle.isOn = isOn
    toggle.isEnabled = isEnabled
    toggle.addAction(UIAction { _ in
        onChange(toggle.isOn)
    }, for: .valueChanged)
    toggle.setContentHuggingPriority(.required, for: .horizontal)

    let rowStack = UIStackView(arrangedSubviews: [textStack, UIView(), toggle])
    rowStack.axis = .horizontal
    rowStack.alignment = .center
    rowStack.spacing = 12

    return WFMakeCard([rowStack])
}

func WFMakeCodeCard(text: String) -> UIView {
    let label = WFMakeTextLabel(
        text,
        font: .monospacedSystemFont(ofSize: 12, weight: .regular),
        color: .label
    )
    return WFMakeCard([label])
}

func WFMakeStepperCard(
    title: String,
    value: Int,
    range: ClosedRange<Int>,
    onChange: @escaping (Int) -> Void
) -> UIView {
    let titleLabel = WFMakeTextLabel(title, font: .preferredFont(forTextStyle: .headline))
    let valueLabel = WFMakeTextLabel("\(value)", font: .preferredFont(forTextStyle: .headline))
    valueLabel.textAlignment = .right
    valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    let headerStack = UIStackView(arrangedSubviews: [titleLabel, UIView(), valueLabel])
    headerStack.axis = .horizontal
    headerStack.alignment = .firstBaseline

    let stepper = UIStepper()
    stepper.minimumValue = Double(range.lowerBound)
    stepper.maximumValue = Double(range.upperBound)
    stepper.stepValue = 1
    stepper.value = Double(value)
    stepper.addAction(UIAction { _ in
        onChange(Int(stepper.value))
    }, for: .valueChanged)

    let controls = UIStackView(arrangedSubviews: [stepper, UIView()])
    controls.axis = .horizontal
    controls.alignment = .center

    return WFMakeCard([headerStack, controls])
}
