import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Photo / file picking for icon uploads, batch import, fill image and the
/// settings avatar. Results are handed back as base64 PNG payloads.
final class ImagePickerCoordinator: NSObject, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    enum Kind: String {
        case upload
        case batch
        case fillImage
        case heroAvatar
    }

    private weak var presenter: UIViewController?

    /// Files as `["name":…, "type":…, "base64":…]`, plus the originating request.
    var onFiles: (([[String: String]], Kind, Int?) -> Void)?
    var onAvatar: ((Data) -> Void)?
    var onFailure: ((String) -> Void)?

    private var kind: Kind = .upload
    private var index: Int?

    init(presenter: UIViewController) {
        self.presenter = presenter
        super.init()
    }

    /// Shows the 照片 / 文件 sheet. Batch import jumps straight to files.
    func chooseImage(kind: Kind, index: Int?) {
        self.kind = kind
        self.index = index
        guard let presenter else { return }
        if kind == .batch {
            presentFiles(allowMultiple: true)
            return
        }
        let photo = UIAlertAction(title: "照片", style: .default) { [weak self] _ in self?.presentPhotos() }
        let file = UIAlertAction(title: "文件", style: .default) { [weak self] _ in self?.presentFiles(allowMultiple: false) }
        AlertPresenter.actionSheet(title: "选择图片", message: nil, on: presenter, actions: [photo, file, UIAlertAction(title: "取消", style: .cancel)])
    }

    func presentPhotos() {
        guard let presenter else { return }
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    private func presentFiles(allowMultiple: Bool) {
        guard let presenter else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
        picker.allowsMultipleSelection = allowMultiple
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    // MARK: - UIDocumentPickerDelegate

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let requestedKind = kind
        let requestedIndex = index
        var files: [[String: String]] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let file = Self.pngFile(data: data, name: url.lastPathComponent) else { continue }
            files.append(file)
        }
        guard !files.isEmpty else {
            onFailure?("无法读取所选图片，请重新选择。")
            return
        }
        onFiles?(files, requestedKind, requestedIndex)
    }

    // MARK: - PHPickerViewControllerDelegate

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        let requestedKind = kind
        let requestedIndex = index
        let imageType = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true }
            ?? UTType.image.identifier
        provider.loadDataRepresentation(forTypeIdentifier: imageType) { [weak self] data, _ in
            guard let self else { return }
            let file = data.flatMap { Self.pngFile(data: $0, name: provider.suggestedName ?? "图片.png") }
            DispatchQueue.main.async {
                if requestedKind == .heroAvatar {
                    guard let data else {
                        self.onFailure?("无法读取头像，请换一张图片。")
                        return
                    }
                    self.onAvatar?(data)
                    return
                }
                guard let file else {
                    self.onFailure?("无法读取照片，请使用文件选择或换一张图片。")
                    return
                }
                self.onFiles?([file], requestedKind, requestedIndex)
            }
        }
    }

    /// Normalises any picked image to PNG so the web engine gets one format.
    static func pngFile(data: Data, name: String) -> [String: String]? {
        guard let image = UIImage(data: data), let png = image.pngData() else { return nil }
        return ["name": name, "type": "image/png", "base64": png.base64EncodedString()]
    }
}
