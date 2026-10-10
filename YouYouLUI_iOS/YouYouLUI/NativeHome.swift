import UIKit
import SwiftUI

final class NativeHomeModel: ObservableObject {
    @Published var authorized = false
    @Published var uploadedCount = 0
    @Published var images: [Int: UIImage] = [:]
    @Published var status = "正在加载图标…"
    @Published var query = ""
    @Published var useBlur = false
    @Published var backgroundImage: UIImage?
    @Published var theme = NativeHomeTheme()
    @Published var fontName: String?
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
        if let fontName { return .custom(fontName, fixedSize: size).weight(weight) }
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
        button = values["button"] as? String ?? button
        actionText = values["actionText"] as? String ?? actionText
        dark = values["dark"] as? Bool ?? dark
        customButton = values["customButton"] as? Bool ?? customButton
        bottomSearchEnabled = values["bottomSearchEnabled"] as? Bool ?? bottomSearchEnabled
        toolbarOpacity = min(1, max(0, values["toolbarOpacity"] as? Double ?? toolbarOpacity))
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
    private var activeCategory: String { category == 0 ? "liquidui" : "wechat" }
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
            .onChange(of: category) { value in model.send("category", ["category": value == 0 ? "liquidui" : "wechat"]) }
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
                    Text("LUIYo").font(model.font(size: 34, weight: .bold))
                    Text("微信图标管理").font(model.font(size: 15)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Label(model.authorized ? "已授权" : "未授权", systemImage: model.authorized ? "checkmark.seal.fill" : "lock.fill")
                            .font(model.font(size: 12, weight: .medium)).foregroundStyle(model.authorized ? Color.green : Color.secondary)
                        Text("已上传项目：\(model.uploadedCount) 项").accessibilityIdentifier("nativeUploadedCount").font(model.font(size: 12)).foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://qm.qq.com/q/th1QshgzHW")!) {
                            Label("反馈问题 · 联系客服", systemImage: "bubble.left.and.bubble.right")
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
                if !model.status.isEmpty && !model.status.hasPrefix("已上传 ") {
                    Text(model.status).font(model.font(size: 12)).foregroundStyle(.secondary).accessibilityIdentifier("nativeHomeStatus")
                }
                NativeHomeCategoryPicker(selection: $category, theme: model.theme, fontName: model.fontName).frame(height: 34)
                HStack {
                    Text(category == 0 ? "LiquidUI 图标" : "原版微信图标").font(model.font(size: 17, weight: .semibold))
                    Spacer()
                    Text("\(categoryEntries.count) 项").font(model.font(size: 12)).foregroundStyle(.secondary)
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
                                            .font(model.font(size: 16, weight: .semibold)).foregroundStyle(model.theme.customButton ? Color(UIColor(nativeHex: model.theme.actionText)) : Color.white)
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
                                    Image(systemName: "trash").font(model.font(size: 16)).foregroundStyle(.red)
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
                        Label("关键词批量导入", systemImage: "square.and.arrow.down")
                            .font(model.font(size: 15, weight: .medium)).frame(maxWidth: .infinity)
                    }.modifier(NativeActionStyle()).controlSize(.large)
                    Button { model.send("fillImage", [:]) } label: {
                        Label("补全图片", systemImage: "photo")
                            .font(model.font(size: 15, weight: .medium)).frame(maxWidth: .infinity)
                    }.modifier(NativeActionStyle()).controlSize(.large)
                }
                Button { model.send("fill", [:]) } label: {
                    Label("双分类补全", systemImage: "square.3.layers.3d")
                        .font(model.font(size: 16, weight: .semibold)).frame(maxWidth: .infinity)
                }.modifier(NativeActionStyle()).controlSize(.large)
                Button { if model.authorized { showColors = true } else { model.send("authorize", [:]) } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "paintpalette").font(model.font(size: 17)).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自定义修改颜色").font(model.font(size: 16, weight: .medium))
                            Text("浅色 / 深色 / 全部图标").font(model.font(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(model.font(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(model.theme.customButton ? Color(UIColor(nativeHex: model.theme.actionText)) : Color.primary).frame(maxWidth: .infinity).padding(.vertical, 1)
                }.modifier(NativeActionStyle()).controlSize(.large).accessibilityIdentifier("nativeColorSettings")
                HStack(spacing: 8) {
                    Button { model.send("clear", [:]) } label: {
                        Label("清空", systemImage: "trash").frame(maxWidth: .infinity)
                    }.modifier(NativeActionStyle(prominent: true, fill: "#007AFE")).controlSize(.large)
                    Button { model.send("export", [:]) } label: {
                        Label("导出 ZIP", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }.modifier(NativeActionStyle(prominent: true, fill: "#46D86A")).controlSize(.large)
                }.font(model.font(size: 16, weight: .semibold))
            }
        }
    }

    private var colorSettings: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("启用自定义颜色", isOn: $selectedEnabled)
                    ColorPicker("选中颜色", selection: $selectedColor, supportsOpacity: false)
                        .disabled(!selectedEnabled)
                } header: { Text("选中 · 浅色模式") }
                  footer: { Text("关闭时自动加深上传图片的颜色。") }
                Section {
                    Toggle("启用自定义颜色", isOn: $darkSelectedEnabled)
                    ColorPicker("选中颜色", selection: $darkSelectedColor, supportsOpacity: false)
                        .disabled(!darkSelectedEnabled)
                } header: { Text("选中 · 深色模式") }
                  footer: { Text("关闭时自动反转上传图片的颜色。") }
                Section {
                    Toggle("启用统一颜色", isOn: $allEnabled)
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
    var prominent = false
    var fill: String?
    func body(content: Content) -> some View {
        let color = UIColor(nativeHex: fill ?? theme.button)
        let text = prominent ? Color.white : (theme.customButton ? Color(UIColor(nativeHex: theme.actionText)) : Color.blue)
        return content.buttonStyle(NativeHomeActionButtonStyle(useBlur: useBlur, tint: color, text: text, opacity: theme.toolbarOpacity, solid: prominent))
    }
}

private struct NativeHomeActionButtonStyle: ButtonStyle {
    var useBlur: Bool
    var tint: UIColor
    var text: Color
    var opacity: Double
    var solid: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(text)
            .padding(.horizontal, 14).frame(minHeight: 48)
            .background(NativeMaterialSurface(useBlur: useBlur, tint: tint, opacity: opacity, radius: -1, solid: solid))
            .contentShape(Capsule())
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
    var solid = false
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
        let signature = "\(blur)|\(tint.nativeHex)|\(solid)"
        if signature != view.materialSignature {
            view.materialSignature = signature
            if #available(iOS 26.0, *), !blur {
                let glass = UIGlassEffect(style: .regular)
                glass.tintColor = tint.withAlphaComponent(solid ? 0.85 : 0.12)
                glass.isInteractive = true
                view.effect = glass
            } else { view.effect = UIBlurEffect(style: .systemMaterial) }
            view.contentView.backgroundColor = tint.withAlphaComponent(solid ? 0.90 : (blur ? 0.24 : 0.10))
        }
        view.alpha = CGFloat(opacity)
        view.setNeedsLayout()
    }
}

private final class NativeMaterialView: UIVisualEffectView {
    var materialSignature = ""
    var shapeRadius: CGFloat = 20
    override func layoutSubviews() {
        super.layoutSubviews()
        clipsToBounds = true
        layer.cornerCurve = .continuous
        layer.cornerRadius = shapeRadius < 0 ? bounds.height / 2 : min(shapeRadius, bounds.height / 2)
    }
}

private struct NativeHomeCategoryPicker: UIViewRepresentable {
    @Binding var selection: Int
    var theme: NativeHomeTheme
    var fontName: String?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: ["LiquidUI", "原版微信"])
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }
    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegmentIndex = selection
        control.backgroundColor = UIColor(nativeHex: theme.card)
        control.selectedSegmentTintColor = UIColor(nativeHex: theme.button)
        let font = fontName.flatMap { UIFont(name: $0, size: 13) } ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
        control.setTitleTextAttributes([.font: font, .foregroundColor: UIColor.label], for: .normal)
        control.setTitleTextAttributes([.font: font, .foregroundColor: UIColor(nativeHex: theme.actionText)], for: .selected)
    }
    final class Coordinator: NSObject {
        var parent: NativeHomeCategoryPicker
        init(_ parent: NativeHomeCategoryPicker) { self.parent = parent }
        @objc func changed(_ control: UISegmentedControl) { parent.selection = control.selectedSegmentIndex }
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
