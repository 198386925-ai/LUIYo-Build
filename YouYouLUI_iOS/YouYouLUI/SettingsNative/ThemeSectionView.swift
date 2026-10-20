import SwiftUI
import UniformTypeIdentifiers

/// Native theme section (Build 111 web design).
/// Custom pill segmented controls, plain small buttons, TRUE NATIVE Toggle —
/// no Picker(.segmented) / UISegmentedControl anywhere.
struct ThemeSectionView: View {
    @ObservedObject var model: SettingsNativeModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showFontPicker = false

    private var isDark: Bool { colorScheme == .dark }

    private var titleColor: Color {
        isDark ? Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255)
               : Color(red: 0x20 / 255, green: 0x28 / 255, blue: 0x32 / 255)
    }
    private var subtitleColor: Color {
        Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)
    }
    private var dividerColor: Color {
        Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255, opacity: 0.12)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 外观模式
            themeRow(title: "外观模式", subtitle: appearanceHint, showDivider: true) {
                WebSegmentedControl(
                    options: [("system", "跟随系统"), ("light", "浅色"), ("dark", "深色")],
                    selection: $model.appearanceMode,
                    isDark: isDark
                )
            }

            // 卡片材质
            themeRow(title: "卡片材质", subtitle: "iOS 26+ 原生液态玻璃 / UIKit 原生磨砂", showDivider: true) {
                WebSegmentedControl(
                    options: [("liquid", "液态玻璃"), ("blur", "原生磨砂")],
                    selection: $model.cardMaterial,
                    isDark: isDark
                )
            }

            // 背景颜色
            themeRow(title: "背景颜色", subtitle: "浅色背景", showDivider: true) {
                HStack(spacing: 8) {
                    ColorPicker("", selection: Binding(
                        get: { model.color(for: model.backgroundColorHex) },
                        set: { model.updateBackgroundColor($0.toHex()) }
                    ))
                    .labelsHidden()
                    .frame(width: 34, height: 34)
                    WebSmallButton(title: "恢复", isDark: isDark) {
                        model.resetBackgroundColor()
                    }
                }
            }

            // 卡片颜色
            themeRow(title: "卡片颜色", subtitle: "仅修改激活授权上方的品牌卡", showDivider: true) {
                HStack(spacing: 8) {
                    ColorPicker("", selection: Binding(
                        get: { model.color(for: model.cardColorHex) },
                        set: { model.updateCardColor($0.toHex()) }
                    ))
                    .labelsHidden()
                    .frame(width: 34, height: 34)
                    WebSmallButton(title: "恢复", isDark: isDark) {
                        model.resetCardColor()
                    }
                }
            }

            // 底栏搜索按钮
            themeRow(title: "底栏搜索按钮", subtitle: "关闭后使用顶部搜索框", showDivider: true) {
                WebSegmentedControl(
                    options: [("off", "关闭"), ("merged", "合并"), ("separate", "分开")],
                    selection: $model.bottomSearchLayout,
                    isDark: isDark
                )
            }

            // 滚动时缩小底栏 — TRUE NATIVE Toggle
            themeRow(title: "滚动时缩小底栏", subtitle: "向下滚动缩小，向上滚动恢复", showDivider: true) {
                Toggle("", isOn: $model.minimizeBottomBar)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            // 自定义字体
            themeRow(title: "自定义字体", subtitle: model.customFontName, showDivider: false) {
                HStack(spacing: 8) {
                    WebSmallButton(title: "导入字体", isDark: isDark) {
                        showFontPicker = true
                    }
                    WebSmallButton(title: "恢复", isDark: isDark) {
                        model.fontController?.reset()
                        model.customFontName = "使用默认字体"
                        model.hasCustomFont = false
                        model.onFontChanged?()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFontPicker,
            allowedContentTypes: [.font],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let data = try? Data(contentsOf: url) {
                            if model.fontController?.apply(data) == true {
                                model.customFontName = url.lastPathComponent
                                model.hasCustomFont = true
                                model.onFontChanged?()
                            }
                        }
                    }
                }
            case .failure:
                break
            }
        }
    }

    private var appearanceHint: String {
        switch model.appearanceMode {
        case "system": return "跟随系统"
        case "light": return "浅色"
        case "dark": return "深色"
        default: return "跟随系统"
        }
    }

    /// .themeRow { min-height:58px; space-between; gap:12px;
    ///   border-bottom:1px solid rgba(120,120,128,.12) } (not after last)
    /// title 13.5px #202832 weight 600 · subtitle 10.5px #8e8e93 margin-top 2
    @ViewBuilder
    private func themeRow<Content: View>(
        title: String,
        subtitle: String,
        showDivider: Bool,
        content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(titleColor)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(subtitleColor)
                }
                Spacer(minLength: 0)
                content()
            }
            .frame(minHeight: 58)
            if showDivider {
                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - Custom pill segmented control (web design, no UISegmentedControl)

/// Container: HStack padding 4, cornerRadius 999, background #F1EFEC.
/// Buttons: cornerRadius 999, transparent, text #202832 13pt weight 600.
/// Active: white background, text #111820, shadow (0,1,2, black 3.5%).
struct WebSegmentedControl: View {
    let options: [(tag: String, label: String)]
    @Binding var selection: String
    let isDark: Bool

    private var containerColor: Color {
        isDark ? Color.white.opacity(0.12)
               : Color(red: 0xF1 / 255, green: 0xEF / 255, blue: 0xEC / 255)
    }
    private var idleTextColor: Color {
        isDark ? Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255)
               : Color(red: 0x20 / 255, green: 0x28 / 255, blue: 0x32 / 255)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.tag) { option in
                let active = selection == option.tag
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = option.tag
                    }
                }) {
                    Text(option.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(active
                            ? Color(red: 0x11 / 255, green: 0x18 / 255, blue: 0x20 / 255)
                            : idleTextColor)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            Capsule()
                                .fill(active ? Color.white : Color.clear)
                                .shadow(color: .black.opacity(active ? 0.035 : 0),
                                        radius: 2, x: 0, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(containerColor))
    }
}

// MARK: - Small web-style button

/// background #F4F2EE, cornerRadius 12, padding 7/14, font 11pt #555.
/// Dark: background white, color #202832.
struct WebSmallButton: View {
    let title: String
    let isDark: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(isDark
                    ? Color(red: 0x20 / 255, green: 0x28 / 255, blue: 0x32 / 255)
                    : Color(red: 0x55 / 255, green: 0x55 / 255, blue: 0x55 / 255))
                .lineLimit(1)
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDark ? Color.white
                                    : Color(red: 0xF4 / 255, green: 0xF2 / 255, blue: 0xEE / 255))
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ThemeSectionView(model: SettingsNativeModel())
        .padding()
}
