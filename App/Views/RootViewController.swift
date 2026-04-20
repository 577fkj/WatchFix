import Combine
import UIKit

private struct MenuItem {
    let title: String
    let symbolName: String
}

private enum Screen: Int, CaseIterable {
    case compatibility
    case features
    case restart
    case logs
    case debug
    case about

    var item: MenuItem {
        switch self {
        case .compatibility:
            return MenuItem(
                title: L("landing.compatibility.title"),
                symbolName: "checkmark.shield.fill"
            )
        case .features:
            return MenuItem(
                title: L("landing.features.title"),
                symbolName: "slider.horizontal.3"
            )
        case .restart:
            return MenuItem(
                title: L("landing.restart.title"),
                symbolName: "arrow.clockwise.circle.fill"
            )
        case .logs:
            return MenuItem(
                title: L("landing.logs.title"),
                symbolName: "text.alignleft"
            )
        case .debug:
            return MenuItem(
                title: L("landing.debug.title"),
                symbolName: "ladybug.fill"
            )
        case .about:
            return MenuItem(
                title: L("landing.about.title"),
                symbolName: "info.circle.fill"
            )
        }
    }
}

final class RootViewController: UITableViewController {
    private let store: Store
    private var cancellables = Set<AnyCancellable>()

    init(store: Store) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("landing.title")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "MenuCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 84
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refreshTapped)
        )
        bindStore()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    @objc private func refreshTapped() {
        store.refreshAll()
    }

    private func bindStore() {
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Screen.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MenuCell", for: indexPath)
        let screen = Screen(rawValue: indexPath.row) ?? .compatibility
        let item = screen.item

        var content = UIListContentConfiguration.subtitleCell()
        content.text = item.title
        content.secondaryText = detail(for: screen)
        content.secondaryTextProperties.numberOfLines = 0
        content.image = UIImage(systemName: item.symbolName)
        content.imageProperties.tintColor = view.tintColor
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let screen = Screen(rawValue: indexPath.row) ?? .compatibility
        let controller: UIViewController
        switch screen {
        case .compatibility:
            controller = CompatibilityViewController(store: store)
        case .features:
            controller = FeatureViewController(store: store)
        case .restart:
            controller = RestartViewController(store: store)
        case .logs:
            controller = LogsViewController(store: store)
        case .debug:
            controller = DebugViewController(store: store)
        case .about:
            controller = AboutViewController(store: store)
        }

        navigationController?.pushViewController(controller, animated: true)
    }

    private func detail(for screen: Screen) -> String {
        switch screen {
        case .compatibility:
            return compatibilityDetail()
        case .features:
            return featuresDetail()
        case .restart:
            return restartDetail()
        case .logs:
            return logsDetail()
        case .debug:
            return debugDetail()
        case .about:
            return aboutDetail()
        }
    }

    private func compatibilityDetail() -> String {
        if store.isRefreshingCompatibility {
            return L("landing.compatibility.status.loading")
        }

        guard let report = store.currentReport else {
            return L("landing.compatibility.status.empty")
        }

        if let watchOSVersion = report.watchOSVersion {
            return LF("landing.compatibility.status.watchVersion", report.watchName, watchOSVersion, report.state.title)
        }

        return LF("landing.compatibility.status.watch", report.watchName, report.state.title)
    }

    private func featuresDetail() -> String {
        let installedCount = store.plugins.filter { $0.available && !$0.isTool }.count
        let knownFixCount = store.plugins.filter { !$0.isTool }.count
        return LF("landing.features.status.plugins", installedCount, knownFixCount)
    }

    private func restartDetail() -> String {
        if store.isRestartingWatch {
            return L("landing.restart.status.restartingWatch")
        }

        if store.isRestartingServices {
            return L("landing.restart.status.restartingServices")
        }

        if store.isRefreshingCompatibility {
            return L("landing.restart.status.loading")
        }

        guard let report = store.currentReport, report.hasActiveWatch else {
            return L("landing.restart.status.unavailable")
        }

        return LF("landing.restart.status.ready", report.watchName)
    }

    private func logsDetail() -> String {
        if store.isLoadingLogs {
            return L("landing.logs.status.loading")
        }

        let statusText = store.isPluginLoggingEnabled
            ? L("landing.logs.status.enabled")
            : L("landing.logs.status.disabled")
        let countText = store.pluginLogs.isEmpty
            ? L("landing.logs.status.empty")
            : LF("landing.logs.status.count", store.pluginLogs.count)
        return [statusText, countText].joined(separator: "\n")
    }

    private func aboutDetail() -> String {
        L("landing.about.detail")
    }

    private func debugDetail() -> String {
        L("landing.debug.detail")
    }
}
