import UIKit

final class AboutViewController: WFScrollStackViewController {
    init(store: Store) {
        super.init(store: store, title: L("landing.about.title"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func render() {
        resetContent()

        contentStack.addArrangedSubview(
            WFMakeSection(
                title: L("about.section.app"),
                contents: [
                    makeHeaderCard(),
                    WFMakeCard([
                        WFMakeValueRow(title: L("about.field.name"), value: appName),
                        WFMakeValueRow(title: L("about.field.version"), value: shortVersion),
                        WFMakeValueRow(title: L("about.field.build"), value: buildVersion),
                        WFMakeValueRow(title: L("about.field.bundle"), value: bundleIdentifier),
                    ]),
                ]
            )
        )

        contentStack.addArrangedSubview(
            WFMakeSection(
                title: L("about.section.overview"),
                contents: [WFMakeInfoCard(text: L("about.overview.body"))]
            )
        )

        contentStack.addArrangedSubview(
            WFMakeSection(
                title: L("about.section.project"),
                contents: [
                    WFMakeCard([
                        WFMakeActionButton(
                            title: L("about.action.github"),
                            systemImage: "link",
                            isPrimary: false
                        ) { [weak self] in
                            self?.openExternalLink(infoKey: "WFGitHubURL")
                        },
                    ]),
                ]
            )
        )

        contentStack.addArrangedSubview(
            WFMakeSection(
                title: L("about.section.support"),
                contents: [
                    WFMakeInfoCard(text: L("about.support.body")),
                    WFMakeCard([
                        WFMakeActionButton(
                            title: L("about.action.patreon"),
                            systemImage: "heart",
                            isPrimary: false
                        ) { [weak self] in
                            self?.openExternalLink(infoKey: "WFPatreonURL")
                        },
                        WFMakeActionButton(
                            title: L("about.action.afdian"),
                            systemImage: "heart",
                            isPrimary: false
                        ) { [weak self] in
                            self?.openExternalLink(infoKey: "WFAfdianURL")
                        },
                    ]),
                ]
            )
        )
    }

    private func makeHeaderCard() -> UIView {
        let iconView = WFMakeIconTile(
            image: UIImage(named: "AppIcon60x60"),
            symbolName: "info.circle.fill",
            tintColor: .systemBlue
        )

        let titleLabel = WFMakeTextLabel(appName, font: .preferredFont(forTextStyle: .title2))
        let subtitleLabel = WFMakeSecondaryLabel(L("about.header.subtitle"))

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 6

        let headerStack = UIStackView(arrangedSubviews: [iconView, textStack])
        headerStack.axis = .horizontal
        headerStack.alignment = .top
        headerStack.spacing = 12

        return WFMakeCard([headerStack])
    }

    private var appName: String {
        bundleValue(for: "CFBundleDisplayName")
            ?? bundleValue(for: "CFBundleName")
            ?? L("landing.title")
    }

    private var shortVersion: String {
        bundleValue(for: "CFBundleShortVersionString") ?? L("about.value.unknown")
    }

    private var buildVersion: String {
        bundleValue(for: "CFBundleVersion") ?? L("about.value.unknown")
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? L("about.value.unknown")
    }

    private func bundleValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func openExternalLink(infoKey: String) {
        guard
            let urlString = bundleValue(for: infoKey),
            let url = URL(string: urlString)
        else {
            return
        }

        UIApplication.shared.open(url)
    }
}
