import Darwin
import UIKit

private final class DebugCopyTapGestureRecognizer: UITapGestureRecognizer {
    let itemTitle: String
    let itemValue: String

    init(title: String, value: String, target: Any?, action: Selector?) {
        itemTitle = title
        itemValue = value
        super.init(target: target, action: action)
    }
}

final class DebugViewController: WFScrollStackViewController, UITextFieldDelegate {
    private var isRawDebugExpanded = false
    private var isCapabilitiesExpanded = false
    private var hasSeededManualProductType = false
    private var manualProductType = ""

    private weak var deviceImagePreviewContainer: UIView?
    private weak var deviceImagePreviewImageView: UIImageView?
    private weak var deviceImagePreviewTitleLabel: UILabel?
    private weak var deviceImagePreviewSourceLabel: UILabel?
    private weak var deviceImagePreviewAssetLabel: UILabel?
    private weak var deviceImagePreviewDetailLabel: UILabel?

    init(store: Store) {
        super.init(store: store, title: L("landing.debug.title"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func render() {
        resetContent()

        contentStack.addArrangedSubview(
            WFMakeSection(
                title: L("debug.section.controls"),
                contents: [
                    WFMakeCard([
                        WFMakeActionButton(
                            title: L("debug.action.refresh"),
                            systemImage: "arrow.clockwise",
                            isLoading: store.isRefreshingDebugSnapshot
                        ) { [weak self] in
                            self?.store.refreshDebugSnapshot()
                        },
                        WFMakeActionButton(
                            title: L("debug.action.copy"),
                            systemImage: "doc.on.doc",
                            isPrimary: false
                        ) { [weak self] in
                            self?.copyAllDebugInformation()
                        },
                    ]),
                ]
            )
        )

        let debugInfo = store.activeWatchDebugInfo
        let properties = debugInfo?.properties
        let currentProductType = scalarText(properties?["productType"])

        if !hasSeededManualProductType, let currentProductType, !currentProductType.isEmpty {
            manualProductType = currentProductType
            hasSeededManualProductType = true
        }

        var watchContents: [UIView] = []
        if store.isRefreshingDebugSnapshot {
            watchContents.append(WFMakeInfoCard(text: L("debug.loading.watch")))
        }

        if let debugInfo, debugInfo.hasWatch, let properties {
            if let summaryCard = makeWatchSummaryCard(properties) {
                watchContents.append(summaryCard)
            }
            if let statusCard = makeWatchStatusCard(properties) {
                watchContents.append(statusCard)
            }
            if let propertiesCard = makeRemainingPropertiesCard(properties) {
                watchContents.append(propertiesCard)
            }
        }

        if watchContents.isEmpty, !store.isRefreshingDebugSnapshot {
            watchContents.append(WFMakeInfoCard(text: L("debug.watch.empty")))
        }

        contentStack.addArrangedSubview(
            WFMakeSection(
                title: L("debug.section.watch"),
                footer: L("debug.section.watch.footer"),
                contents: watchContents
            )
        )

        contentStack.addArrangedSubview(
            WFMakeSection(
                title: L("debug.section.deviceImage"),
                footer: L("debug.section.deviceImage.footer"),
                contents: [makeDeviceImageCard()]
            )
        )

        var capabilityContents: [UIView] = [
            WFMakeCard([
                WFMakeActionButton(
                    title: isCapabilitiesExpanded ? L("debug.action.hideCapabilities") : L("debug.action.showCapabilities"),
                    systemImage: isCapabilitiesExpanded ? "chevron.up" : "chevron.down",
                    isPrimary: false
                ) { [weak self] in
                    guard let self else {
                        return
                    }
                    self.isCapabilitiesExpanded.toggle()
                    self.render()
                },
            ]),
        ]

        if isCapabilitiesExpanded {
            let capabilities = debugInfo?.capabilities ?? []
            if let capabilitiesCard = makeCapabilitiesCard(capabilities) {
                capabilityContents.append(capabilitiesCard)
            } else if !store.isRefreshingDebugSnapshot {
                capabilityContents.append(WFMakeInfoCard(text: L("debug.capabilities.empty")))
            }
        }

        contentStack.addArrangedSubview(
            WFMakeSection(
                title: L("debug.section.capabilities"),
                footer: L("debug.section.capabilities.footer"),
                contents: capabilityContents
            )
        )

        var rawContents: [UIView] = [
            WFMakeCard([
                WFMakeActionButton(
                    title: isRawDebugExpanded ? L("debug.action.hideRaw") : L("debug.action.showRaw"),
                    systemImage: isRawDebugExpanded ? "chevron.up" : "chevron.down",
                    isPrimary: false
                ) { [weak self] in
                    guard let self else {
                        return
                    }
                    self.isRawDebugExpanded.toggle()
                    self.render()
                },
            ]),
        ]

        if isRawDebugExpanded {
            if let rawJSON = store.activeWatchDebugrawJSON {
                rawContents.append(makeDumpCard(title: L("debug.card.rawJSON"), object: rawJSON))
            } else if !store.isRefreshingDebugSnapshot {
                rawContents.append(WFMakeInfoCard(text: L("debug.raw.empty")))
            }
        }

        contentStack.addArrangedSubview(
            WFMakeSection(
                title: L("debug.section.raw"),
                footer: L("debug.section.raw.footer"),
                contents: rawContents
            )
        )

        contentStack.addArrangedSubview(
            WFMakeSection(
                title: L("debug.section.phone"),
                contents: [makePhoneCard()]
            )
        )
    }

    private func highlightedPropertyKeys() -> Set<String> {
        [
            "name",
            "localizedModel",
            "productType",
            "systemName",
            "systemVersion",
            "systemBuildVersion",
            "modelNumber",
            "regulatoryModelNumber",
            "serialNumber",
            "chipID",
            "isActive",
            "isPaired",
            "isCellularEnabled",
            "isSetup",
            "pairingCompatibilityVersion",
            "minPairingCompatibilityVersion",
            "maxPairingCompatibilityVersion",
            "compatibilityState",
            "statusCode",
            "pairedDate",
            "lastActiveDate",
            "pairingID",
            "pairingSessionIdentifier",
            "regionCode",
            "regionInfo",
            "currentUserLocale",
            "capabilities",
        ]
    }

    private func makeWatchSummaryCard(_ properties: [String: Any]) -> UIView? {
        let watchName = scalarText(properties["name"]) ?? scalarText(properties["localizedModel"]) ?? "Apple Watch"
        let localizedModel = scalarText(properties["localizedModel"])
        let productType = scalarText(properties["productType"])
        let preview = WatchImageHelper.preview(for: productType)
        let systemVersion = [scalarText(properties["systemName"]), scalarText(properties["systemVersion"])]
            .compactMap { $0 }
            .joined(separator: " ")
        let subtitleParts = [localizedModel, productType, systemVersion]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else {
                    return nil
                }
                return value
            }

        let titleStackSubviews: [UIView] = {
            var views: [UIView] = [WFMakeTextLabel(watchName, font: .preferredFont(forTextStyle: .headline))]
            if !subtitleParts.isEmpty {
                views.append(WFMakeSecondaryLabel(subtitleParts.joined(separator: " • ")))
            }
            return views
        }()

        let titleStack = UIStackView(arrangedSubviews: titleStackSubviews)
        titleStack.axis = .vertical
        titleStack.spacing = 4

        let headerStack = UIStackView(arrangedSubviews: [makeWatchImageView(preview: preview, dimension: 58), titleStack])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 14

        var rows: [UIView] = [headerStack]

        let summaryKeys = [
            "systemBuildVersion",
            "modelNumber",
            "regulatoryModelNumber",
            "serialNumber",
            "chipID",
            "pairingID",
            "pairingSessionIdentifier",
            "regionInfo",
            "currentUserLocale",
        ]

        rows.append(contentsOf: propertyViews(properties: properties, keys: summaryKeys))
        return rows.count > 0 ? WFMakeCard(rows) : nil
    }

    private func makeWatchStatusCard(_ properties: [String: Any]) -> UIView? {
        let statusKeys = [
            "isActive",
            "isPaired",
            "isCellularEnabled",
            "isSetup",
            "pairingCompatibilityVersion",
            "minPairingCompatibilityVersion",
            "maxPairingCompatibilityVersion",
            "compatibilityState",
            "statusCode",
            "pairedDate",
            "lastActiveDate",
        ]

        let rows = propertyViews(properties: properties, keys: statusKeys)
        guard !rows.isEmpty else {
            return nil
        }

        return WFMakeCard([
            WFMakeTextLabel(L("debug.card.status"), font: .preferredFont(forTextStyle: .headline)),
        ] + rows)
    }

    private func makeRemainingPropertiesCard(_ properties: [String: Any]) -> UIView? {
        let remainingKeys = properties.keys
            .filter { !highlightedPropertyKeys().contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let rows = propertyViews(properties: properties, keys: remainingKeys)
        guard !rows.isEmpty else {
            return nil
        }

        return WFMakeCard([
            WFMakeTextLabel(L("debug.card.properties"), font: .preferredFont(forTextStyle: .headline)),
        ] + rows)
    }

    private func propertyViews(properties: [String: Any], keys: [String]) -> [UIView] {
        keys.compactMap { key in
            guard let value = properties[key] else {
                return nil
            }
            return makePropertyView(key: key, value: value)
        }
    }

    private func makePropertyView(key: String, value: Any) -> UIView {
        if let scalar = scalarText(value) {
            return makeCopyableValueRow(title: key, value: scalar)
        }

        let titleLabel = WFMakeTextLabel(key, font: .preferredFont(forTextStyle: .subheadline))
        let valueLabel = WFMakeTextLabel(
            formattedDump(value),
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
            color: .secondaryLabel,
            lines: 0
        )
        valueLabel.lineBreakMode = .byCharWrapping

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 6
        return makeCopyableView(stack, title: key, value: formattedDump(value))
    }

    private func scalarText(_ value: Any?) -> String? {
        guard let value else {
            return nil
        }

        if value is NSNull {
            return L("debug.value.none")
        }

        if let string = value as? String {
            return string
        }

        if let number = value as? NSNumber {
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
                return number.boolValue ? L("debug.value.yes") : L("debug.value.no")
            }
            return number.stringValue
        }

        if let values = value as? [String] {
            return values.joined(separator: ", ")
        }

        if let dict = value as? [String: Any], let description = dict["description"] as? String, dict.keys.contains("className") {
            return description
        }

        return nil
    }

    private func makeCapabilitiesCard(_ capabilities: [String]) -> UIView? {
        guard !capabilities.isEmpty else {
            return nil
        }

        let countLabel = makeCopyableValueRow(title: L("debug.capabilities.count"), value: "\(capabilities.count)")
        let capabilityText = capabilities.joined(separator: "\n")
        let capabilityLabel = WFMakeTextLabel(
            capabilityText,
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
            color: .secondaryLabel,
            lines: 0
        )
        capabilityLabel.lineBreakMode = .byCharWrapping

        let card = WFMakeCard([
            WFMakeTextLabel(L("debug.card.capabilities"), font: .preferredFont(forTextStyle: .headline)),
            countLabel,
            makeCopyableView(capabilityLabel, title: L("debug.card.capabilities"), value: capabilityText),
        ])
        return card
    }

    private func makeDumpCard(title: String, object: Any) -> UIView {
        let dumpText = formattedDump(object)
        let dumpLabel = WFMakeTextLabel(
            dumpText,
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
            color: .secondaryLabel,
            lines: 0
        )
        dumpLabel.lineBreakMode = .byCharWrapping

        let card = WFMakeCard([
            WFMakeTextLabel(title, font: .preferredFont(forTextStyle: .headline)),
            dumpLabel,
        ])
        return makeCopyableView(card, title: title, value: dumpText)
    }

    private func formattedDump(_ object: Any) -> String {
        if object is NSNull {
            return L("debug.value.none")
        }

        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: object)
        }

        return text
    }

    private func copyAllDebugInformation() {
        UIPasteboard.general.string = formattedDump(fullDebugInformationPayload())
        store.alert = Alert(
            title: L("alert.success.title"),
            message: L("debug.copy.success")
        )
    }

    private func fullDebugInformationPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "phone": phoneDebugInfo(),
        ]

        if let debugInfo = store.activeWatchDebugInfo {
            payload["nrDeviceDebugInfo"] = debugInfo.bridgeValue
        } else {
            payload["nrDeviceDebugInfo"] = NSNull()
        }

        payload["nrDevicerawJSON"] = store.activeWatchDebugrawJSON ?? NSNull()

        return payload
    }

    private func phoneDebugInfo() -> [String: String] {
        let device = UIDevice.current
        return [
            "name": device.name,
            "model": device.model,
            "identifier": machineIdentifier(),
            "system": "\(device.systemName) \(device.systemVersion)",
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? L("about.value.unknown"),
        ]
    }

    private func makePhoneCard() -> UIView {
        let phoneInfo = phoneDebugInfo()
        return WFMakeCard([
            makeCopyableValueRow(title: L("debug.phone.field.name"), value: phoneInfo["name"] ?? L("about.value.unknown")),
            makeCopyableValueRow(title: L("debug.phone.field.model"), value: phoneInfo["model"] ?? L("about.value.unknown")),
            makeCopyableValueRow(title: L("debug.phone.field.identifier"), value: phoneInfo["identifier"] ?? L("about.value.unknown")),
            makeCopyableValueRow(title: L("debug.phone.field.system"), value: phoneInfo["system"] ?? L("about.value.unknown")),
            makeCopyableValueRow(title: L("debug.phone.field.bundle"), value: phoneInfo["bundleIdentifier"] ?? L("about.value.unknown")),
        ])
    }

    private func makeCopyableValueRow(title: String, value: String) -> UIView {
        makeCopyableView(WFMakeValueRow(title: title, value: value), title: title, value: value)
    }

    private func makeDeviceImageCard() -> UIView {
        let textField = UITextField()
        textField.borderStyle = .roundedRect
        textField.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .done
        textField.placeholder = L("debug.deviceImage.input.placeholder")
        textField.text = manualProductType
        textField.delegate = self
        textField.addTarget(self, action: #selector(deviceImageInputChanged(_:)), for: .editingChanged)

        let imageContainer = UIView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.layer.cornerRadius = 18
        imageContainer.layer.cornerCurve = .continuous
        imageContainer.clipsToBounds = true

        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageContainer.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageContainer.widthAnchor.constraint(equalToConstant: 78),
            imageContainer.heightAnchor.constraint(equalToConstant: 78),
            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor, constant: 10),
            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor, constant: 10),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor, constant: -10),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor, constant: -10),
        ])

        let titleLabel = WFMakeTextLabel("", font: .preferredFont(forTextStyle: .headline))

        let sourceLabel = WFMakeFootnoteLabel("")
        sourceLabel.numberOfLines = 0

        let assetLabel = WFMakeFootnoteLabel("")
        assetLabel.numberOfLines = 0

        let detailLabel = WFMakeTextLabel(
            "",
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
            color: .secondaryLabel,
            lines: 0
        )
        detailLabel.lineBreakMode = .byCharWrapping

        let previewTextStack = UIStackView(arrangedSubviews: [titleLabel, sourceLabel, assetLabel])
        previewTextStack.axis = .vertical
        previewTextStack.spacing = 4

        let previewHeader = UIStackView(arrangedSubviews: [imageContainer, previewTextStack])
        previewHeader.axis = .horizontal
        previewHeader.alignment = .center
        previewHeader.spacing = 14

        deviceImagePreviewContainer = imageContainer
        deviceImagePreviewImageView = imageView
        deviceImagePreviewTitleLabel = titleLabel
        deviceImagePreviewSourceLabel = sourceLabel
        deviceImagePreviewAssetLabel = assetLabel
        deviceImagePreviewDetailLabel = detailLabel

        let card = WFMakeCard([
            WFMakeSecondaryLabel(L("debug.deviceImage.input.title")),
            textField,
            previewHeader,
            detailLabel,
        ])

        updateDeviceImagePreview()
        return card
    }

    private func makeWatchImageView(preview: WatchImageHelper.Preview, dimension: CGFloat) -> UIView {
        let imageContainer = UIView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.layer.cornerRadius = 16
        imageContainer.layer.cornerCurve = .continuous
        imageContainer.clipsToBounds = true

        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageContainer.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageContainer.widthAnchor.constraint(equalToConstant: dimension),
            imageContainer.heightAnchor.constraint(equalToConstant: dimension),
            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor, constant: -8),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor, constant: -8),
        ])

        applyWatchPreview(preview, imageView: imageView, container: imageContainer)
        return imageContainer
    }

    private func applyWatchPreview(_ preview: WatchImageHelper.Preview, imageView: UIImageView, container: UIView) {
        imageView.image = preview.bridgeImage ?? UIImage(systemName: preview.symbolName)
        imageView.tintColor = preview.bridgeImage == nil ? .systemBlue : nil
        container.backgroundColor = preview.bridgeImage == nil
            ? UIColor.systemBlue.withAlphaComponent(0.12)
            : .tertiarySystemGroupedBackground
    }

    private func updateDeviceImagePreview() {
        guard let container = deviceImagePreviewContainer,
              let imageView = deviceImagePreviewImageView,
              let titleLabel = deviceImagePreviewTitleLabel,
              let sourceLabel = deviceImagePreviewSourceLabel,
              let assetLabel = deviceImagePreviewAssetLabel,
              let detailLabel = deviceImagePreviewDetailLabel else {
            return
        }

        let preview = WatchImageHelper.preview(for: manualProductType)
        applyWatchPreview(preview, imageView: imageView, container: container)

        let none = L("debug.value.none")

        switch preview.status {
        case .emptyInput:
            titleLabel.text = L("debug.deviceImage.preview.empty")
            sourceLabel.text = nil
            assetLabel.text = nil
            detailLabel.text = nil
        case .invalidProductType:
            titleLabel.text = L("debug.deviceImage.preview.invalid")
            sourceLabel.text = nil
            assetLabel.text = "\(L("debug.deviceImage.field.bridgeAsset")): \(none)"
            detailLabel.text = [
                "\(L("debug.deviceImage.field.parsed")): \(preview.productType)",
                "\(L("debug.deviceImage.field.nrSize")): \(none)",
                "\(L("debug.deviceImage.field.bridgeSize")): \(none)",
                "\(L("debug.deviceImage.field.sizeAlias")): \(none)",
                "\(L("debug.deviceImage.field.fallbackMaterial")): \(none)",
                "\(L("debug.deviceImage.field.symbolFallback")): \(preview.symbolName)",
            ].joined(separator: "\n")
        case .unmappedProductType, .mappedProductType:
            let parsedText: String
            if let version = preview.version {
                parsedText = "\(version.family)\(version.major),\(version.minor)"
            } else {
                parsedText = none
            }

            titleLabel.text = {
                if preview.bridgeImage != nil {
                    return L("debug.deviceImage.preview.loaded")
                }
                return L("debug.deviceImage.preview.unmapped")
            }()

            sourceLabel.text = preview.bridgeImage != nil
                ? "\(L("debug.deviceImage.field.imageSource")): \(L("debug.deviceImage.value.source.bundle"))"
                : nil
            assetLabel.text = "\(L("debug.deviceImage.field.bridgeAsset")): \(preview.loadedAssetName ?? preview.bridgeAssetName ?? none)"
            detailLabel.text = [
                "\(L("debug.deviceImage.field.parsed")): \(parsedText)",
                "\(L("debug.deviceImage.field.nrSize")): \(numericText(preview.nanoRegistrySize) ?? none)",
                "\(L("debug.deviceImage.field.bridgeSize")): \(numericText(preview.bridgeSize) ?? none)",
                "\(L("debug.deviceImage.field.sizeAlias")): \(preview.sizeAlias ?? none)",
                "\(L("debug.deviceImage.field.fallbackMaterial")): \(numericText(preview.fallbackMaterial) ?? none)",
                "\(L("debug.deviceImage.field.symbolFallback")): \(preview.symbolName)",
            ].joined(separator: "\n")
        }
    }

    private func numericText(_ value: Int?) -> String? {
        guard let value else {
            return nil
        }
        return "\(value)"
    }

    private func makeCopyableView(_ view: UIView, title: String, value: String) -> UIView {
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(DebugCopyTapGestureRecognizer(
            title: title,
            value: value,
            target: self,
            action: #selector(copyDebugItem(_:))
        ))
        return view
    }

    @objc
    private func copyDebugItem(_ sender: DebugCopyTapGestureRecognizer) {
        UIPasteboard.general.string = "\(sender.itemTitle)\n\(sender.itemValue)"
        store.alert = Alert(
            title: L("alert.success.title"),
            message: LF("debug.copy.item.success", sender.itemTitle)
        )
    }

    private func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    @objc
    private func deviceImageInputChanged(_ sender: UITextField) {
        manualProductType = sender.text ?? ""
        updateDeviceImagePreview()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
