import UIKit

final class FeatureViewController: WFScrollStackViewController {
    init(store: Store) {
        super.init(store: store, title: L("landing.features.title"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func render() {
        resetContent()

        let installedPlugins = store.plugins
            .filter { $0.available && !$0.isTool }
            .sorted { lhs, rhs in
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        let unavailablePlugins = store.plugins
            .filter { !$0.available && !$0.isTool }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        let toolPlugins = store.plugins
            .filter(\.isTool)
            .sorted { lhs, rhs in
                if lhs.available != rhs.available {
                    return lhs.available && !rhs.available
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        let knownFixCount = installedPlugins.count + unavailablePlugins.count
        let installedPluginIDs = installedPlugins.map(\.id)
        let installablePluginIDs = unavailablePlugins.filter(\.canInstall).map(\.id)
        let installedToolIDs = toolPlugins.filter(\.available).map(\.id)
        let installableToolIDs = toolPlugins.filter { !$0.available && $0.canInstall }.map(\.id)

        var installedContents: [UIView] = [
            WFMakeInfoCard(
                text: unavailablePlugins.isEmpty
                    ? LF("features.plugins.summary", installedPlugins.count, knownFixCount)
                    : [
                        LF("features.plugins.summary", installedPlugins.count, knownFixCount),
                        LF("features.plugins.unavailable.summary", unavailablePlugins.count),
                    ].joined(separator: "\n")
            ),
        ]

        if !installedPluginIDs.isEmpty {
            installedContents.append(
                WFMakeCard([
                    WFMakeActionButton(
                        title: L("common.deleteAll"),
                        systemImage: "trash",
                        isPrimary: false,
                        isLoading: installedPluginIDs.contains(where: store.isPluginBusy),
                        isEnabled: !installedPluginIDs.isEmpty,
                        tintColor: .systemRed
                    ) { [weak self] in
                        self?.store.removePlugins(identifiers: installedPluginIDs)
                    },
                ])
            )
        }

        if installedPlugins.isEmpty {
            installedContents.append(WFMakeInfoCard(text: L("features.plugins.empty")))
        }

        installedContents.append(contentsOf: installedPlugins.map { plugin in
            makePluginCard(for: plugin)
        })

        contentStack.addArrangedSubview(
            WFMakeSection(
                title: L("features.plugins.installed.title"),
                footer: L("features.plugins.footer"),
                contents: installedContents
            )
        )

        if !unavailablePlugins.isEmpty {
            var unavailableContents: [UIView] = []
            unavailableContents.append(
                WFMakeCard([
                    WFMakeActionButton(
                        title: L("common.installAll"),
                        systemImage: "square.and.arrow.down",
                        isLoading: installablePluginIDs.contains(where: store.isPluginBusy),
                        isEnabled: !installablePluginIDs.isEmpty
                    ) { [weak self] in
                        self?.store.installPlugins(identifiers: installablePluginIDs)
                    },
                ])
            )

            unavailableContents.append(contentsOf: unavailablePlugins.map { plugin in
                makePluginCard(for: plugin)
            })

            contentStack.addArrangedSubview(
                WFMakeSection(
                    title: L("features.plugins.unavailable.title"),
                    footer: L("features.plugins.unavailable.footer"),
                    contents: unavailableContents
                )
            )
        }

        if !toolPlugins.isEmpty {
            var toolContents: [UIView] = []
            var toolActionButtons: [UIView] = []
            if !installableToolIDs.isEmpty {
                toolActionButtons.append(
                    WFMakeActionButton(
                        title: L("common.installAll"),
                        systemImage: "square.and.arrow.down",
                        isLoading: installableToolIDs.contains(where: store.isPluginBusy),
                        isEnabled: !installableToolIDs.isEmpty
                    ) { [weak self] in
                        self?.store.installPlugins(identifiers: installableToolIDs)
                    }
                )
            }
            if !installedToolIDs.isEmpty {
                toolActionButtons.append(
                    WFMakeActionButton(
                        title: L("common.deleteAll"),
                        systemImage: "trash",
                        isPrimary: false,
                        isLoading: installedToolIDs.contains(where: store.isPluginBusy),
                        isEnabled: !installedToolIDs.isEmpty,
                        tintColor: .systemRed
                    ) { [weak self] in
                        self?.store.removePlugins(identifiers: installedToolIDs)
                    }
                )
            }
            if !toolActionButtons.isEmpty {
                toolContents.append(WFMakeCard(toolActionButtons))
            }

            toolContents.append(contentsOf: toolPlugins.map { plugin in
                makePluginCard(for: plugin)
            })

            contentStack.addArrangedSubview(
                WFMakeSection(
                    title: L("features.tools.title"),
                    contents: toolContents
                )
            )
        }

    }

    private func makePluginCard(for plugin: PluginState) -> UIView {
        let onConfiguration: (() -> Void)? = plugin.metadata.hasConfigurationInterface
            ? { [weak self] in
                self?.openPluginConfiguration(for: plugin)
            }
            : nil

        return WFMakePluginCard(
            plugin: plugin,
            isBusy: store.isPluginBusy(plugin.id),
            configurationTitle: L("features.plugins.configure"),
            configurationSystemImage: "slider.horizontal.3",
            isConfigurationEnabled: plugin.metadata.hasConfigurationInterface,
            onConfiguration: onConfiguration
        ) { [weak self] in
            self?.performPluginAction(for: plugin)
        }
    }

    private func performPluginAction(for plugin: PluginState) {
        if plugin.available {
            store.removePlugin(identifier: plugin.id)
        } else {
            store.installPlugin(identifier: plugin.id)
        }
    }

    private func openPluginConfiguration(for plugin: PluginState) {
        if let controller = try? WFPluginBridge.configurationViewController(forPluginNamed: plugin.id) {
            if controller.title?.isEmpty ?? true {
                controller.title = plugin.title
            }
            navigationController?.pushViewController(controller, animated: true)
            return
        }

        navigationController?.pushViewController(
            PluginConfigurationViewController(store: store, plugin: plugin),
            animated: true
        )
    }
}
