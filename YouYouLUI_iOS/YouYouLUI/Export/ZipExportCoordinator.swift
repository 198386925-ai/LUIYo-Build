import UIKit

/// Export flow: rename the ZIP produced by the web engine, then hand the file
/// to the system share sheet.
final class ZipExportCoordinator {
    static let defaultFileName = "优优LUI图标包"

    private weak var presenter: UIViewController?

    /// The web engine applies the chosen name before producing the blob.
    var onNameChosen: ((String) -> Void)?

    init(presenter: UIViewController) { self.presenter = presenter }

    /// Asks for the export file name.
    func askFileName(default name: String) {
        guard let presenter, presenter.presentedViewController == nil else { return }
        let alert = UIAlertController(title: "导出 ZIP", message: "修改文件名", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = name
            field.placeholder = Self.defaultFileName
            field.accessibilityIdentifier = "zipExportName"
            field.clearButtonMode = .whileEditing
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "分享", style: .default) { [weak self, weak alert] _ in
            let value = alert?.textFields?.first?.text ?? Self.defaultFileName
            let share: () -> Void = { [weak self] in self?.onNameChosen?(value) }
            // Finish the name alert before WebKit can request the share sheet.
            if let alert, presenter.presentedViewController === alert {
                alert.dismiss(animated: false, completion: share)
            } else {
                share()
            }
        })
        presenter.present(alert, animated: true)
    }

    /// Writes the ZIP to a temporary file and opens the share sheet.
    func share(data: Data, fileName rawName: String) {
        guard let presenter else { return }
        let safeName = rawName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let fileName = safeName.lowercased().hasSuffix(".zip") ? safeName : safeName + ".zip"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            AlertPresenter.notice(title: "分享失败", message: error.localizedDescription, on: presenter)
            return
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.view.accessibilityIdentifier = "zipShareSheet"
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.maxY - 40, width: 1, height: 1)
        }
        presenter.present(activity, animated: true)
    }
}
