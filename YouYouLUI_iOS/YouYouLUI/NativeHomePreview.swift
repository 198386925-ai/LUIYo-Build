import UIKit
import SwiftUI

@main
final class NativeHomePreviewAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let scenario = ProcessInfo.processInfo.environment["LUI_SNAPSHOT"] ?? "preview-native-glass-home-light"
        window.overrideUserInterfaceStyle = scenario.hasSuffix("dark") ? .dark : .light
        window.rootViewController = UIHostingController(rootView: LUIYoNativeGlassHomePreview())
        self.window = window
        window.makeKeyAndVisible()
        return true
    }
}

// Preview-only: all glass is rendered by iOS 26 SwiftUI system APIs.
// This view is compiled only for Debug simulator builds.
#if DEBUG && targetEnvironment(simulator)
private struct LUIYoNativeGlassHomePreview: View {
    @State private var category = 0
    @State private var query = ""
    @State private var showColors = false
    @State private var selectedColor = Color.blue
    @State private var darkSelectedColor = Color.white
    @State private var allColor = Color(uiColor: .darkGray)
    @State private var selectedEnabled = false
    @State private var darkSelectedEnabled = false
    @State private var allEnabled = false
    private let titles = ["插件入口", "顶栏美化设置", "改金额", "改文字", "头像遮罩", "背景 Diy"]

    var body: some View {
        tabs
        .searchable(text: $query, prompt: "搜索图标")
        .tint(.blue)
        .sheet(isPresented: $showColors) { colorSettings }
        .onAppear {
            if ProcessInfo.processInfo.environment["LUI_SNAPSHOT"]?.contains("colors") == true {
                showColors = true
            }
            saveRuntimeEvidence()
        }
    }

    @ViewBuilder private var tabs: some View {
        if #available(iOS 26.0, *) {
        TabView {
            Tab("首页", systemImage: "house.fill") { home }
            Tab("规则", systemImage: "list.bullet.rectangle") {
                NavigationStack { Text("图标命名规则").navigationTitle("规则") }
            }
            Tab("设置", systemImage: "gearshape.fill") {
                NavigationStack { Text("主题与偏好设置").navigationTitle("设置") }
            }
            Tab(role: .search) {
                NavigationStack { Text("搜索图标").navigationTitle("搜索") }
            }
        }
        } else {
            // The system tab bar supplies its native blur on older iOS versions.
            TabView {
                home.tabItem { Label("首页", systemImage: "house.fill") }
                NavigationView { Text("图标命名规则").navigationTitle("规则") }
                    .tabItem { Label("规则", systemImage: "list.bullet.rectangle") }
                NavigationView { Text("主题与偏好设置").navigationTitle("设置") }
                    .tabItem { Label("设置", systemImage: "gearshape.fill") }
            }
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LUIYo").font(.largeTitle.bold())
                    Text("LiquidUI / 微信图标管理").font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Label("已授权", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.medium)).foregroundStyle(.green)
                        Text("已上传项目：0 项").font(.caption).foregroundStyle(.secondary)
                        Link("联系客服", destination: URL(string: "https://qm.qq.com/q/th1QshgzHW")!)
                            .font(.caption.weight(.medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                            .accessibilityLabel("反馈问题，联系客服")
                    }
                }
                tools
                Picker("图标分类", selection: $category) {
                    Text("LiquidUI").tag(0)
                    Text("原版微信").tag(1)
                }
                .pickerStyle(.segmented)
                Text(category == 0 ? "LiquidUI 图标" : "原版微信图标").font(.headline)
                NativeGlassGroup {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(titles, id: \.self) { title in
                            Button {} label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                                        Text("点击上传").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(10).frame(maxWidth: .infinity, minHeight: 64)
                            }
                            .buttonStyle(.plain)
                            .modifier(NativeCardSurface())
                            .accessibilityLabel("上传" + title)
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }
        .background {
            // A wallpaper backdrop only. Glass, edges and highlights are system-rendered.
            LinearGradient(colors: [Color(uiColor: .systemGroupedBackground), Color.blue.opacity(0.07), Color(uiColor: .systemGroupedBackground)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
    }

    private var tools: some View {
        NativeGlassGroup {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button {} label: {
                        Label("关键词批量导入", systemImage: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity)
                    }.modifier(NativeActionStyle()).controlSize(.regular)
                    Button {} label: {
                        Label("补全图片", systemImage: "photo")
                            .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity)
                    }.modifier(NativeActionStyle()).controlSize(.regular)
                }
                Button {} label: {
                    Label("双分类补全", systemImage: "square.3.layers.3d")
                        .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity)
                }.modifier(NativeActionStyle()).controlSize(.regular)
                Button { showColors = true } label: {
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
                }.modifier(NativeActionStyle()).controlSize(.regular)
                HStack(spacing: 8) {
                    Button {} label: {
                        Label("清空", systemImage: "trash").frame(maxWidth: .infinity)
                    }.modifier(NativeActionStyle(prominent: true)).tint(.blue).controlSize(.regular)
                    Button {} label: {
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

    private func saveRuntimeEvidence() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            var glassClasses: [String] = []
            func visit(_ view: UIView) {
                let name = String(describing: type(of: view))
                if name.localizedCaseInsensitiveContains("glass") { glassClasses.append(name) }
                if let surface = view as? UIVisualEffectView, let effect = surface.effect {
                    glassClasses.append(String(describing: type(of: effect)))
                }
                view.subviews.forEach(visit)
            }
            if let delegate = UIApplication.shared.delegate as? NativeHomePreviewAppDelegate,
               let window = delegate.window { visit(window) }
            let evidence: [String: Any] = [
                "osVersion": UIDevice.current.systemVersion,
                "rendering": "native SwiftUI on iOS simulator",
                "materialPolicy": "iOS 26+: system Liquid Glass; earlier iOS: system regularMaterial and native tab bar",
                "runtimeGlassClasses": Array(Set(glassClasses)).sorted(),
                "previewOnly": true
            ]
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: dir.appendingPathComponent("native-glass-evidence.json"))
            }
            try? Data("ready".utf8).write(to: dir.appendingPathComponent("native-glass-ready.txt"))
        }
    }
}

// Availability checks keep the iOS 15 deployment target. No simulated glass layers.
private struct NativeActionStyle: ViewModifier {
    var prominent = false
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else {
            content.buttonStyle(.plain).padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
        }
    }
}

private struct NativeCardSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
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
#endif
