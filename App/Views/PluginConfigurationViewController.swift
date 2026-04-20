import UIKit

private enum PluginConfigurationPageKey {
    static let title = "title"
    static let sections = "sections"
    static let savedMessage = "savedMessage"
    static let pendingMessage = "pendingMessage"
}

private enum PluginConfigurationSectionKey {
    static let title = "title"
    static let footer = "footer"
    static let controls = "controls"
}

private enum PluginConfigurationControlKey {
    static let type = "type"
    static let key = "key"
    static let title = "title"
    static let detail = "detail"
    static let minimumValue = "minimumValue"
    static let maximumValue = "maximumValue"
    static let defaultValue = "defaultValue"
    static let minimumValueKey = "minimumValueKey"
}

private enum PluginConfigurationControlType {
    static let stepper = "stepper"
    static let toggle = "toggle"
}

final class PluginConfigurationViewController: WFScrollStackViewController {
    private let pluginIdentifier: String
    private let initialPlugin: PluginState
    private var configurationPage: [String: Any] = [:]
    private var savedConfiguration: [String: Any] = [:]
    private var draftConfiguration: [String: Any] = [:]
    private var pageLoadError: String?
    private var isSavingConfiguration = false

    init(store: Store, plugin: PluginState) {
        pluginIdentifier = plugin.id
        initialPlugin = plugin
        super.init(store: store, title: plugin.title)
        reloadConfiguration()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func render() {
        resetContent()

        let plugin = currentPlugin
        title = pageTitle(plugin: plugin)
        contentStack.addArrangedSubview(WFMakePluginHeaderCard(plugin: plugin))
        contentStack.addArrangedSubview(makeInstallationSection(plugin: plugin))

        if let pageLoadError {
            contentStack.addArrangedSubview(
                WFMakeSection(
                    title: L("plugin.configuration.settings.title"),
                    contents: [WFMakeInfoCard(text: pageLoadError)]
                )
            )
            return
        }

        let sections = sectionDescriptors()
        if sections.isEmpty {
            contentStack.addArrangedSubview(
                WFMakeSection(
                    title: L("plugin.configuration.settings.title"),
                    contents: [WFMakeInfoCard(text: L("plugin.configuration.noCustomSettings"))]
                )
            )
            return
        }

        for section in sections {
            let controls = controlDescriptors(in: section)
            let contents = controls.map(renderControl)
            guard !contents.isEmpty else {
                continue
            }

            contentStack.addArrangedSubview(
                WFMakeSection(
                    title: stringValue(section[PluginConfigurationSectionKey.title], fallback: L("plugin.configuration.settings.title")) ?? L("plugin.configuration.settings.title"),
                    footer: stringValue(section[PluginConfigurationSectionKey.footer], fallback: nil),
                    contents: contents
                )
            )
        }

        if !allControlDescriptors().isEmpty {
            contentStack.addArrangedSubview(makeSaveSection())
        }
    }

    private var currentPlugin: PluginState {
        store.plugins.first { $0.id == pluginIdentifier } ?? initialPlugin
    }

    private func pageTitle(plugin: PluginState) -> String {
        stringValue(configurationPage[PluginConfigurationPageKey.title], fallback: plugin.title) ?? plugin.title
    }

    private func reloadConfiguration() {
        var bridgeError: NSError?
        configurationPage = WFPluginBridge.configurationPage(forPluginNamed: pluginIdentifier, error: &bridgeError)
        if let bridgeError {
            configurationPage = [:]
            pageLoadError = bridgeError.localizedDescription
        } else {
            pageLoadError = nil
        }

        savedConfiguration = WFPluginBridge.configuration(forPluginNamed: pluginIdentifier)
        draftConfiguration = defaultConfiguration()
        for (key, value) in savedConfiguration {
            draftConfiguration[key] = value
        }
    }

    private func makeInstallationSection(plugin: PluginState) -> UIView {
        let isBusy = store.isPluginBusy(plugin.id)
        let button = WFMakeActionButton(
            title: plugin.available ? L("common.delete") : L("common.install"),
            systemImage: plugin.available ? "trash" : "square.and.arrow.down",
            isPrimary: !plugin.available,
            isLoading: isBusy,
            isEnabled: plugin.available || plugin.canInstall,
            tintColor: plugin.available ? .systemRed : nil
        ) { [weak self] in
            guard let self else {
                return
            }
            if plugin.available {
                self.store.removePlugin(identifier: plugin.id)
            } else {
                self.store.installPlugin(identifier: plugin.id)
            }
        }

        var sectionContents: [UIView] = [WFMakeCard([button])]
        if plugin.available, let validationMessage = plugin.validationMessage, plugin.validation.state == .incompatible {
            sectionContents.append(WFMakeCard([WFMakeFootnoteLabel(validationMessage, color: .systemRed)]))
        }

        return WFMakeSection(
            title: L("plugin.configuration.installation.title"),
            contents: sectionContents
        )
    }

    private func makeSaveSection() -> UIView {
        let modified = hasModifiedConfiguration
        let statusText = modified
            ? stringValue(configurationPage[PluginConfigurationPageKey.pendingMessage], fallback: L("plugin.configuration.status.pending"))!
            : stringValue(configurationPage[PluginConfigurationPageKey.savedMessage], fallback: L("plugin.configuration.status.saved"))!

        let saveButton = WFMakeActionButton(
            title: L("common.save"),
            systemImage: "square.and.arrow.down",
            isLoading: isSavingConfiguration,
            isEnabled: modified && !isSavingConfiguration
        ) { [weak self] in
            self?.saveConfiguration()
        }
        let restoreButton = WFMakeActionButton(
            title: L("common.restore"),
            systemImage: "arrow.uturn.backward",
            isPrimary: false,
            isEnabled: modified && !isSavingConfiguration
        ) { [weak self] in
            self?.restoreSavedConfiguration()
        }
        let defaultsButton = WFMakeActionButton(
            title: L("common.defaults"),
            systemImage: "arrow.counterclockwise",
            isPrimary: false,
            isEnabled: !configurationEquals(draftConfiguration, defaultConfiguration()) && !isSavingConfiguration
        ) { [weak self] in
            self?.useDefaultConfiguration()
        }

        return WFMakeSection(
            title: L("plugin.configuration.save.title"),
            contents: [
                WFMakeInfoCard(text: statusText),
                WFMakeCard([saveButton, restoreButton, defaultsButton]),
            ]
        )
    }

    private func renderControl(_ control: [String: Any]) -> UIView {
        let type = stringValue(control[PluginConfigurationControlKey.type], fallback: "")
        switch type {
        case PluginConfigurationControlType.stepper:
            return renderStepper(control)
        case PluginConfigurationControlType.toggle:
            return renderToggle(control)
        default:
            let title = stringValue(control[PluginConfigurationControlKey.title], fallback: L("plugin.configuration.unsupported.title"))!
            return WFMakeInfoCard(text: LF("plugin.configuration.unsupported.detail", title))
        }
    }

    private func renderStepper(_ control: [String: Any]) -> UIView {
        let key = stringValue(control[PluginConfigurationControlKey.key], fallback: "")!
        let defaultValue = intValue(control[PluginConfigurationControlKey.defaultValue], fallback: intValue(control[PluginConfigurationControlKey.minimumValue], fallback: 0))
        let range = rangeForControl(control)
        let value = min(max(intValue(draftConfiguration[key], fallback: defaultValue), range.lowerBound), range.upperBound)

        return WFMakeStepperCard(
            title: stringValue(control[PluginConfigurationControlKey.title], fallback: key) ?? key,
            value: value,
            range: range
        ) { [weak self] newValue in
            self?.updateStepperValue(newValue, for: control)
        }
    }

    private func renderToggle(_ control: [String: Any]) -> UIView {
        let key = stringValue(control[PluginConfigurationControlKey.key], fallback: "")!
        let defaultValue = boolValue(control[PluginConfigurationControlKey.defaultValue], fallback: false)
        let value = boolValue(draftConfiguration[key], fallback: defaultValue)

        return WFMakeToggleCard(
            title: stringValue(control[PluginConfigurationControlKey.title], fallback: key) ?? key,
            detail: stringValue(control[PluginConfigurationControlKey.detail], fallback: "") ?? "",
            isOn: value
        ) { [weak self] isOn in
            self?.draftConfiguration[key] = NSNumber(value: isOn)
            self?.render()
        }
    }

    private func updateStepperValue(_ newValue: Int, for control: [String: Any]) {
        guard let key = stringValue(control[PluginConfigurationControlKey.key], fallback: nil) else {
            return
        }

        let range = rangeForControl(control)
        draftConfiguration[key] = NSNumber(value: min(max(newValue, range.lowerBound), range.upperBound))
        applyDependentMinimums(changedKey: key)
        render()
    }

    private func applyDependentMinimums(changedKey: String) {
        let changedValue = intValue(draftConfiguration[changedKey], fallback: 0)
        for control in allControlDescriptors() {
            guard
                stringValue(control[PluginConfigurationControlKey.minimumValueKey], fallback: nil) == changedKey,
                let dependentKey = stringValue(control[PluginConfigurationControlKey.key], fallback: nil)
            else {
                continue
            }

            let currentValue = intValue(draftConfiguration[dependentKey], fallback: intValue(control[PluginConfigurationControlKey.defaultValue], fallback: changedValue))
            if currentValue < changedValue {
                draftConfiguration[dependentKey] = NSNumber(value: changedValue)
            }
        }
    }

    private func saveConfiguration() {
        guard hasModifiedConfiguration else {
            return
        }

        let payload = draftConfiguration
        isSavingConfiguration = true
        render()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }

            let result: Result<Void, Error>
            do {
                try WFPluginBridge.saveConfiguration(payload, forPluginNamed: self.pluginIdentifier)
                result = .success(())
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.isSavingConfiguration = false
                switch result {
                case .success:
                    self.reloadConfiguration()
                    self.store.loadPairingSettings()
                    self.store.refreshCurrentCompatibility(resetLatestUpdate: false)
                    self.store.alert = Alert(
                        title: L("alert.success.title"),
                        message: L("alert.settingsSaved.message")
                    )
                case let .failure(error):
                    self.store.alert = Alert(title: self.pageTitle(plugin: self.currentPlugin), message: error.localizedDescription)
                }
                self.render()
            }
        }
    }

    private func restoreSavedConfiguration() {
        draftConfiguration = defaultConfiguration()
        for (key, value) in savedConfiguration {
            draftConfiguration[key] = value
        }
        render()
    }

    private func useDefaultConfiguration() {
        draftConfiguration = defaultConfiguration()
        render()
    }

    private var hasModifiedConfiguration: Bool {
        !configurationEquals(draftConfiguration, savedConfigurationWithDefaults())
    }

    private func savedConfigurationWithDefaults() -> [String: Any] {
        var configuration = defaultConfiguration()
        for (key, value) in savedConfiguration {
            configuration[key] = value
        }
        return configuration
    }

    private func defaultConfiguration() -> [String: Any] {
        var configuration: [String: Any] = [:]
        for control in allControlDescriptors() {
            guard let key = stringValue(control[PluginConfigurationControlKey.key], fallback: nil) else {
                continue
            }
            switch stringValue(control[PluginConfigurationControlKey.type], fallback: "") {
            case PluginConfigurationControlType.toggle:
                configuration[key] = NSNumber(value: boolValue(control[PluginConfigurationControlKey.defaultValue], fallback: false))
            default:
                let defaultValue = intValue(control[PluginConfigurationControlKey.defaultValue], fallback: intValue(control[PluginConfigurationControlKey.minimumValue], fallback: 0))
                configuration[key] = NSNumber(value: defaultValue)
            }
        }
        return configuration
    }

    private func sectionDescriptors() -> [[String: Any]] {
        dictionaryArray(configurationPage[PluginConfigurationPageKey.sections])
    }

    private func controlDescriptors(in section: [String: Any]) -> [[String: Any]] {
        dictionaryArray(section[PluginConfigurationSectionKey.controls])
    }

    private func allControlDescriptors() -> [[String: Any]] {
        sectionDescriptors().flatMap(controlDescriptors)
    }

    private func rangeForControl(_ control: [String: Any]) -> ClosedRange<Int> {
        var minimum = intValue(control[PluginConfigurationControlKey.minimumValue], fallback: 0)
        if let minimumValueKey = stringValue(control[PluginConfigurationControlKey.minimumValueKey], fallback: nil) {
            minimum = max(minimum, intValue(draftConfiguration[minimumValueKey], fallback: minimum))
        }
        let maximum = max(minimum, intValue(control[PluginConfigurationControlKey.maximumValue], fallback: minimum))
        return minimum ... maximum
    }

    private func dictionaryArray(_ value: Any?) -> [[String: Any]] {
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries
        }
        if let dictionaries = value as? [NSDictionary] {
            return dictionaries.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private func stringValue(_ value: Any?, fallback: String?) -> String? {
        if let string = value as? String, !string.isEmpty {
            return string
        }
        return fallback
    }

    private func intValue(_ value: Any?, fallback: Int) -> Int {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let integer = value as? Int {
            return integer
        }
        if let string = value as? String, let integer = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return integer
        }
        return fallback
    }

    private func boolValue(_ value: Any?, fallback: Bool) -> Bool {
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let boolean = value as? Bool {
            return boolean
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                break
            }
        }
        return fallback
    }

    private func configurationEquals(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        NSDictionary(dictionary: lhs).isEqual(NSDictionary(dictionary: rhs))
    }
}
