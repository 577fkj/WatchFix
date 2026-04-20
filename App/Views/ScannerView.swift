import AVFoundation
import UIKit

// MARK: - Scanner view controller

final class ScannerViewController: WFScrollStackViewController {
    private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private var scannerView: WFVisualPairingScannerView?
    private var hasHandledScan = false

    init(store: Store) {
        super.init(store: store, title: L("scanner.title"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L("common.done"),
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshAuthorizationStatus()
        startScanningIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scannerView?.stopScanning()
    }

    override func render() {
        resetContent()
        contentStack.addArrangedSubview(
            WFMakeCard([
                WFMakeTextLabel(L("scanner.hint"), font: .preferredFont(forTextStyle: .headline)),
            ])
        )

        if authorizationStatus == .authorized {
            contentStack.addArrangedSubview(makeScannerPreviewCard())
            if let report = store.scannedReport {
                contentStack.addArrangedSubview(WFMakeCompatibilityCard(report: report))
            } else {
                contentStack.addArrangedSubview(WFMakeInfoCard(text: L("scanner.waiting")))
            }
            if hasHandledScan || store.scannedReport != nil {
                contentStack.addArrangedSubview(
                    WFMakeCard([
                        WFMakeActionButton(
                            title: L("scanner.action.rescan"),
                            systemImage: "arrow.clockwise"
                        ) { [weak self] in
                            self?.resetScan()
                        },
                    ])
                )
            }
        } else {
            contentStack.addArrangedSubview(
                WFMakeCard([
                    WFMakeTextLabel(L("scanner.permission.title"), font: .preferredFont(forTextStyle: .headline)),
                    WFMakeSecondaryLabel(L("scanner.permission.detail")),
                    WFMakeActionButton(
                        title: L("scanner.permission.button"),
                        systemImage: "camera.viewfinder"
                    ) { [weak self] in
                        self?.requestOrOpenSettings()
                    },
                ])
            )
        }
    }

    private func makeScannerPreviewCard() -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.layer.cornerRadius = 18
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalTo: container.widthAnchor, multiplier: 4.0 / 3.0).isActive = true

        let scannerView = scannerView ?? makeScannerView()
        if scannerView.superview !== container {
            scannerView.removeFromSuperview()
            container.addSubview(scannerView)
            scannerView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                scannerView.topAnchor.constraint(equalTo: container.topAnchor),
                scannerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                scannerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                scannerView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        return container
    }

    private func makeScannerView() -> WFVisualPairingScannerView {
        let view = WFVisualPairingScannerView()
        view.scanHandler = { [weak self] result in
            DispatchQueue.main.async {
                self?.handleScan(result)
            }
        }
        scannerView = view
        return view
    }

    private func handleScan(_ result: [String: Any]) {
        guard !hasHandledScan else {
            return
        }

        hasHandledScan = true
        scannerView?.stopScanning()
        store.handleScannerResult(result)
    }

    private func resetScan() {
        hasHandledScan = false
        store.clearScannedReport()
        render()
        startScanningIfNeeded()
    }

    private func refreshAuthorizationStatus() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authorizationStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    self?.render()
                    self?.startScanningIfNeeded()
                }
            }
        } else {
            render()
        }
    }

    private func startScanningIfNeeded() {
        guard authorizationStatus == .authorized, !hasHandledScan else {
            return
        }
        scannerView?.startScanning()
    }

    private func requestOrOpenSettings() {
        switch authorizationStatus {
        case .notDetermined:
            refreshAuthorizationStatus()
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .authorized:
            startScanningIfNeeded()
        @unknown default:
            break
        }
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}
