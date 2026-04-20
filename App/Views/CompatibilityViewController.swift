import AVFoundation
import UIKit

final class CompatibilityViewController: WFScrollStackViewController {
    // MARK: Inline scanner state
    private var isScannerVisible = false
    private var inlineScannerView: WFVisualPairingScannerView?
    private var hasHandledInlineScan = false
    private var cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    init(store: Store) {
        super.init(store: store, title: L("landing.compatibility.title"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        inlineScannerView?.stopScanning()
    }

    override func render() {
        resetContent()
        let hasActiveWatch = store.currentReport?.hasActiveWatch ?? false

        var currentContents: [UIView] = [
            WFMakeCard([
                WFMakeActionButton(
                    title: L("compatibility.action.current"),
                    systemImage: "link.circle",
                    isLoading: store.isRefreshingCompatibility
                ) { [weak self] in
                    self?.store.refreshCurrentCompatibility()
                },
            ]),
        ]

        if store.isRefreshingCompatibility {
            currentContents.append(WFMakeInfoCard(text: L("compatibility.loading.current")))
        }

        if let report = store.currentReport {
            currentContents.append(WFMakeCompatibilityCard(report: report))
        } else {
            currentContents.append(WFMakeInfoCard(text: L("compatibility.empty.current")))
        }

        contentStack.addArrangedSubview(
            WFMakeSection(title: L("compatibility.section.current"), contents: currentContents)
        )

        var latestContents: [UIView] = [
            WFMakeCard([
                WFMakeActionButton(
                    title: L("compatibility.action.latest"),
                    systemImage: "magnifyingglass.circle",
                    isLoading: store.isScanningUpdate,
                    isEnabled: hasActiveWatch && !store.isRefreshingCompatibility
                ) { [weak self] in
                    self?.store.scanLatestUpdate()
                },
            ]),
        ]

        if !hasActiveWatch && !store.isRefreshingCompatibility {
            latestContents.append(WFMakeInfoCard(text: L("compatibility.empty.latest")))
        }

        if store.isScanningUpdate {
            latestContents.append(WFMakeInfoCard(text: L("compatibility.loading.latest")))
        }

        latestContents.append(WFMakeUpdateCard(status: store.latestUpdateStatus))
        contentStack.addArrangedSubview(
            WFMakeSection(title: L("compatibility.section.latest"), contents: latestContents)
        )

        var scanContents: [UIView] = []

        if isScannerVisible {
            switch cameraAuthorizationStatus {
            case .authorized:
                scanContents.append(makeInlineScannerCard())
                if let report = store.scannedReport {
                    scanContents.append(WFMakeCompatibilityCard(report: report))
                }
                var actions: [UIView] = []
                if hasHandledInlineScan || store.scannedReport != nil {
                    actions.append(
                        WFMakeActionButton(
                            title: L("scanner.action.rescan"),
                            systemImage: "arrow.clockwise",
                            isPrimary: false
                        ) { [weak self] in
                            self?.resetInlineScan()
                        }
                    )
                }
                actions.append(
                    WFMakeActionButton(
                        title: L("scanner.action.close"),
                        systemImage: "xmark",
                        isPrimary: false
                    ) { [weak self] in
                        self?.hideScanner()
                    }
                )
                scanContents.append(WFMakeCard(actions))

            case .notDetermined:
                scanContents.append(WFMakeInfoCard(text: L("scanner.permission.requesting")))
                scanContents.append(WFMakeCard([
                    WFMakeActionButton(
                        title: L("scanner.action.close"),
                        systemImage: "xmark",
                        isPrimary: false
                    ) { [weak self] in
                        self?.hideScanner()
                    },
                ]))

            default:
                scanContents.append(WFMakeCard([
                    WFMakeTextLabel(L("scanner.permission.title"), font: .preferredFont(forTextStyle: .headline)),
                    WFMakeSecondaryLabel(L("scanner.permission.detail")),
                    WFMakeActionButton(
                        title: L("scanner.permission.button"),
                        systemImage: "camera.viewfinder"
                    ) { [weak self] in
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    },
                ]))
                scanContents.append(WFMakeCard([
                    WFMakeActionButton(
                        title: L("scanner.action.close"),
                        systemImage: "xmark",
                        isPrimary: false
                    ) { [weak self] in
                        self?.hideScanner()
                    },
                ]))
            }
        } else {
            scanContents.append(
                WFMakeCard([
                    WFMakeActionButton(
                        title: L("compatibility.action.scan"),
                        systemImage: "qrcode.viewfinder"
                    ) { [weak self] in
                        self?.showScanner()
                    },
                ])
            )
            if let report = store.scannedReport {
                scanContents.append(WFMakeCompatibilityCard(report: report))
            } else {
                scanContents.append(WFMakeInfoCard(text: L("compatibility.empty.scan")))
            }
        }

        contentStack.addArrangedSubview(
            WFMakeSection(
                title: L("compatibility.section.scan"),
                footer: isScannerVisible ? nil : L("compatibility.scan.footer"),
                contents: scanContents
            )
        )
    }

    // MARK: - Inline scanner

    private func makeInlineScannerCard() -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.layer.cornerRadius = 18
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalTo: container.widthAnchor).isActive = true

        let sv = inlineScannerView ?? makeInlineScannerView()
        if sv.superview !== container {
            sv.removeFromSuperview()
            container.addSubview(sv)
            sv.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                sv.topAnchor.constraint(equalTo: container.topAnchor),
                sv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                sv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                sv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        return container
    }

    private func makeInlineScannerView() -> WFVisualPairingScannerView {
        let view = WFVisualPairingScannerView()
        view.scanHandler = { [weak self] result in
            DispatchQueue.main.async {
                self?.handleInlineScan(result)
            }
        }
        inlineScannerView = view
        return view
    }

    private func handleInlineScan(_ result: [String: Any]) {
        guard !hasHandledInlineScan else { return }
        hasHandledInlineScan = true
        inlineScannerView?.stopScanning()
        store.handleScannerResult(result)
    }

    private func resetInlineScan() {
        hasHandledInlineScan = false
        store.clearScannedReport()
        render()
        inlineScannerView?.startScanning()
    }

    private func showScanner() {
        store.clearScannedReport()
        hasHandledInlineScan = false
        isScannerVisible = true
        cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuthorizationStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    self?.render()
                }
            }
        }
        render()
    }

    private func hideScanner() {
        isScannerVisible = false
        inlineScannerView?.stopScanning()
        inlineScannerView = nil
        render()
    }

    // Kept for backward compatibility (unused)
    private func presentScanner() {
        store.clearScannedReport()
        let controller = ScannerViewController(store: store)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .formSheet
        present(navigationController, animated: true)
    }
}
