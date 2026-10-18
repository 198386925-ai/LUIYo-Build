import UIKit

/// Server-backed access gate: wraps the real app and keeps it hidden until the
/// backend accepts the stored token (or a newly redeemed activation code).
final class ActivationGateViewController: UIViewController {
    private let session: ActivationSession
    private let shell: MainShellViewController

    init(endpoint: URL) {
        session = ActivationSession(endpoint: endpoint)
        shell = MainShellViewController()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { session.stop() }

    override func viewDidLoad() {
        super.viewDidLoad()
        shell.setAuthorization(false)
        shell.onLicenseSubmitted = { [weak self] code in self?.session.redeem(code: code) }
        shell.onPageChanged = { [weak self] page in self?.session.currentPage = page }

        addChild(shell)
        shell.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shell.view)
        NSLayoutConstraint.activate([
            shell.view.topAnchor.constraint(equalTo: view.topAnchor),
            shell.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            shell.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shell.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        shell.didMove(toParent: self)

        session.onState = { [weak self] state in self?.apply(state) }
        session.start()
    }

    private func apply(_ state: ActivationState) {
        switch state {
        case .authorized:
            shell.setAuthorization(true)
        case .unauthorized(let message):
            shell.setAuthorization(false, message: message)
        case .checking(let message):
            shell.setAuthorization(false, message: message, busy: true)
        case .versionBlocked(let message, let reason):
            shell.setAuthorization(false, message: message)
            BlockedPopupWindow.show(title: "版本已被禁用", description: message,
                                    reasonLabel: "禁用原因", reason: reason,
                                    fontName: shell.currentThemeFont?.fontName)
        case .banned(let reason):
            shell.setAuthorization(false, message: "设备已被拉黑")
            BlockedPopupWindow.show(title: "设备已被拉黑",
                                    description: "当前设备已被限制使用，确认后退出LUIYo",
                                    reasonLabel: "拉黑原因", reason: reason,
                                    fontName: shell.currentThemeFont?.fontName)
        }
    }
}
