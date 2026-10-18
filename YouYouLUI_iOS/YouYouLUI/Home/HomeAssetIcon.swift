import SwiftUI
import UIKit

/// Uploaded toolbar glyphs contain white cutouts. Derive the silhouette from
/// luminance before tinting, so template rendering preserves those details.
enum ToolbarAssetImages {
    private static var cache: [String: UIImage] = [:]

    static func template(named name: String) -> UIImage? {
        if let cached = cache[name] { return cached }
        guard let original = UIImage(named: name), let source = original.cgImage else { return nil }
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let mask: CGImage? = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                                            | CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(source, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            let data = bytes.bindMemory(to: UInt8.self)
            for index in stride(from: 0, to: data.count, by: 4) {
                let alpha = Double(data[index + 3])
                let luminance = 0.2126 * Double(data[index]) + 0.7152 * Double(data[index + 1]) + 0.0722 * Double(data[index + 2])
                let opacity = max(0, min(alpha, (alpha - luminance) / 0.8))
                data[index] = 0
                data[index + 1] = 0
                data[index + 2] = 0
                data[index + 3] = UInt8(opacity.rounded())
            }
            return context.makeImage()
        }
        guard let mask else { return nil }
        let image = UIImage(cgImage: mask, scale: original.scale, orientation: .up).withRenderingMode(.alwaysTemplate)
        cache[name] = image
        return image
    }
}

struct ToolbarAssetIcon: View {
    var name: String
    var size: CGFloat

    var body: some View {
        Image(uiImage: ToolbarAssetImages.template(named: name) ?? UIImage())
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(.blue)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
