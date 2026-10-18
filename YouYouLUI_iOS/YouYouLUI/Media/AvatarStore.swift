import UIKit

/// Persists the avatar chosen on the settings hero card.
enum AvatarStore {
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SettingsAvatar.png")
    }

    enum Failure: Error {
        case unreadable
        case encoding
        case write(Error)
    }

    /// Downscales and writes the avatar as PNG. Returns nil on success.
    static func saveAvatar(data: Data) -> Failure? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return .unreadable }
        let scale = min(1, 512 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let png = normalized.pngData() else { return .encoding }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try png.write(to: fileURL, options: .atomic)
            return nil
        } catch {
            return .write(error)
        }
    }
}
