import SwiftUI
import UniformTypeIdentifiers

// MARK: - NativeThemeSection
//
// Native SwiftUI replacement for the web "主题" (Theme) settings section.
// Only the theme rows — no header hero, no activation, no changelog.
//
// ## Parent integration contract
// Create with an `onChange` closure. The parent MUST, inside `onChange`,
//  1. persist the value to UserDefaults, and
//  2. sync it into the WKWebView via JavaScript.
//
// Setting keys (String) and value types:
//
//  NativeThemeSettingKey.appearance       String  "system" | "light" | "dark"
//      UD: "youyou.theme.appearance"
//      JS: applyMode("<value>")                      // global in web page
//
//  NativeThemeSettingKey.material         String  "liquid" | "blur"
//      UD: "youyou.cardMaterialMode"
//      JS: document.querySelector('#materialModePicker [data-material="<value>"]').click()
//
//  NativeThemeSettingKey.backgroundColor  String  "#RRGGBB"
//      UD: "youyou.theme.background"
//      JS: set #appBackgroundColor value + dispatch 'input', or applyColors()
//
//  NativeThemeSettingKey.cardColor        String  "#RRGGBB"
//      UD: "youyou.theme.heroCardColor"
//      JS: set #appCardColor value + dispatch 'input', or applyColors()
//
//  NativeThemeSettingKey.bottomSearchMode String  "off" | "merged" | "separate"
//      UD: "youyou.theme.bottomSearchMode"
//      JS: document.querySelector('#bottomSearchModePicker [data-bottom-search-mode="<value>"]').click()
//
//  NativeThemeSettingKey.shrinkOnScroll   Bool
//      UD: "youyou.minimizeBottomBar"   (native setScrollMinimize reads this key)
//      JS: applyShrink(true/false)       // global; also fires minimizeBottomBar -> native
//      Native: call setScrollMinimize(enabled) as well (tabBarMinimizeBehavior)
//
//  NativeThemeSettingKey.importFont       [String: Any] ["name": String, "data": Data]
//      Parent: persist font (ApplicationSupport/ThemeFont.data), register via setNativeFont,
//      and sync to web: applyFont(base64, name)
//
//  NativeThemeSettingKey.resetFont        Bool (true)
//      Parent: clear stored font, remove @font-face from web, reset label.
//
// The view reads initial values from UserDefaults in init, so the parent only
// needs to write UserDefaults inside `onChange` — no refresh plumbing needed.

enum NativeThemeSettingKey {
    static let appearance = "appearance"
    static let material = "material"
    static let backgroundColor = "backgroundColor"
    static let cardColor = "cardColor"
    static let bottomSearchMode = "bottomSearchMode"
    static let shrinkOnScroll = "shrinkOnScroll"
    static let importFont = "importFont"
    static let resetFont = "resetFont"
}

struct NativeThemeSection: View {
    var onChange: (String, Any) -> Void

    @State private var appearance: String
    @State private var material: String
    @State private var backgroundColor: Color
    @State private var cardColor: Color
    @State private var bottomSearchMode: String
    @State private var shrinkOnScroll: Bool
    @State private var fontName: String
    @State private var showingFontPicker = false

    private static let defaultBackgroundHex = "#F4F2EE"
    private static let defaultCardHex = "#FFFFFF"

    init(onChange: @escaping (String, Any) -> Void) {
        self.onChange = onChange
        let d = UserDefaults.standard

        let rawAppearance = d.string(forKey: "youyou.theme.appearance") ?? "system"
        _appearance = State(initialValue: ["system", "light", "dark"].contains(rawAppearance) ? rawAppearance : "system")

        let rawMaterial = d.string(forKey: "youyou.cardMaterialMode") ?? "liquid"
        _material = State(initialValue: rawMaterial == "blur" ? "blur" : "liquid")

        _backgroundColor = State(initialValue: Self.color(fromHex: d.string(forKey: "youyou.theme.background")
            ?? Self.defaultBackgroundHex))
        _cardColor = State(initialValue: Self.color(fromHex: d.string(forKey: "youyou.theme.heroCardColor")
            ?? Self.defaultCardHex))

        let rawSearch = d.string(forKey: "youyou.theme.bottomSearchMode") ?? "off"
        _bottomSearchMode = State(initialValue: ["off", "merged", "separate"].contains(rawSearch) ? rawSearch : "off")

        _shrinkOnScroll = State(initialValue: d.bool(forKey: "youyou.minimizeBottomBar"))
        _fontName = State(initialValue: d.string(forKey: "youyou.theme.customFontName") ?? "使用默认字体")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header (mirrors web <summary>: 主题 / 卡片材质、背景、按钮与字体)
            HStack(spacing: 12) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("主题").font(.headline)
                    Text("卡片材质、背景、按钮与字体")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            themeCard {
                VStack(spacing: 0) {
                    themeRow(title: "外观模式", subtitle: appearanceHint) {
                        Picker("外观模式", selection: $appearance) {
                            Text("跟随系统").tag("system")
                            Text("浅色").tag("light")
                            Text("深色").tag("dark")
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                    }
                    Divider().padding(.leading, 4)

                    themeRow(title: "卡片材质", subtitle: "液态玻璃：iOS 26+ UIKit 原生 Liquid Glass") {
                        Picker("卡片材质", selection: $material) {
                            Text("液态玻璃").tag("liquid")
                            Text("原生磨砂").tag("blur")
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                    }
                    Divider().padding(.leading, 4)

                    themeRow(title: "背景颜色", subtitle: "浅色背景") {
                        HStack(spacing: 10) {
                            ColorPicker("", selection: $backgroundColor, supportsOpacity: false)
                                .labelsHidden()
                            glassButton("恢复") {
                                backgroundColor = Self.color(fromHex: Self.defaultBackgroundHex)
                            }
                        }
                    }
                    Divider().padding(.leading, 4)

                    themeRow(title: "卡片颜色", subtitle: "仅修改激活授权上方的品牌卡") {
                        HStack(spacing: 10) {
                            ColorPicker("", selection: $cardColor, supportsOpacity: false)
                                .labelsHidden()
                            glassButton("恢复") {
                                cardColor = Self.color(fromHex: Self.defaultCardHex)
                            }
                        }
                    }
                    Divider().padding(.leading, 4)

                    themeRow(title: "底栏搜索按钮", subtitle: "关闭后使用顶部搜索框") {
                        Picker("底栏搜索按钮", selection: $bottomSearchMode) {
                            Text("关闭").tag("off")
                            Text("合并").tag("merged")
                            Text("分开").tag("separate")
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                    }
                    Divider().padding(.leading, 4)

                    // NATIVE Toggle -> renders as real UISwitch. This is the whole
                    // point of this file: no web replica, no overlay hacks.
                    Toggle(isOn: $shrinkOnScroll) {
                        themeRowLabel(title: "滚动时缩小底栏", subtitle: "向下滚动缩小，向上滚动恢复")
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)

                    Divider().padding(.leading, 4)

                    themeRow(title: "自定义字体", subtitle: fontName) {
                        HStack(spacing: 10) {
                            glassButton("导入字体") { showingFontPicker = true }
                            glassButton("恢复") {
                                fontName = "使用默认字体"
                                onChange(NativeThemeSettingKey.resetFont, true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .onChange(of: appearance) { onChange(NativeThemeSettingKey.appearance, $0) }
        .onChange(of: material) { onChange(NativeThemeSettingKey.material, $0) }
        .onChange(of: backgroundColor) { onChange(NativeThemeSettingKey.backgroundColor, Self.hexString(from: $0)) }
        .onChange(of: cardColor) { onChange(NativeThemeSettingKey.cardColor, Self.hexString(from: $0)) }
        .onChange(of: bottomSearchMode) { onChange(NativeThemeSettingKey.bottomSearchMode, $0) }
        .onChange(of: shrinkOnScroll) { onChange(NativeThemeSettingKey.shrinkOnScroll, $0) }
        .fileImporter(
            isPresented: $showingFontPicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first, url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                let ext = url.pathExtension.lowercased()
                guard ["ttf", "otf", "woff", "woff2"].contains(ext),
                      let data = try? Data(contentsOf: url) else { return }
                fontName = url.deletingPathExtension().lastPathComponent
                onChange(NativeThemeSettingKey.importFont,
                         ["name": url.lastPathComponent, "data": data] as [String: Any])
            case .failure:
                break
            }
        }
    }

    // MARK: - Subviews

    private var appearanceHint: String {
        switch appearance {
        case "light": return "浅色"
        case "dark": return "深色"
        default: return "跟随系统外观"
        }
    }

    private func themeRowLabel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body).fontWeight(.semibold)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func themeRow<Control: View>(title: String, subtitle: String,
                                         @ViewBuilder control: () -> Control) -> some View {
        HStack {
            themeRowLabel(title: title, subtitle: subtitle)
            Spacer()
            control()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    /// Card container: iOS 26 native Liquid Glass, plain system fill below.
    private func themeCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            content().glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        } else {
            content()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.secondarySystemBackground))
                )
        }
    }

    /// Small action button (恢复 / 导入字体): native glass on iOS 26+, bordered fallback.
    private func glassButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .modifier(GlassCapsule())
    }

    // MARK: - Color helpers (private names — must NOT clash with the
    // UIColor(nativeHex:) extension already in NativeHome.swift)

    private static func color(fromHex hex: String) -> Color {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = Int(h, radix: 16) else { return .white }
        return Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }

    private static func hexString(from color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - GlassCapsule

/// Capsule glass background for small buttons. iOS 26 native Liquid Glass;
/// frosted fallback on older versions. No custom drawing on iOS 26+.
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                )
                .overlay(
                    Capsule()
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
        }
    }
}
