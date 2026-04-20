import Foundation
import Combine

private func WFStoreLog(_ message: String, sourceFile: String = #fileID) {
    WFLogSwift(sourceFile, "[WatchFixStore] \(message)")
}

struct WatchDebugInfo {
    let hasWatch: Bool
    let hasActiveWatch: Bool
    let properties: [String: Any]
    let capabilities: [String]

    init(dictionary: [String: Any]) {
        hasWatch = (dictionary["hasWatch"] as? NSNumber)?.boolValue ?? false
        hasActiveWatch = (dictionary["hasActiveWatch"] as? NSNumber)?.boolValue ?? false
        properties = dictionary["properties"] as? [String: Any] ?? [:]
        capabilities = dictionary["capabilities"] as? [String] ?? []
    }

    var bridgeValue: [String: Any] {
        [
            "hasWatch": hasWatch,
            "hasActiveWatch": hasActiveWatch,
            "properties": properties,
            "capabilities": capabilities,
        ]
    }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var plugins: [PluginState] = Catalog.merge(states: [:], validationSnapshot: [:], installedVersions: [:])
    @Published var pairingSettings = PairingCompatibilitySettings()
    @Published private(set) var savedPairingSettings = PairingCompatibilitySettings()
    @Published private(set) var currentReport: WatchCompatibilityReport?
    @Published private(set) var activeWatchDebugInfo: WatchDebugInfo?
    @Published private(set) var activeWatchDebugrawJSON: [String: Any]?
    @Published private(set) var scannedReport: WatchCompatibilityReport?
    @Published private(set) var latestUpdateStatus = LatestUpdateStatus(state: .unavailable, hasUpdate: false, inferred: false)
    @Published private(set) var pluginLogs: [String] = []
    @Published private(set) var isPluginLoggingEnabled = false
    @Published private(set) var isRefreshingCompatibility = false
    @Published private(set) var isRefreshingDebugSnapshot = false
    @Published private(set) var isScanningUpdate = false
    @Published private(set) var isSavingSettings = false
    @Published private(set) var isLoadingLogs = false
    @Published private(set) var isUpdatingLoggingState = false
    @Published private(set) var isClearingLogs = false
    @Published private(set) var isRestartingWatch = false
    @Published private(set) var isRestartingServices = false
    @Published private(set) var busyPluginIDs: Set<String> = []
    @Published var alert: Alert?

    private var hasLoaded = false
    private var latestUpdateScanResult: [String: Any]?
    private var pluginStatesByIdentifier: [String: Bool] = [:]
    private var installedPluginVersionsByIdentifier: [String: [String: String]] = [:]
    private var lastPluginUpdateAlertToken: String?
    private var bridgeNotificationCancellables = Set<AnyCancellable>()

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        bindBridgeNotifications()
        refreshAll()
    }

    func refreshAll() {
        loadPluginStates()
        loadPairingSettings()
        loadPluginLogs()
        refreshCurrentCompatibility()
        refreshDebugSnapshot()
    }

    func loadPluginStates() {
        var stateMap: [String: Bool] = [:]
        for (key, value) in WFPluginBridge.pluginStates() {
            stateMap[key] = value.boolValue
        }
        pluginStatesByIdentifier = stateMap
        installedPluginVersionsByIdentifier = WFPluginBridge.installedPluginVersions()
        refreshPluginCatalog()
    }

    func loadPairingSettings() {
        let settings = PairingCompatibilitySettings(dictionary: WFPluginBridge.pairingCompatibilitySettings())
        savedPairingSettings = settings
        pairingSettings = settings
    }

    func refreshCurrentCompatibility(resetLatestUpdate: Bool = true) {
        isRefreshingCompatibility = true
        if resetLatestUpdate {
            latestUpdateScanResult = nil
        }
        runBridge({
            try WatchAPI.currentCompatibilityReport()
        }, fallbackTitle: L("compatibility.section.current")) { [weak self] result in
            guard let self else {
                return
            }

            self.isRefreshingCompatibility = false
            switch result {
            case let .success(objcReport):
                let report = WatchCompatibilityReport(objcReport)
                self.currentReport = report
                self.latestUpdateStatus = LatestUpdateStatus.from(
                    result: self.latestUpdateScanResult,
                    currentReport: report
                )
                self.refreshPluginCatalog()
            case .failure:
                self.currentReport = nil
                self.latestUpdateStatus = LatestUpdateStatus.from(
                    result: self.latestUpdateScanResult,
                    currentReport: nil
                )
                self.refreshPluginCatalog()
            }
        }
    }

    func loadPluginLogs() {
        isLoadingLogs = true
        runBridge({
            WFPluginBridge.pluginLogSnapshot()
        }, fallbackTitle: L("landing.logs.title")) { [weak self] result in
            guard let self else {
                return
            }

            self.isLoadingLogs = false
            if case let .success(snapshot) = result {
                self.isPluginLoggingEnabled = (snapshot["enabled"] as? NSNumber)?.boolValue ?? false
                self.pluginLogs = snapshot["logs"] as? [String] ?? []
            }
        }
    }

    func refreshDebugInformation() {
        refreshCurrentCompatibility(resetLatestUpdate: false)
        refreshDebugSnapshot()
    }

    func refreshDebugSnapshot() {
        isRefreshingDebugSnapshot = true
        runBridge({
            WatchAPI.activeWatchDebugPayload()
        }, fallbackTitle: L("landing.debug.title")) { [weak self] result in
            guard let self else {
                return
            }

            self.isRefreshingDebugSnapshot = false
            if case let .success(payload) = result {
                let infoDictionary = payload["displayInfo"] as? [String: Any] ?? [:]
                self.activeWatchDebugInfo = WatchDebugInfo(dictionary: infoDictionary)
                self.activeWatchDebugrawJSON = payload["rawJSON"] as? [String: Any]
            }
        }
    }

    func clearScannedReport() {
        scannedReport = nil
    }

    func handleScannerResult(_ result: [String: Any]) {
        runBridge({
            try WatchAPI.compatibilityReport(forScannedResult: result)
        }, fallbackTitle: L("compatibility.section.scan")) { [weak self] bridgeResult in
            guard let self else {
                return
            }

            if case let .success(objcReport) = bridgeResult {
                self.scannedReport = WatchCompatibilityReport(objcReport)
            }
        }
    }

    func scanLatestUpdate() {
        isScanningUpdate = true
        WatchAPI.scanLatestSoftwareUpdate { [weak self] result, error in
            guard let self else {
                return
            }

            self.isScanningUpdate = false
            if let error {
                let nsError = error as NSError
                if nsError.domain == "SUBError", nsError.code == 34 {
                    let compatibilityResult: [String: Any] = [
                        "hasUpdate": NSNumber(value: true),
                        "needsPhoneUpdate": NSNumber(value: true),
                        "updateName": L("compatibility.section.latest"),
                    ]
                    self.latestUpdateScanResult = compatibilityResult
                    self.latestUpdateStatus = LatestUpdateStatus.from(
                        result: compatibilityResult,
                        currentReport: self.currentReport
                    )
                    return
                }

                self.present(error: error, title: L("compatibility.section.latest"))
                return
            }

            self.latestUpdateScanResult = result
            self.latestUpdateStatus = LatestUpdateStatus.from(result: result, currentReport: self.currentReport)
        }
    }

    func installPlugin(identifier: String) {
        installPlugins(identifiers: [identifier])
    }

    func removePlugin(identifier: String) {
        removePlugins(identifiers: [identifier])
    }

    func installPlugins(identifiers: [String]) {
        updatePluginInstallation(identifiers: identifiers, shouldInstall: true)
    }

    func removePlugins(identifiers: [String]) {
        updatePluginInstallation(identifiers: identifiers, shouldInstall: false)
    }

    func setPluginLoggingEnabled(_ enabled: Bool) {
        let previousValue = isPluginLoggingEnabled
        isPluginLoggingEnabled = enabled
        isUpdatingLoggingState = true

        runBridge({
            try WFPluginBridge.setPluginLoggingEnabled(enabled)
        }, fallbackTitle: L("logs.section.controls")) { [weak self] result in
            guard let self else {
                return
            }

            self.isUpdatingLoggingState = false
            switch result {
            case .success:
                self.loadPluginLogs()
            case .failure:
                self.isPluginLoggingEnabled = previousValue
            }
        }
    }

    func clearPluginLogs() {
        isClearingLogs = true
        runBridge({
            try WFPluginBridge.clearPluginLogs()
        }, fallbackTitle: L("logs.section.entries")) { [weak self] result in
            guard let self else {
                return
            }

            self.isClearingLogs = false
            if case .success = result {
                self.pluginLogs = []
            }
        }
    }

    func restoreSavedPairingSettings() {
        pairingSettings = savedPairingSettings
    }

    func useDefaultPairingSettings() {
        pairingSettings = PairingCompatibilitySettings()
    }

    func rebootActiveWatch() {
        isRestartingWatch = true
        runBridge({
            try WatchAPI.rebootActiveWatch()
        }, fallbackTitle: L("restart.watch.title")) { [weak self] result in
            guard let self else {
                return
            }

            self.isRestartingWatch = false
            if case .success = result {
                self.alert = Alert(
                    title: L("alert.success.title"),
                    message: L("alert.watchRebooted.message")
                )
            }
        }
    }

    func restartWatchServices() {
        isRestartingServices = true
        runBridge({
            try WFPluginBridge.restartWatchServices()
        }, fallbackTitle: L("restart.services.title")) { [weak self] result in
            guard let self else {
                return
            }

            self.isRestartingServices = false
            if case .success = result {
                self.alert = Alert(
                    title: L("alert.success.title"),
                    message: L("alert.servicesRestarted.message")
                )
                self.refreshCurrentCompatibility(resetLatestUpdate: false)
            }
        }
    }

    func isPluginBusy(_ identifier: String) -> Bool {
        busyPluginIDs.contains(identifier)
    }

    var hasModifiedPairingSettings: Bool {
        pairingSettings != savedPairingSettings
    }

    var isUsingDefaultPairingSettings: Bool {
        pairingSettings == PairingCompatibilitySettings()
    }

    private func present(error: Error, title: String) {
        alert = Alert(title: title, message: error.localizedDescription)
    }

    private func runBridge<T>(
        _ work: @escaping () throws -> T,
        fallbackTitle: String,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<T, Error>
            do {
                result = .success(try work())
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async { [weak self] in
                if case let .failure(error) = result {
                    self?.present(error: error, title: fallbackTitle)
                }
                completion(result)
            }
        }
    }

    private func bindBridgeNotifications() {
        NotificationCenter.default.publisher(for: .WFPluginBridgeDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                self.loadPluginStates()
                self.loadPairingSettings()
                self.refreshCurrentCompatibility(resetLatestUpdate: false)
                self.refreshDebugSnapshot()
            }
            .store(in: &bridgeNotificationCancellables)
    }

    private func refreshPluginCatalog() {
        let validationSnapshot = WatchAPI.activeWatchValidationSnapshot(
            forCapabilityUUIDStrings: Catalog.requiredCapabilityIdentifiers()
        )
        plugins = Catalog.merge(
            states: pluginStatesByIdentifier,
            validationSnapshot: validationSnapshot,
            installedVersions: installedPluginVersionsByIdentifier
        )
        let summary = plugins
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map {
                "\($0.id): installed=\($0.available) state=\($0.enabled) canInstall=\($0.canInstall) needsUpdate=\($0.needsUpdate) validation=\($0.validation.state)"
            }
            .joined(separator: " | ")
        WFStoreLog("Plugin catalog refreshed: \(summary)")
        // presentPluginUpdateAlertIfNeeded() // TODO: 未安装插件也报告更新，等插件管理完善后再加回这个功能
    }

    private func updatePluginInstallation(identifiers: [String], shouldInstall: Bool) {
        var seen = Set<String>()
        let targets = identifiers.filter { seen.insert($0).inserted }
        guard !targets.isEmpty else {
            return
        }

        let targetSet = Set(targets)
        guard busyPluginIDs.isDisjoint(with: targetSet) else {
            return
        }

        busyPluginIDs.formUnion(targetSet)
        runBridge({
            for identifier in targets {
                if shouldInstall {
                    try WFPluginBridge.installPluginNamed(identifier)
                } else {
                    try WFPluginBridge.removePluginNamed(identifier)
                }
            }
        }, fallbackTitle: L("features.plugins.title")) { [weak self] result in
            guard let self else {
                return
            }

            self.busyPluginIDs.subtract(targetSet)
            self.loadPluginStates()
            self.refreshCurrentCompatibility(resetLatestUpdate: false)
        }
    }

    private func presentPluginUpdateAlertIfNeeded() {
        let outdatedPlugins = plugins
            .filter { $0.available && $0.needsUpdate && !$0.isTool }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        if outdatedPlugins.isEmpty {
            lastPluginUpdateAlertToken = nil
            return
        }

        let token = outdatedPlugins
            .map { "\($0.id):\($0.installedBuildVersion ?? ""):\($0.metadata.buildVersion)" }
            .joined(separator: "|")
        if token == lastPluginUpdateAlertToken {
            return
        }

        lastPluginUpdateAlertToken = token
        let pluginNames = outdatedPlugins.map(\.title).joined(separator: "\n")
        alert = Alert(
            title: L("alert.pluginUpdate.title"),
            message: LF("alert.pluginUpdate.message", pluginNames)
        )
    }
}
