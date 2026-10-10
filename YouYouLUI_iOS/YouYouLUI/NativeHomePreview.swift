import UIKit
import SwiftUI

@main
final class NativeHomePreviewAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let scenario = ProcessInfo.processInfo.environment["LUI_SNAPSHOT"] ?? "preview-native-glass-home-light"
        window.overrideUserInterfaceStyle = scenario.hasSuffix("dark") ? .dark : .light
        if #available(iOS 26.0, *) {
            window.rootViewController = UIHostingController(rootView: LUIYoNativeGlassHomePreview())
        }
        self.window = window
        window.makeKeyAndVisible()
        return true
    }
}

// Preview-only: all glass is rendered by iOS 26 SwiftUI system APIs.
// This view is compiled only for Debug simulator builds.
#if DEBUG && targetEnvironment(simulator)
@available(iOS 26.0, *)
private struct LUIYoNativeGlassHomePreview: View {
    @State private var category = 0
    @State private var query = ""
    @State private var showColors = false
    @State private var selectedColor = Color.blue
    private let titles = ["插件入口", "顶栏美化设置", "改金额", "改文字", "头像遮罩", "背景 Diy"]

    var body: some View {
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
        .searchable(text: $query, prompt: "搜索图标")
        .tint(.blue)
        .onAppear(perform: saveRuntimeEvidence)
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LUIYo").font(.largeTitle.bold())
                    Text("LiquidUI / 微信图标管理").font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Label("已授权", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.medium)).foregroundStyle(.green)
                        Text("已上传 0 项").font(.caption).foregroundStyle(.secondary)
                    }
                }
                tools
                Picker("图标分类", selection: $category) {
                    Text("LiquidUI").tag(0)
                    Text("原版微信").tag(1)
                }
                .pickerStyle(.segmented)
                Text(category == 0 ? "LiquidUI 图标" : "原版微信图标").font(.headline)
                GlassEffectContainer(spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(titles, id: \.self) { title in
                            Button {} label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus").font(.title3).foregroundStyle(.secondary)
                                        .frame(width: 30, height: 42)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                                        Text("点击上传").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(14).frame(maxWidth: .infinity, minHeight: 78)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24))
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
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Button {} label: {
                        Label("关键词批量导入", systemImage: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity)
                    }.buttonStyle(.glass).controlSize(.large)
                    Button {} label: {
                        Label("补全图片", systemImage: "photo")
                            .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity)
                    }.buttonStyle(.glass).controlSize(.large)
                }
                Button {} label: {
                    Label("双分类补全", systemImage: "square.3.layers.3d")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                }.buttonStyle(.glass).controlSize(.large)
                DisclosureGroup(isExpanded: $showColors) {
                    ColorPicker("选中颜色", selection: $selectedColor).font(.subheadline)
                } label: {
                    Label("自定义修改颜色", systemImage: "paintpalette")
                        .font(.subheadline).foregroundStyle(.primary)
                }.padding(.horizontal, 8)
                HStack(spacing: 12) {
                    Button {} label: {
                        Label("清空", systemImage: "trash").frame(maxWidth: .infinity)
                    }.buttonStyle(.glassProminent).tint(.blue).controlSize(.large)
                    Button {} label: {
                        Label("导出 ZIP", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }.buttonStyle(.glassProminent).tint(.green).controlSize(.large)
                }.font(.subheadline.weight(.semibold))
            }
        }
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
                "apis": ["glassEffect(.regular.interactive())", "buttonStyle(.glass)", "buttonStyle(.glassProminent)", "Picker(.segmented)", "TabView with search role"],
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
#endif
