import UIKit

/// Thin wrapper over UIAlertController so feature code never repeats boilerplate.
enum AlertPresenter {
    /// Simple notice with one confirmation button.
    static func notice(title: String = "提示", message: String, on presenter: UIViewController) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        presenter.present(alert, animated: true)
    }

    /// Confirmation dialog with a destructive action.
    static func confirm(title: String,
                        message: String?,
                        confirmTitle: String,
                        destructive: Bool = false,
                        on presenter: UIViewController,
                        handler: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: confirmTitle, style: destructive ? .destructive : .default) { _ in handler() })
        presenter.present(alert, animated: true)
    }

    /// Action sheet anchored to the center of `presenter` (iPad safe).
    static func actionSheet(title: String?,
                            message: String?,
                            on presenter: UIViewController,
                            actions: [UIAlertAction]) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        for action in actions { alert.addAction(action) }
        alert.popoverPresentationController?.sourceView = presenter.view
        alert.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1
        )
        presenter.present(alert, animated: true)
    }
}
