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
    var onCommand: ((String, [String: Any]) -> Void)?
    var savedColors: [String: Any] { UserDefaults.standard.dictionary(forKey: "luiyo.nativeIconColors") ?? [:] }
    func send(_ action: String, _ values: [String: Any]) { onCommand?(action, values) }
    func saveColors(_ values: [String: Any]) {
        UserDefaults.standard.set(values, forKey: "luiyo.nativeIconColors")
        send("colors", ["values": values])
    }
    func apply(_ payload: [String: Any]) {
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
                    Text("LUIYo").font(.largeTitle.bold())
                    Text("微信图标管理").font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Label(model.authorized ? "已授权" : "未授权", systemImage: model.authorized ? "checkmark.seal.fill" : "lock.fill")
                            .font(.caption.weight(.medium)).foregroundStyle(model.authorized ? Color.green : Color.secondary)
                        Text("已上传项目：\(model.uploadedCount) 项").accessibilityIdentifier("nativeUploadedCount").font(.caption).foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://qm.qq.com/q/th1QshgzHW")!) {
                            Label("反馈问题 · 联系客服", systemImage: "bubble.left.and.bubble.right")
                        }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                            .accessibilityLabel("反馈问题，联系客服")
                    }
                }
                tools
                if !model.status.isEmpty && !model.status.hasPrefix("已上传 ") {
                    Text(model.status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("nativeHomeStatus")
                }
                Picker("图标分类", selection: $category) {
                    Text("LiquidUI").tag(0)
                    Text("原版微信").tag(1)
                }
                .pickerStyle(.segmented)
                HStack {
                    Text(category == 0 ? "LiquidUI 图标" : "原版微信图标").font(.headline)
                    Spacer()
                    Text("\(categoryEntries.count) 项").font(.caption).foregroundStyle(.secondary)
                }
                NativeGlassGroup {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(visibleEntries) { item in
                            Button { model.send("upload", ["id": item.id]) } label: {
                                HStack(spacing: 8) {
                                    if let image = model.images[item.id] {
                                        Image(uiImage: image).resizable().scaledToFit().frame(width: 32, height: 32)
                                    } else {
                                        Image(systemName: "plus")
                                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                            .frame(width: 32, height: 32)
                                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                                            .lineLimit(2)
                                        Text(model.images[item.id] == nil ? "点击上传" : "已上传 · 点击替换").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(10).frame(maxWidth: .infinity, minHeight: 64)
                            }
                            .buttonStyle(.plain)
                            .modifier(NativeCardSurface())
                            .id(item.id)
                            .accessibilityLabel("上传" + item.title)
                            .contextMenu { if model.images[item.id] != nil { Button("移除图标", role: .destructive) { model.send("remove", ["id": item.id]) } } }
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }
        .background {
            // A wallpaper backdrop only. Glass, edges and highlights are system-rendered.
            if let image = model.backgroundImage {
                GeometryReader { frame in
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: frame.size.width, height: frame.size.height).clipped()
                }.ignoresSafeArea()
            } else {
                LinearGradient(colors: [Color(uiColor: .systemGroupedBackground), Color.blue.opacity(0.07), Color(uiColor: .systemGroupedBackground)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            }
        }

        }
    }

    private var tools: some View {
        NativeGlassGroup {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button { model.send("batch", [:]) } label: {
                        Label("关键词批量导入", systemImage: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity)
                    }.modifier(NativeActionStyle()).controlSize(.regular)
                    Button { model.send("fillImage", [:]) } label: {
                        Label("补全图片", systemImage: "photo")
                            .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity)
                    }.modifier(NativeActionStyle()).controlSize(.regular)
                }
                Button { model.send("fill", [:]) } label: {
                    Label("双分类补全", systemImage: "square.3.layers.3d")
                        .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity)
                }.modifier(NativeActionStyle()).controlSize(.regular)
                Button { if model.authorized { showColors = true } else { model.send("authorize", [:]) } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "paintpalette").font(.body).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自定义修改颜色").font(.system(size: 13, weight: .medium))
                            Text("浅色 / 深色 / 全部图标").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary).frame(maxWidth: .infinity).padding(.vertical, 1)
                }.modifier(NativeActionStyle()).controlSize(.regular).accessibilityIdentifier("nativeColorSettings")
                HStack(spacing: 8) {
                    Button { model.send("clear", [:]) } label: {
                        Label("清空", systemImage: "trash").frame(maxWidth: .infinity)
                    }.modifier(NativeActionStyle(prominent: true)).tint(.blue).controlSize(.regular)
                    Button { model.send("export", [:]) } label: {
                        Label("导出 ZIP", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }.modifier(NativeActionStyle(prominent: true)).tint(.green).controlSize(.regular)
                }.font(.system(size: 13, weight: .semibold))
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
        }.navigationViewStyle(.stack)
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

// Availability checks keep the iOS 15 deployment target. No simulated glass layers.
private struct NativeActionStyle: ViewModifier {
    @Environment(\.nativeUseBlur) private var useBlur
    var prominent = false
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !useBlur {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else {
            content.buttonStyle(.plain).padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
        }
    }
}

private struct NativeCardSurface: ViewModifier {
    @Environment(\.nativeUseBlur) private var useBlur
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !useBlur {
            content.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

private struct NativeGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var body: some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 6, content: content) }
        else { content() }
    }
}

private struct NativeUseBlurKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var nativeUseBlur: Bool { get { self[NativeUseBlurKey.self] } set { self[NativeUseBlurKey.self] = newValue } }
}
