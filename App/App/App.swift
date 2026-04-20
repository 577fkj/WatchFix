import Combine
import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    private let store = Store()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let rootViewController = RootViewController(store: store)
        let navigationController = NavigationController(store: store, rootViewController: rootViewController)

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.tintColor = .systemBlue
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()

        store.loadIfNeeded()
        return true
    }
}

final class NavigationController: UINavigationController {
    private let store: Store
    private var cancellables = Set<AnyCancellable>()
    private var pendingAlerts: [Alert] = []
    private var isPresentingAlert = false

    init(store: Store, rootViewController: UIViewController) {
        self.store = store
        super.init(rootViewController: rootViewController)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationBar.prefersLargeTitles = true
        observeAlerts()
    }

    private func observeAlerts() {
        store.$alert
            .receive(on: RunLoop.main)
            .sink { [weak self] alert in
                guard let self, let alert else {
                    return
                }
                self.pendingAlerts.append(alert)
                self.presentNextAlertIfNeeded()
                self.store.alert = nil
            }
            .store(in: &cancellables)
    }

    private func presentNextAlertIfNeeded() {
        guard !isPresentingAlert, !pendingAlerts.isEmpty else {
            return
        }

        let presenter = topPresenter()
        guard !(presenter is UIAlertController) else {
            return
        }

        let alert = pendingAlerts.removeFirst()
        isPresentingAlert = true

        let controller = UIAlertController(title: alert.title, message: alert.message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L("common.done"), style: .default) { [weak self] _ in
            self?.isPresentingAlert = false
            self?.presentNextAlertIfNeeded()
        })
        presenter.present(controller, animated: true)
    }

    private func topPresenter() -> UIViewController {
        var controller: UIViewController = visibleViewController ?? topViewController ?? self
        while let presented = controller.presentedViewController {
            controller = presented
        }
        return controller
    }
}
