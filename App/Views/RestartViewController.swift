import UIKit

final class RestartViewController: WFScrollStackViewController {
    init(store: Store) {
        super.init(store: store, title: L("landing.restart.title"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func render() {
        resetContent()

        let hasActiveWatch = store.currentReport?.hasActiveWatch ?? false
        var watchCardContents: [UIView] = [WFMakeSecondaryLabel(L("restart.watch.detail"))]
        if !hasActiveWatch {
            watchCardContents.append(WFMakeFootnoteLabel(L("restart.watch.unavailable"), color: .systemOrange))
        }
        watchCardContents.append(
            WFMakeActionButton(
                title: L("restart.watch.button"),
                systemImage: "applewatch",
                isLoading: store.isRestartingWatch,
                isEnabled: hasActiveWatch
            ) { [weak self] in
                self?.presentWatchRestartConfirmation()
            }
        )

        let watchContents: [UIView] = [
            WFMakeCard(watchCardContents),
        ]
        contentStack.addArrangedSubview(
            WFMakeSection(title: L("restart.watch.title"), contents: watchContents)
        )

        let serviceContents: [UIView] = [
            WFMakeCard([
                WFMakeSecondaryLabel(L("restart.services.detail")),
                WFMakeActionButton(
                    title: L("restart.services.button"),
                    systemImage: "iphone",
                    isLoading: store.isRestartingServices
                ) { [weak self] in
                    self?.presentServiceRestartConfirmation()
                },
            ]),
        ]
        contentStack.addArrangedSubview(
            WFMakeSection(title: L("restart.services.title"), contents: serviceContents)
        )
    }

    private func presentWatchRestartConfirmation() {
        presentConfirmation(
            title: L("restart.watch.confirm.title"),
            message: L("restart.watch.confirm.message"),
            confirmTitle: L("restart.watch.confirm.button")
        ) { [weak self] in
            self?.store.rebootActiveWatch()
        }
    }

    private func presentServiceRestartConfirmation() {
        presentConfirmation(
            title: L("restart.services.confirm.title"),
            message: L("restart.services.confirm.message"),
            confirmTitle: L("restart.services.confirm.button")
        ) { [weak self] in
            self?.store.restartWatchServices()
        }
    }

    private func presentConfirmation(
        title: String,
        message: String,
        confirmTitle: String,
        action: @escaping () -> Void
    ) {
        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        controller.addAction(UIAlertAction(title: confirmTitle, style: .destructive) { _ in
            action()
        })
        present(controller, animated: true)
    }
}
