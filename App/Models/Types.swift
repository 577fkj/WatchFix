import Foundation
import UIKit

func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: arguments)
}

enum WatchCompatibilityState: String {
    case compatible
    case needsPairingSupport
    case indeterminate
    case unavailable

    var tintColor: UIColor {
        switch self {
        case .compatible:
            return .systemGreen
        case .needsPairingSupport:
            return .systemOrange
        case .indeterminate:
            return .systemYellow
        case .unavailable:
            return .systemGray
        }
    }

    var symbolName: String {
        switch self {
        case .compatible:
            return "checkmark.circle.fill"
        case .needsPairingSupport:
            return "link.badge.plus"
        case .indeterminate:
            return "questionmark.circle.fill"
        case .unavailable:
            return "minus.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .compatible:
            return L("compatibility.state.compatible")
        case .needsPairingSupport:
            return L("compatibility.state.needs")
        case .indeterminate:
            return L("compatibility.state.indeterminate")
        case .unavailable:
            return L("compatibility.state.unavailable")
        }
    }
}

struct PairingCompatibilitySettings: Equatable {
    var minVersion: Int = 4
    var maxVersion: Int = 24
    var helloThreshold: Int = 18

    init() {}

    init(dictionary: [String: NSNumber]) {
        minVersion = dictionary["PairingCompatibilityMinVersion"]?.intValue ?? 4
        maxVersion = dictionary["PairingCompatibilityMaxVersion"]?.intValue ?? 24
        helloThreshold = dictionary["PairingCompatibilityHelloThreshold"]?.intValue ?? 18
    }

    var bridgeValue: [String: NSNumber] {
        [
            "PairingCompatibilityMinVersion": NSNumber(value: minVersion),
            "PairingCompatibilityMaxVersion": NSNumber(value: maxVersion),
            "PairingCompatibilityHelloThreshold": NSNumber(value: helloThreshold),
        ]
    }
}

struct OSRestriction: Hashable {
    let minimumSystemVersion: Int
    let maximumSystemVersion: Int
    let minimumWatchOSVersion: Int
}

struct PluginMetadata: Hashable {
    let identifier: String
    let title: String
    let detail: String
    let symbolName: String
    let shortVersion: String
    let buildVersion: String
    let scopeIdentifier: String
    let minimumSystemVersion: Int
    let maximumSystemVersion: Int
    let minimumWatchOSVersion: Int
    let osRestrictions: [OSRestriction]
    let nanoCapabilities: [String]
    let nanoCapabilitiesAnyPredicate: Bool
    let isTool: Bool
    let hasInstallableContent: Bool
    let hasConfigurationInterface: Bool
}

struct PluginValidation: Hashable {
    enum State: Hashable {
        case compatible
        case incompatible
        case indeterminate
    }

    let state: State
    let message: String?

    static let compatible = PluginValidation(state: .compatible, message: nil)
}

struct PluginState: Identifiable {
    let metadata: PluginMetadata
    var enabled: Bool
    var available: Bool
    var installedVersion: String?
    var installedBuildVersion: String?
    var needsUpdate: Bool
    var validation: PluginValidation

    var id: String { metadata.identifier }
    var title: String { metadata.title }
    var detail: String { metadata.detail }
    var isTool: Bool { metadata.isTool }
    var validationMessage: String? { validation.message }
    var updateMessage: String? {
        guard needsUpdate else {
            return nil
        }
        guard let installedBuildVersion, !installedBuildVersion.isEmpty else {
            return LF("features.plugins.update.required.unknown", Catalog.displayVersion(shortVersion: metadata.shortVersion, buildVersion: metadata.buildVersion))
        }
        return LF(
            "features.plugins.update.required",
            Catalog.displayVersion(shortVersion: installedVersion, buildVersion: installedBuildVersion),
            Catalog.displayVersion(shortVersion: metadata.shortVersion, buildVersion: metadata.buildVersion)
        )
    }
    var canInstall: Bool { validation.state != .incompatible }
}

struct WatchCompatibilityReport {
    let source: WFCompatibilityReportSource
    let state: WatchCompatibilityState
    let hasActiveWatch: Bool
    let watchName: String
    let productType: String?
    let watchOSVersion: String?
    let chipID: String?
    let deviceMaxCompatibilityVersion: Int?
    let systemMinCompatibilityVersion: Int?
    let systemMaxCompatibilityVersion: Int?
    let inferred: Bool
    let rawDescription: String?

    init(_ report: WFCompatibilityReport) {
        source = report.source
        switch report.state {
        case .compatible:         state = .compatible
        case .needsPairingSupport: state = .needsPairingSupport
        case .unavailable:         state = .unavailable
        default:                   state = .indeterminate
        }
        hasActiveWatch = report.hasActiveWatch
        watchName = report.watchName.isEmpty ? "Apple Watch" : report.watchName
        productType = report.productType
        watchOSVersion = report.watchOSVersion
        chipID = report.chipID
        deviceMaxCompatibilityVersion = report.deviceMaxCompatibilityVersion?.intValue
        systemMinCompatibilityVersion = report.systemMinCompatibilityVersion?.intValue
        systemMaxCompatibilityVersion = report.systemMaxCompatibilityVersion?.intValue
        inferred = report.inferred
        rawDescription = report.rawDescription
    }

    var sourceLabel: String {
        switch source {
        case .magicCode:
            return L("compatibility.source.magiccode")
        case .registry:
            return L("compatibility.source.registry")
        @unknown default:
            return L("compatibility.source.registry")
        }
    }

    var detailText: String {
        switch state {
        case .compatible:
            return inferred ? L("compatibility.detail.compatible.inferred") : L("compatibility.detail.compatible")
        case .needsPairingSupport:
            return inferred ? L("compatibility.detail.needs.inferred") : L("compatibility.detail.needs")
        case .indeterminate:
            return L("compatibility.detail.indeterminate")
        case .unavailable:
            return L("compatibility.detail.unavailable")
        }
    }
}

struct LatestUpdateStatus {
    let state: WatchCompatibilityState
    let hasUpdate: Bool
    let inferred: Bool
    let updateName: String?
    let updateVersion: String?
    let buildVersion: String?
    let marketingVersion: String?
    let productSystemName: String?
    let publisher: String?
    let osName: String?
    let documentationID: String?
    let downloadSize: Int64?
    let preparationSize: Int64?
    let installationSize: Int64?
    let totalRequiredFreeSpace: Int64?
    let manifestLength: Int?
    let terms: Bool?
    let installTonightScheduled: Bool?
    let displayTermsRequested: Bool?

    private init(state: WatchCompatibilityState, hasUpdate: Bool, inferred: Bool, result: [String: Any]) {
        self.state = state
        self.hasUpdate = hasUpdate
        self.inferred = inferred
        self.updateName = result["updateName"] as? String
        self.updateVersion = result["updateVersion"] as? String
        self.buildVersion = result["buildVersion"] as? String
        self.marketingVersion = result["marketingVersion"] as? String
        self.productSystemName = result["productSystemName"] as? String
        self.publisher = result["publisher"] as? String
        self.osName = result["osName"] as? String
        self.documentationID = result["documentationID"] as? String
        self.downloadSize = (result["downloadSize"] as? NSNumber).map { $0.int64Value }
        self.preparationSize = (result["preparationSize"] as? NSNumber).map { $0.int64Value }
        self.installationSize = (result["installationSize"] as? NSNumber).map { $0.int64Value }
        self.totalRequiredFreeSpace = (result["totalRequiredFreeSpace"] as? NSNumber).map { $0.int64Value }
        self.manifestLength = (result["manifestLength"] as? NSNumber).map { $0.intValue }
        self.terms = (result["terms"] as? NSNumber)?.boolValue
        self.installTonightScheduled = (result["installTonightScheduled"] as? NSNumber)?.boolValue
        self.displayTermsRequested = (result["displayTermsRequested"] as? NSNumber)?.boolValue
    }

    init(state: WatchCompatibilityState, hasUpdate: Bool, inferred: Bool) {
        self.init(state: state, hasUpdate: hasUpdate, inferred: inferred, result: [:])
    }

    static func from(result: [String: Any]?, currentReport: WatchCompatibilityReport?) -> LatestUpdateStatus {
        guard let result else {
            return LatestUpdateStatus(state: .unavailable, hasUpdate: false, inferred: false)
        }

        let hasUpdate = (result["hasUpdate"] as? NSNumber)?.boolValue ?? false
        let needsPhoneUpdate = (result["needsPhoneUpdate"] as? NSNumber)?.boolValue ?? false

        if needsPhoneUpdate {
            return LatestUpdateStatus(state: .needsPairingSupport, hasUpdate: true, inferred: false, result: result)
        }

        guard hasUpdate else {
            return LatestUpdateStatus(state: .unavailable, hasUpdate: false, inferred: false)
        }

        let updateName = result["updateName"] as? String
        let updateVersion = result["updateVersion"] as? String

        guard let currentReport, let currentVersion = currentReport.watchOSVersion else {
            return LatestUpdateStatus(state: .indeterminate, hasUpdate: true, inferred: true, result: result)
        }

        guard let updateMajor = Self.majorVersion(from: updateName ?? updateVersion),
              let currentMajor = Self.majorVersion(from: currentVersion) else {
            return LatestUpdateStatus(state: .indeterminate, hasUpdate: true, inferred: true, result: result)
        }

        if updateMajor == currentMajor {
            return LatestUpdateStatus(state: currentReport.state, hasUpdate: true, inferred: true, result: result)
        }

        return LatestUpdateStatus(state: .indeterminate, hasUpdate: true, inferred: true, result: result)
    }

    private static func majorVersion(from text: String?) -> Int? {
        guard let text else {
            return nil
        }

        let pattern = #"(\d+)(?:\.\d+){0,2}"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return Int(text[range])
    }

    var title: String {
        if !hasUpdate {
            return L("update.none.title")
        }
        switch state {
        case .compatible:
            return L("update.state.compatible")
        case .needsPairingSupport:
            return L("update.state.needs")
        case .indeterminate:
            return L("update.state.indeterminate")
        case .unavailable:
            return L("update.none.title")
        }
    }

    var detailText: String {
        if !hasUpdate {
            return L("update.none.detail")
        }
        if inferred {
            return L("update.detail.inferred")
        }
        switch state {
        case .compatible:
            return L("update.detail.compatible")
        case .needsPairingSupport:
            return L("update.detail.needs")
        case .indeterminate, .unavailable:
            return L("update.detail.indeterminate")
        }
    }
}

struct Alert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum Catalog {
    private static let bundledPlugins: [PluginMetadata] = loadBundledPlugins()

    static func requiredCapabilityIdentifiers() -> [String] {
        Array(Set(bundledPlugins.flatMap(\.nanoCapabilities))).sorted()
    }

    static func metadata(for identifier: String) -> PluginMetadata {
        bundledPlugins.first(where: { $0.identifier == identifier }) ?? PluginMetadata(
            identifier: identifier,
            title: identifier,
            detail: identifier,
            symbolName: symbolName(forScopeIdentifier: identifier),
            shortVersion: "",
            buildVersion: "",
            scopeIdentifier: identifier,
            minimumSystemVersion: 0,
            maximumSystemVersion: 0,
            minimumWatchOSVersion: 0,
            osRestrictions: [],
            nanoCapabilities: [],
            nanoCapabilitiesAnyPredicate: false,
            isTool: false,
            hasInstallableContent: true,
            hasConfigurationInterface: false
        )
    }

    static func merge(
        states: [String: Bool],
        validationSnapshot: [String: Any],
        installedVersions: [String: [String: String]]
    ) -> [PluginState] {
        let known = Dictionary(uniqueKeysWithValues: bundledPlugins.map { ($0.identifier, $0) })
        let identifiers = Set(states.keys).union(bundledPlugins.map(\.identifier))
        return identifiers
            .sorted()
            .map { identifier in
                let metadata = known[identifier] ?? metadata(for: identifier)
                let stateValue = states[identifier] ?? (metadata.hasInstallableContent ? false : true)
                let installedMetadata = installedVersions[identifier]
                let available = metadata.hasInstallableContent
                    ? (stateValue || installedMetadata != nil)
                    : true
                return PluginState(
                    metadata: metadata,
                    enabled: stateValue,
                    available: available,
                    installedVersion: installedMetadata?["version"],
                    installedBuildVersion: installedMetadata?["buildVersion"],
                    needsUpdate: pluginNeedsUpdate(metadata: metadata, installedMetadata: installedMetadata, isInstalled: available),
                    validation: validation(for: metadata, validationSnapshot: validationSnapshot, isInstalled: available)
                )
            }
    }

    private static func loadBundledPlugins() -> [PluginMetadata] {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL else {
            return []
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: pluginsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { $0.pathExtension.lowercased() == "wffix" }
            .compactMap(metadata(for:))
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private static func metadata(for bundleURL: URL) -> PluginMetadata? {
        let infoURL = bundleURL.appendingPathComponent("Info.plist")
        guard
            let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
            let manifest = info["WFPluginManifest"] as? [String: Any]
        else {
            return nil
        }

        let identifier = bundleURL.deletingPathExtension().lastPathComponent
        let titleKey = manifest["WFPluginTitle"] as? String ?? identifier
        let detailKey = manifest["WFPluginDetail"] as? String ?? identifier
        let title = localizedPluginValue(bundleURL: bundleURL, key: titleKey)
        let detail = localizedPluginValue(bundleURL: bundleURL, key: detailKey)
        let scopeIdentifier = manifest["WFPluginScopeIdentifier"] as? String ?? identifier

        return PluginMetadata(
            identifier: identifier,
            title: title,
            detail: detail,
            symbolName: symbolName(forScopeIdentifier: scopeIdentifier),
            shortVersion: info["WFPluginVersion"] as? String ?? info["CFBundleShortVersionString"] as? String ?? "",
            buildVersion: info["WFPluginBuildVersion"] as? String ?? info["CFBundleVersion"] as? String ?? "",
            scopeIdentifier: scopeIdentifier,
            minimumSystemVersion: (manifest["WFPluginMinimumSystemVersion"] as? NSNumber)?.intValue ?? 0,
            maximumSystemVersion: (manifest["WFPluginMaximumSystemVersion"] as? NSNumber)?.intValue ?? 0,
            minimumWatchOSVersion: (manifest["WFPluginMinimumWatchOSVersion"] as? NSNumber)?.intValue ?? 0,
            osRestrictions: (manifest["WFPluginOSRestrictions"] as? [[String: Any]] ?? []).compactMap { dict in
                guard let max = (dict["WFPluginMaximumSystemVersion"] as? NSNumber)?.intValue else { return nil }
                return OSRestriction(
                    minimumSystemVersion: (dict["WFPluginMinimumSystemVersion"] as? NSNumber)?.intValue ?? 0,
                    maximumSystemVersion: max,
                    minimumWatchOSVersion: (dict["WFPluginMinimumWatchOSVersion"] as? NSNumber)?.intValue ?? 0
                )
            },
            nanoCapabilities: (manifest["WFPluginNanoCapabilities"] as? [String] ?? []).map { $0.uppercased() },
            nanoCapabilitiesAnyPredicate: (manifest["WFPluginNanoCapabilitiesAnyPredicate"] as? NSNumber)?.boolValue ?? false,
            isTool: (manifest["WFPluginPresentAsTool"] as? NSNumber)?.boolValue ?? false,
            hasInstallableContent: (manifest["WFPluginHasInstallableContent"] as? NSNumber)?.boolValue ?? true,
            hasConfigurationInterface: WFPluginBridge.pluginHasConfigurationInterface(named: identifier)
        )
    }

    private static func localizedPluginValue(bundleURL: URL, key: String) -> String {
        if let bundle = Bundle(url: bundleURL) {
            let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
            if localized != key {
                return localized
            }

            if
                let englishPath = bundle.path(forResource: "en", ofType: "lproj"),
                let englishBundle = Bundle(path: englishPath)
            {
                let englishLocalized = englishBundle.localizedString(forKey: key, value: nil, table: nil)
                if englishLocalized != key {
                    return englishLocalized
                }
            }
        }

        return key
    }

    private static func symbolName(forScopeIdentifier scopeIdentifier: String) -> String {
        return "puzzlepiece.extension"
    }

    private static func validation(
        for metadata: PluginMetadata,
        validationSnapshot: [String: Any],
        isInstalled: Bool = false
    ) -> PluginValidation {
        var failures: [String] = []
        var pending: [String] = []
        let capabilityNumbers = validationSnapshot["capabilities"] as? [String: NSNumber] ?? [:]
        let capabilityStates = capabilityNumbers.reduce(into: [String: Bool]()) { partialResult, entry in
            partialResult[entry.key.uppercased()] = entry.value.boolValue
        }
        let currentWatchVersion = (validationSnapshot["encodedWatchOSVersion"] as? NSNumber)?.intValue

        if metadata.minimumSystemVersion > 0 && currentSystemVersion() < metadata.minimumSystemVersion {
            failures.append(LF("features.plugins.validation.system", formattedVersion(metadata.minimumSystemVersion)))
        }

        if metadata.maximumSystemVersion > 0 && currentSystemVersion() > metadata.maximumSystemVersion {
            if isInstalled {
                // 已安装时仅显示警告，不阻止卸载
                pending.append(LF("features.plugins.validation.system.maximum", formattedVersion(metadata.maximumSystemVersion)))
            } else {
                failures.append(LF("features.plugins.validation.system.maximum", formattedVersion(metadata.maximumSystemVersion)))
            }
        }

        if metadata.minimumWatchOSVersion > 0 {
            if let currentWatchVersion {
                if currentWatchVersion < metadata.minimumWatchOSVersion {
                    failures.append(LF("features.plugins.validation.watch", formattedVersion(metadata.minimumWatchOSVersion)))
                }
            } else {
                pending.append(LF("features.plugins.validation.watch.unknown", formattedVersion(metadata.minimumWatchOSVersion)))
            }
        }

        if !metadata.osRestrictions.isEmpty {
            let currentOS = currentSystemVersion()
            // 找出所有 OS 范围匹配的规则
            let osMatchingRules = metadata.osRestrictions.filter { rule in
                (rule.minimumSystemVersion == 0 || currentOS >= rule.minimumSystemVersion) &&
                currentOS <= rule.maximumSystemVersion
            }
            if osMatchingRules.isEmpty {
                // 当前 OS 不在任何规则的范围内
                if isInstalled {
                    pending.append(L("features.plugins.validation.os.restrictions"))
                } else {
                    failures.append(L("features.plugins.validation.os.restrictions"))
                }
            } else {
                // 在所有 OS 匹配的规则中，只要有一条 watchOS 也满足即可
                let fullyMatchingRule = osMatchingRules.first { rule in
                    guard rule.minimumWatchOSVersion > 0 else { return true }
                    guard let currentWatchVersion else { return false }
                    return currentWatchVersion >= rule.minimumWatchOSVersion
                }
                if fullyMatchingRule == nil {
                    // 没有一条规则完全满足
                    let hasUnknownWatch = currentWatchVersion == nil
                    if hasUnknownWatch {
                        let minWatch = osMatchingRules.compactMap { $0.minimumWatchOSVersion > 0 ? $0.minimumWatchOSVersion : nil }.min()
                        if let minWatch {
                            pending.append(LF("features.plugins.validation.watch.unknown", formattedVersion(minWatch)))
                        }
                    } else {
                        let minWatch = osMatchingRules.compactMap { $0.minimumWatchOSVersion > 0 ? $0.minimumWatchOSVersion : nil }.min()
                        if let minWatch {
                            failures.append(LF("features.plugins.validation.watch", formattedVersion(minWatch)))
                        } else {
                            failures.append(L("features.plugins.validation.os.restrictions"))
                        }
                    }
                }
            }
        }

        if !metadata.nanoCapabilities.isEmpty {
            let supportedStates = metadata.nanoCapabilities.compactMap { capabilityStates[$0.uppercased()] }
            if supportedStates.count == metadata.nanoCapabilities.count {
                let isSupported = metadata.nanoCapabilitiesAnyPredicate
                    ? supportedStates.contains(true)
                    : !supportedStates.contains(false)
                if !isSupported {
                    failures.append(L("features.plugins.validation.capability"))
                }
            } else {
                pending.append(L("features.plugins.validation.capability.unknown"))
            }
        }

        if !failures.isEmpty {
            return PluginValidation(state: .incompatible, message: failures.joined(separator: "\n"))
        }
        if !pending.isEmpty {
            return PluginValidation(state: .indeterminate, message: pending.joined(separator: "\n"))
        }
        return .compatible
    }

    private static func pluginNeedsUpdate(metadata: PluginMetadata, installedMetadata: [String: String]?, isInstalled: Bool) -> Bool {
        if !isInstalled || metadata.isTool || !metadata.hasInstallableContent {
            return false
        }

        if metadata.buildVersion.isEmpty {
            return false
        }

        guard let installedBuildVersion = installedMetadata?["buildVersion"], !installedBuildVersion.isEmpty else {
            return true
        }

        return installedBuildVersion != metadata.buildVersion
    }

    private static func formattedVersion(_ encodedVersion: Int) -> String {
        let major = (encodedVersion >> 16) & 0xFF
        let minor = (encodedVersion >> 8) & 0xFF
        let patch = encodedVersion & 0xFF
        if patch > 0 {
            return "\(major).\(minor).\(patch)"
        }
        return "\(major).\(minor)"
    }

    private static func currentSystemVersion() -> Int {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return (version.majorVersion << 16) | (version.minorVersion << 8) | version.patchVersion
    }

    static func displayVersion(shortVersion: String?, buildVersion: String?) -> String {
        let shortValue = shortVersion ?? ""
        let buildValue = buildVersion ?? ""
        if buildValue.isEmpty {
            return shortValue
        }
        if shortValue.isEmpty || shortValue == buildValue {
            return buildValue
        }
        return "\(shortValue) (\(buildValue))"
    }
}
