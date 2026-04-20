import UIKit

final class LogsViewController: WFScrollStackViewController {
    init(store: Store) {
        super.init(store: store, title: L("landing.logs.title"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.loadPluginLogs()
    }

    override func render() {
        resetContent()

        let loggingDetail = store.isPluginLoggingEnabled
            ? L("logs.toggle.detail.on")
            : L("logs.toggle.detail.off")
        let controlContents: [UIView] = [
            WFMakeToggleCard(
                title: L("logs.toggle.title"),
                detail: loggingDetail,
                isOn: store.isPluginLoggingEnabled,
                isEnabled: !store.isUpdatingLoggingState
            ) { [weak self] enabled in
                self?.store.setPluginLoggingEnabled(enabled)
            },
            WFMakeCard([
                WFMakeActionButton(
                    title: L("logs.action.refresh"),
                    systemImage: "arrow.clockwise",
                    isPrimary: false,
                    isLoading: store.isLoadingLogs
                ) { [weak self] in
                    self?.store.loadPluginLogs()
                },
                WFMakeActionButton(
                    title: L("logs.action.clear"),
                    systemImage: "trash",
                    isPrimary: false,
                    isLoading: store.isClearingLogs,
                    isEnabled: !store.pluginLogs.isEmpty && !store.isClearingLogs
                ) { [weak self] in
                    self?.store.clearPluginLogs()
                },
            ]),
        ]
        contentStack.addArrangedSubview(
            WFMakeSection(title: L("logs.section.controls"), contents: controlContents)
        )

        var entryContents: [UIView] = []
        if store.isLoadingLogs && store.pluginLogs.isEmpty {
            entryContents.append(WFMakeInfoCard(text: L("logs.loading")))
        } else if store.pluginLogs.isEmpty {
            entryContents.append(WFMakeInfoCard(text: L("logs.empty")))
        } else {
            let recentLogs = Array(store.pluginLogs.suffix(150)).joined(separator: "\n")
            entryContents.append(WFMakeCodeCard(text: recentLogs))
        }

        contentStack.addArrangedSubview(
            WFMakeSection(title: L("logs.section.entries"), contents: entryContents)
        )
    }
}
