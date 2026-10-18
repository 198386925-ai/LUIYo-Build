import CoreText
import UIKit

/// Owns the custom theme font: registration, persistence and notification.
/// Applying it to specific views stays the shell's job.
final class ThemeFontController {
    /// The app's imported font, if any.
    private(set) var font: UIFont?
    /// Persisted font bytes, used to skip redundant CoreText work.
    private var fontData: Data?
    private var registeredGraphicsFont: CGFont?

    /// Called on the main queue whenever the font changes (nil = system font).
    var onFontChanged: ((UIFont?) -> Void)?

    private var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ThemeFont.data")
    }

    /// Restores the font saved by a previous launch.
    @discardableResult
    func restore() -> Bool {
        guard let data = try? Data(contentsOf: storageURL) else { return false }
        return apply(data)
    }

    /// Registers and persists a font payload coming from the page.
    @discardableResult
    func apply(_ data: Data) -> Bool {
        if fontData == data {
            onFontChanged?(font)
            return true
        }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return false }
        if let previous = registeredGraphicsFont { CTFontManagerUnregisterGraphicsFont(previous, nil) }
        let createdFont = CTFontCreateWithFontDescriptor(descriptor, 10, nil)
        let graphicsFont = CTFontCopyGraphicsFont(createdFont, nil)
        registeredGraphicsFont = CTFontManagerRegisterGraphicsFont(graphicsFont, nil) ? graphicsFont : nil
        font = createdFont as UIFont
        fontData = data
        persist(data)
        onFontChanged?(font)
        return true
    }

    /// Drops the custom font and reverts every view to the system font.
    func reset() {
        font = nil
        fontData = nil
        if let previous = registeredGraphicsFont { CTFontManagerUnregisterGraphicsFont(previous, nil) }
        registeredGraphicsFont = nil
        try? FileManager.default.removeItem(at: storageURL)
        onFontChanged?(nil)
    }

    private func persist(_ data: Data) {
        try? FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: storageURL, options: .atomic)
    }
}
