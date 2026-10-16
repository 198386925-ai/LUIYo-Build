import UIKit
import SwiftUI
import CoreText

final class NativeHomeModel: ObservableObject {
    @Published var authorized = false
    @Published var uploadedCount = 0
    @Published var images: [Int: UIImage] = [:]
    @Published var status = ""
    @Published var query = ""
    @Published var useBlur = false
    @Published var backgroundImage: UIImage?
    @Published var theme = NativeHomeTheme()
    @Published var fontName: String?
    @Published var importedFont: UIFont?
    var onCommand: ((String, [String: Any]) -> Void)?
    var onScrollView: ((UIScrollView) -> Void)?
    var savedColors: [String: Any] { UserDefaults.standard.dictionary(forKey: "luiyo.nativeIconColors") ?? [:] }
    func send(_ action: String, _ values: [String: Any]) { onCommand?(action, values) }
    func saveColors(_ values: [String: Any]) {
        UserDefaults.standard.set(values, forKey: "luiyo.nativeIconColors")
        send("colors", ["values": values])
    }
    func apply(_ payload: [String: Any]) {
        if let values = payload["theme"] as? [String: Any] { theme = NativeHomeTheme(values) }
        uploadedCount = payload["uploadedCount"] as? Int ?? 0
        status = payload["status"] as? String ?? ""
        let sources = payload["images"] as? [String: String] ?? [:]
        var decoded: [String: UIImage] = [:]
        for (key, url) in sources {
            if let raw = url.split(separator: ",", maxSplits: 1).last,
               let data = Data(base64Encoded: String(raw)), let image = UIImage(data: data) { decoded[key] = image }
        }
        var result: [Int: UIImage] = [:]
        for (id, key) in payload["uploaded"] as? [String: String] ?? [:] {
            if let index = Int(id), let image = decoded[key] { result[index] = image }
        }
        images = result
    }
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let importedFont { return Font(importedFont.withSize(size) as CTFont).weight(weight) }
        return .system(size: size, weight: weight)
    }
}

struct NativeHomeTheme: Equatable {
    var background = "#F2F2F7", card = "#FFFFFF", button = "#FFFFFF", actionText = "#202832"
    var dark = false, customButton = false, bottomSearchEnabled = true
    var toolbarOpacity = 1.0
    init() {}
    init(_ values: [String: Any]) {
        background = values["background"] as? String ?? background
        card = values["card"] as? String ?? card
        button = "#FFFFFF"
        actionText = "#202832"
        dark = values["dark"] as? Bool ?? dark
        customButton = false
        bottomSearchEnabled = values["bottomSearchEnabled"] as? Bool ?? bottomSearchEnabled
        toolbarOpacity = 1
    }
}

extension UIColor {
    convenience init(nativeHex: String) {
        let value = Int(nativeHex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
        self.init(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    var nativeHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

struct LUIYoNativeHome: View {
    @ObservedObject var model: NativeHomeModel
    @State private var category = 0
    private var query: String { model.query }
    @State private var showColors = false
    @FocusState private var searchFocused: Bool
    @State private var selectedColor = Color.blue
    @State private var darkSelectedColor = Color.white
    @State private var allColor = Color(uiColor: .darkGray)
    @State private var selectedEnabled = false
    @State private var darkSelectedEnabled = false
    @State private var allEnabled = false
    private let catalog = NativeIconCatalog.load()
    private var activeCategory: String { category == 0 ? "wechat" : "liquidui" }
    private var categoryEntries: [NativeIconEntry] { catalog.entries.filter { $0.category == activeCategory } }
    private var visibleEntries: [NativeIconEntry] {
        let tokens = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return categoryEntries.filter { item in
            tokens.allSatisfy { item.searchText.localizedCaseInsensitiveContains($0) }
        }
    }

    var body: some View {
        home
            .tint(.blue)
            .environment(\.nativeUseBlur, model.useBlur)
            .environment(\.nativeHomeTheme, model.theme)
            .sheet(isPresented: $showColors) { colorSettings }
            .onChange(of: category) { value in model.send("category", ["category": value == 0 ? "wechat" : "liquidui"]) }
            .onChange(of: showColors) { value in
                if value {
                    let colors = model.savedColors
                    selectedEnabled = colors["selectedLightEnabled"] as? Bool ?? false
                    darkSelectedEnabled = colors["selectedDarkEnabled"] as? Bool ?? false
                    allEnabled = colors["allColorEnabled"] as? Bool ?? false
                    selectedColor = Color(UIColor(nativeHex: colors["selectedColor"] as? String ?? "#1677ff"))
                    darkSelectedColor = Color(UIColor(nativeHex: colors["selectedDarkColor"] as? String ?? "#ffffff"))
                    allColor = Color(UIColor(nativeHex: colors["allColor"] as? String ?? "#222222"))
                } else {
                    model.saveColors(["selectedLightEnabled": selectedEnabled, "selectedDarkEnabled": darkSelectedEnabled,
                        "allColorEnabled": allEnabled, "selectedColor": UIColor(selectedColor).nativeHex,
                        "selectedDarkColor": UIColor(darkSelectedColor).nativeHex, "allColor": UIColor(allColor).nativeHex])
                }
            }
    }

    private var home: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LUIYo").font(model.font(size: 28, weight: .bold))
                    Text("微信图标管理").font(model.font(size: 14)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Label(model.authorized ? "已授权" : "未授权", systemImage: model.authorized ? "checkmark.seal.fill" : "lock.fill")
                            .font(model.font(size: 12, weight: .medium)).foregroundStyle(model.authorized ? Color.green : Color.secondary)
                        Text("已上传项目：\(model.uploadedCount) 项").accessibilityIdentifier("nativeUploadedCount").font(model.font(size: 12)).foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://qm.qq.com/q/th1QshgzHW")!) {
                            HStack(spacing: 6) { ToolbarAssetIcon(name: "ToolbarSupport", size: 17); Text("反馈问题 · 联系客服") }
                        }
                            .font(model.font(size: 12, weight: .medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                            .accessibilityLabel("反馈问题，联系客服")
                    }
                }
                if !model.theme.bottomSearchEnabled {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索图标", text: Binding(get: { model.query }, set: { value in
                            model.query = value; model.send("search", ["query": value])
                        }))
                        .font(model.font(size: 15)).submitLabel(.search).focused($searchFocused)
                        .onSubmit { searchFocused = false }.accessibilityIdentifier("nativeHomeSearch")
                        if !model.query.isEmpty {
                            Button { model.query = ""; model.send("search", ["query": ""]) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain).accessibilityLabel("清除搜索")
                        }
                    }.padding(.horizontal, 14).frame(height: 48).modifier(NativeCardSurface())
                }
                tools
                NativeHomeCategoryPicker(selection: $category, theme: model.theme, font: model.importedFont, useBlur: model.useBlur).frame(height: 34)
                // Progress belongs after the picker, so loading cannot move the categories.
                if !model.status.isEmpty && !model.status.hasPrefix("已上传 ") {
                    Text(model.status).font(model.font(size: 12)).foregroundStyle(.secondary).accessibilityIdentifier("nativeHomeStatus")
                }
                HStack {
                    Text(category == 0 ? "原版微信图标" : "LiquidUI 图标").font(model.font(size: 17, weight: .semibold))
                    Spacer()
                    Text("\(categoryEntries.count) 项").font(model.font(size: 12)).foregroundStyle(.secondary)
                }
                if visibleEntries.isEmpty && !query.isEmpty {
                    Text("没有匹配的图标").font(model.font(size: 13)).foregroundStyle(.secondary)
                }
                NativeGlassGroup {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(visibleEntries) { item in
                            HStack(spacing: 0) {
                              Button { model.send("upload", ["id": item.id]) } label: {
                                HStack(spacing: 8) {
                                    if let image = model.images[item.id] {
                                        Image(uiImage: image).resizable().scaledToFit().frame(width: 32, height: 32)
                                    } else {
                                        Image(systemName: "plus")
                                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(model.theme.customButton ? Color(UIColor(nativeHex: model.theme.actionText)) : Color.white)
                                            .frame(width: 32, height: 32)
                                            .background(model.theme.customButton ? Color(UIColor(nativeHex: model.theme.button)) : Color.blue, in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title).font(model.font(size: 12, weight: .semibold)).foregroundStyle(.primary)
                                            .lineLimit(2)
                                        Text(model.images[item.id] == nil ? "点击上传" : "已上传 · 点击替换").font(model.font(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(10).frame(maxWidth: .infinity, minHeight: 64)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("上传" + item.title)
                              if model.images[item.id] != nil {
                                Button { model.send("remove", ["id": item.id]) } label: {
                                    Image(systemName: "trash").font(.system(size: 18)).foregroundStyle(.red)
                                        .frame(width: 44, height: 64).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("删除" + item.title)
                                    .accessibilityIdentifier("deleteIcon-\(item.id)")
                              }
                            }.modifier(NativeCardSurface()).id(item.id)
                            .contextMenu { if model.images[item.id] != nil { Button("移除图标", role: .destructive) { model.send("remove", ["id": item.id]) } } }
                        }
                    }
                }
            }
            .labelStyle(NativeAlignedLabelStyle())
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            .background(NativeHomeScrollLink(onAttach: { model.onScrollView?($0) }))
        }
        .background {
            if model.backgroundImage == nil {
                Color(UIColor(nativeHex: model.theme.background)).ignoresSafeArea()
            } else { Color.clear }
        }

        }
    }

    private var tools: some View {
        NativeGlassGroup {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button { model.send("batch", [:]) } label: {
                        HStack(spacing: 7) { ToolbarAssetIcon(name: "ToolbarImport", size: 18); Text("关键词批量导入") }
                            .font(model.font(size: 13, weight: .medium)).frame(maxWidth: .infinity)
                    }.modifier(NativeActionStyle()).controlSize(.large)
                    Button { model.send("fillImage", [:]) } label: {
                        HStack(spacing: 7) { ToolbarAssetIcon(name: "ToolbarFill", size: 18); Text("补全图片") }
                            .font(model.font(size: 13, weight: .medium)).frame(maxWidth: .infinity)
                    }.modifier(NativeActionStyle()).controlSize(.large)
                }
                Button { model.send("fill", [:]) } label: {
                    Label("双分类补全", systemImage: "square.3.layers.3d")
                        .font(model.font(size: 13, weight: .semibold)).frame(maxWidth: .infinity)
                }.modifier(NativeActionStyle()).controlSize(.large)
                Button { if model.authorized { showColors = true } else { model.send("authorize", [:]) } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "paintpalette").font(.system(size: 18)).frame(width: 20, height: 20).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自定义修改颜色").font(model.font(size: 13, weight: .medium))
                            Text("浅色 / 深色 / 全部图标").font(model.font(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Color.primary).frame(maxWidth: .infinity).padding(.vertical, 1)
                }.modifier(NativeActionStyle()).controlSize(.large).accessibilityIdentifier("nativeColorSettings")
                HStack(spacing: 8) {
                    NativeGlassActionButton(title: "清空", asset: "ToolbarClear", color: "#007AFE", font: model.importedFont,
                        useBlur: model.useBlur) { model.send("clear", [:]) }.frame(maxWidth: .infinity).frame(height: 44)
                    NativeGlassActionButton(title: "导出 ZIP", asset: "ToolbarExport", color: "#46D86A", font: model.importedFont,
                        useBlur: model.useBlur) { model.send("export", [:]) }.frame(maxWidth: .infinity).frame(height: 44)
                }.font(model.font(size: 13, weight: .semibold))
            }
        }
    }

    private var colorSettings: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("启用自定义颜色", isOn: $selectedEnabled).toggleStyle(BrandSwitchStyle())
                    ColorPicker("选中颜色", selection: $selectedColor, supportsOpacity: false)
                        .disabled(!selectedEnabled)
                } header: { Text("选中 · 浅色模式") }
                  footer: { Text("关闭时自动加深上传图片的颜色。") }
                Section {
                    Toggle("启用自定义颜色", isOn: $darkSelectedEnabled).toggleStyle(BrandSwitchStyle())
                    ColorPicker("选中颜色", selection: $darkSelectedColor, supportsOpacity: false)
                        .disabled(!darkSelectedEnabled)
                } header: { Text("选中 · 深色模式") }
                  footer: { Text("关闭时自动反转上传图片的颜色。") }
                Section {
                    Toggle("启用统一颜色", isOn: $allEnabled).toggleStyle(BrandSwitchStyle())
                    ColorPicker("图标颜色", selection: $allColor, supportsOpacity: false)
                        .disabled(!allEnabled)
                } header: { Text("全部图标") }
                  footer: { Text("关闭时保留上传图片的原本颜色。") }
            }
            .navigationTitle("自定义颜色").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showColors = false }
                }
            }
        }.navigationViewStyle(.stack).font(model.font(size: 17))
    }

}

private struct NativeIconEntry: Decodable, Identifiable {
    let id: Int
    let title: String
    let category: String
    let searchText: String
    let files: [String]
}

private struct NativeIconCatalog: Decodable {
    let totalSourceItems: Int
    let entries: [NativeIconEntry]
    static func load() -> NativeIconCatalog {
        guard let url = Bundle.main.url(forResource: "native-preview-catalog", withExtension: "json", subdirectory: "Web"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(NativeIconCatalog.self, from: data) else {
            fatalError("Complete homepage catalog is missing")
        }
        return catalog
    }
}

// UIKit renders the material; only its native tint and background opacity change.
private struct NativeActionStyle: ViewModifier {
    @Environment(\.nativeUseBlur) private var useBlur
    @Environment(\.nativeHomeTheme) private var theme
    func body(content: Content) -> some View {
        let color = UIColor(nativeHex: theme.button)
        let text = theme.customButton ? Color.primary : Color.blue
        return content.buttonStyle(NativeHomeActionButtonStyle(useBlur: useBlur, tint: color, text: text, opacity: theme.toolbarOpacity))
    }
}

private struct NativeHomeActionButtonStyle: ButtonStyle {
    var useBlur: Bool
    var tint: UIColor
    var text: Color
    var opacity: Double
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(text)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(NativeMaterialSurface(useBlur: useBlur, tint: tint, opacity: opacity, radius: -1))
            .contentShape(Capsule())
    }
}

// UIKit owns the tinted glass, hit target and pressed state. Semantic colors are fixed.
// Uploaded glyphs include white cutouts. Derive the silhouette from luminance
// before tinting, so template rendering preserves those internal details.
private enum ToolbarAssetImages {
    private static var cache: [String: UIImage] = [:]
    static func template(named name: String) -> UIImage? {
        if let cached = cache[name] { return cached }
        guard let original = UIImage(named: name), let source = original.cgImage else { return nil }
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let mask: CGImage? = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(source, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            let data = bytes.bindMemory(to: UInt8.self)
            for index in stride(from: 0, to: data.count, by: 4) {
                let alpha = Double(data[index + 3])
                let luminance = 0.2126 * Double(data[index]) + 0.7152 * Double(data[index + 1]) + 0.0722 * Double(data[index + 2])
                let opacity = max(0, min(alpha, (alpha - luminance) / 0.8))
                data[index] = 0; data[index + 1] = 0; data[index + 2] = 0
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

private struct ToolbarAssetIcon: View {
    var name: String
    var size: CGFloat
    var body: some View {
        Image(uiImage: ToolbarAssetImages.template(named: name) ?? UIImage()).resizable().renderingMode(.template).scaledToFit()
            .foregroundStyle(.blue)
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct NativeGlassActionButton: UIViewRepresentable {
    var title: String
    var asset: String
    var color: String
    var font: UIFont?
    var useBlur: Bool
    var action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        let tint = UIColor(nativeHex: color)
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *), !useBlur {
            configuration = .prominentGlass()
        } else {
            configuration = .plain()
            configuration.background.visualEffect = UIBlurEffect(style: .systemMaterial)
            configuration.background.backgroundColor = tint.withAlphaComponent(0.72)
        }
        configuration.title = title
        if let image = ToolbarAssetImages.template(named: asset) {
            configuration.image = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18)).image { _ in
                image.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: CGRect(x: 0, y: 0, width: 18, height: 18))
            }.withRenderingMode(.alwaysOriginal)
        }
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = tint
        configuration.baseForegroundColor = .white
        let titleFont = font?.withSize(13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = titleFont
            result.foregroundColor = .white
            return result
        }
        button.tintColor = tint
        button.configuration = configuration
        button.accessibilityLabel = title
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}

private struct NativeCardSurface: ViewModifier {
    @Environment(\.nativeUseBlur) private var useBlur
    @Environment(\.nativeHomeTheme) private var theme
    func body(content: Content) -> some View {
        content.background(NativeMaterialSurface(useBlur: useBlur, tint: UIColor(nativeHex: theme.card), opacity: 1, radius: 20))
    }
}

private struct NativeMaterialSurface: UIViewRepresentable {
    var useBlur: Bool
    var tint: UIColor
    var opacity: Double
    var radius: CGFloat
    func makeUIView(context: Context) -> NativeMaterialView {
        let view = NativeMaterialView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }
    func updateUIView(_ view: NativeMaterialView, context: Context) {
        view.shapeRadius = radius
        var blur = useBlur
        if #available(iOS 26.0, *) {} else { blur = true }
        let signature = "\(blur)|\(tint.nativeHex)"
        if signature != view.materialSignature {
            view.materialSignature = signature
            if #available(iOS 26.0, *), !blur {
                let glass = UIGlassEffect(style: .regular)
                if tint.nativeHex.uppercased() != "#FFFFFF" { glass.tintColor = tint.withAlphaComponent(0.12) }
                glass.isInteractive = true
                view.effect = glass
            } else { view.effect = UIBlurEffect(style: .systemMaterial) }
            view.contentView.backgroundColor = blur ? tint.withAlphaComponent(0.24) : .clear
        }
        view.alpha = CGFloat(opacity)
        view.setNeedsLayout()
    }
}

private final class NativeMaterialView: UIVisualEffectView {
    var materialSignature = ""
    var shapeRadius: CGFloat = 20
    private var appliedRadius: CGFloat = -1
    private var appliedGlassMode = false
    override func layoutSubviews() {
        super.layoutSubviews()
        removeExtraLayerShadows(layer)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let radius = shapeRadius < 0 ? bounds.height / 2 : min(shapeRadius, bounds.height / 2)
        if #available(iOS 26.0, *), effect is UIGlassEffect {
            // Let UIKit generate the optical rounded edge; never crop its layers.
            clipsToBounds = false
            if abs(appliedRadius - radius) > 0.1 || !appliedGlassMode {
                cornerConfiguration = .uniformCorners(radius: .fixed(Double(radius)))
            }
            appliedGlassMode = true
        } else {
            clipsToBounds = true
            layer.cornerCurve = .continuous
            layer.cornerRadius = radius
            appliedGlassMode = false
        }
        appliedRadius = radius
    }
}

private struct NativeHomeCategoryPicker: UIViewRepresentable {
    @Binding var selection: Int
    var theme: NativeHomeTheme
    var font: UIFont?
    var useBlur: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> NativeCategoryGlassView {
        let view = NativeCategoryGlassView()
        view.control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return view
    }
    func updateUIView(_ view: NativeCategoryGlassView, context: Context) {
        context.coordinator.parent = self
        view.update(theme: theme, font: font, useBlur: useBlur)
        view.setSelection(selection)
    }
    final class Coordinator: NSObject {
        var parent: NativeHomeCategoryPicker
        init(_ parent: NativeHomeCategoryPicker) { self.parent = parent }
        @objc func changed(_ control: UISegmentedControl) { parent.selection = control.selectedSegmentIndex }
    }
}

// A solid selected pill sits above native glass; the control remains independently tappable.
private final class NativeCategoryGlassView: UIView {
    let material = NativeMaterialView()
    let control = UISegmentedControl(items: ["原版微信", "LiquidUI"])
    private let selectedPill = UIView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        material.shapeRadius = -1
        material.isUserInteractionEnabled = false
        material.accessibilityElementsHidden = true
        addSubview(material)
        selectedPill.isUserInteractionEnabled = false
        selectedPill.accessibilityElementsHidden = true
        addSubview(selectedPill)
        // Never put an interactive control inside a noninteractive material view.
        addSubview(control)
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(selectionChanged), for: .valueChanged)
        let transparent = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        control.backgroundColor = .clear
        control.setBackgroundImage(transparent, for: .normal, barMetrics: .default)
        control.setBackgroundImage(transparent, for: .selected, barMetrics: .default)
        control.setBackgroundImage(transparent, for: [.selected, .highlighted], barMetrics: .default)
        control.setDividerImage(transparent, forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(theme: NativeHomeTheme, font: UIFont?, useBlur: Bool) {
        let signature = "\(useBlur)|\(theme.card)|\(theme.dark)"
        if material.materialSignature != signature {
            material.materialSignature = signature
            let tint = UIColor(nativeHex: theme.card)
            if #available(iOS 26.0, *), !useBlur {
                let effect = UIGlassEffect(style: .regular)
                if !["#FFFFFF", "#1C1C1E"].contains(theme.card.uppercased()) { effect.tintColor = tint.withAlphaComponent(0.12) }
                material.effect = effect
                material.contentView.backgroundColor = .clear
            } else {
                material.effect = UIBlurEffect(style: .systemMaterial)
                material.contentView.backgroundColor = tint.withAlphaComponent(0.24)
            }
        }
        control.selectedSegmentTintColor = .clear
        selectedPill.backgroundColor = .white
        selectedPill.layer.borderWidth = 0
        selectedPill.layer.shadowColor = UIColor.black.cgColor
        selectedPill.layer.shadowOpacity = 0.065
        selectedPill.layer.shadowRadius = 1
        selectedPill.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        let textFont = font?.withSize(13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
        control.setTitleTextAttributes([.font: textFont, .foregroundColor: UIColor.label], for: .normal)
        control.setTitleTextAttributes([.font: textFont, .foregroundColor: UIColor(nativeHex: "#202832")], for: .selected)
        material.setNeedsLayout()
        setNeedsLayout()
    }
    func setSelection(_ index: Int) {
        if control.selectedSegmentIndex != index { control.selectedSegmentIndex = index }
        layoutSelectedPill()
    }
    @objc private func selectionChanged() { layoutSelectedPill() }
    private func layoutSelectedPill() {
        guard bounds.width > 4, bounds.height > 4 else { return }
        let track = bounds.insetBy(dx: 2, dy: 2)
        let width = track.width / CGFloat(control.numberOfSegments)
        let index = max(0, control.selectedSegmentIndex)
        UIView.performWithoutAnimation {
            selectedPill.frame = CGRect(x: track.minX + CGFloat(index) * width, y: track.minY, width: width, height: track.height)
            selectedPill.layer.cornerRadius = track.height / 2
            selectedPill.layer.cornerCurve = .continuous
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        control.frame = bounds.insetBy(dx: 2, dy: 2)
        layoutSelectedPill()
    }
}

// Register the actual SwiftUI UIScrollView with the native tab controller.
private struct NativeHomeScrollLink: UIViewRepresentable {
    var onAttach: (UIScrollView) -> Void
    func makeUIView(context: Context) -> NativeScrollProbe {
        let view = NativeScrollProbe()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.onAttach = onAttach
        return view
    }
    func updateUIView(_ view: NativeScrollProbe, context: Context) {
        view.onAttach = onAttach
        view.setNeedsLayout()
    }
}

private final class NativeScrollProbe: UIView {
    var onAttach: ((UIScrollView) -> Void)?
    private weak var reported: UIScrollView?
    override func didMoveToWindow() { super.didMoveToWindow(); discover() }
    override func layoutSubviews() { super.layoutSubviews(); discover() }
    private func discover() {
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView {
                if reported !== scroll {
                    reported = scroll
                    DispatchQueue.main.async { [weak self, weak scroll] in
                        if let scroll { self?.onAttach?(scroll) }
                    }
                }
                return
            }
            ancestor = view.superview
        }
    }
}

private struct NativeGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { content() }
}

private struct NativeUseBlurKey: EnvironmentKey { static let defaultValue = false }
private struct NativeHomeThemeKey: EnvironmentKey { static let defaultValue = NativeHomeTheme() }
extension EnvironmentValues {
    var nativeUseBlur: Bool { get { self[NativeUseBlurKey.self] } set { self[NativeUseBlurKey.self] = newValue } }
    var nativeHomeTheme: NativeHomeTheme { get { self[NativeHomeThemeKey.self] } set { self[NativeHomeThemeKey.self] = newValue } }
}

// Keep SF Symbols at a stable size when a decorative text font is imported.
private struct NativeAlignedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 8) {
            configuration.icon.font(.system(size: 18)).frame(width: 20, height: 20)
            configuration.title
        }
    }
}

// Public CALayer properties only. Native glass/blur continues to draw the material.
func removeExtraLayerShadows(_ layer: CALayer) {
    if layer.shadowOpacity != 0 { layer.shadowOpacity = 0 }
    if layer.shadowRadius != 0 { layer.shadowRadius = 0 }
    if layer.shadowPath != nil { layer.shadowPath = nil }
    // UIKit owns its effect sublayers. Preserve their optical rendering.
}

private struct BrandSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack { configuration.label; Spacer(); BrandSwitch(isOn: configuration.$isOn).frame(width:44,height:26) }
    }
}
private struct BrandSwitch: UIViewRepresentable {
    @Binding var isOn: Bool
    func makeUIView(context: Context) -> UIControl {
        LUIYoCreateThemeSwitch(isOn) { value in isOn = value }
    }
    func updateUIView(_ view: UIControl, context: Context) { LUIYoSetThemeSwitch(view, isOn) }
}
