import SwiftUI

/// Native SwiftUI replacement for the web-based Settings page (Build 111).
/// Replicates the web's custom card design exactly — .settingsFold cards,
/// custom header, CSS-style chevron, animated collapse.
/// No Form, no Section, no default List styling, no UISegmentedControl.
struct SettingsNativeView: View {
    @ObservedObject var model: SettingsNativeModel
    @Environment(\.colorScheme) private var colorScheme

    init(model: SettingsNativeModel = SettingsNativeModel()) {
        self.model = model
    }

    private var isDark: Bool { colorScheme == .dark }

    // MARK: - Palette (from Build 111 Web/index.html)
    private var pageBackground: Color {
        isDark ? .black : Color(red: 0xF5 / 255, green: 0xF3 / 255, blue: 0xEF / 255)
    }
    private var headTitleColor: Color {
        isDark ? Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255)
               : Color(red: 0x18 / 255, green: 0x20 / 255, blue: 0x2A / 255)
    }
    private var gray: Color {
        Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // .settingsHead { padding:10px 4px 18px }
                VStack(alignment: .leading, spacing: 5) {
                    Text("设置")
                        .font(.system(size: 28, weight: .heavy)) // weight 800
                        .tracking(-0.5)
                        .foregroundColor(headTitleColor)
                    Text("主题、使用说明与更新日志")
                        .font(.system(size: 14))
                        .foregroundColor(gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .padding(.horizontal, 4)
                .padding(.bottom, 18)

                // The three collapsible cards
                VStack(spacing: 12) {
                    SettingsFold(
                        icon: "circle.lefthalf.filled",
                        title: "主题",
                        subtitle: "卡片材质、背景、按钮与字体",
                        isExpanded: $model.themeExpanded,
                        isDark: isDark
                    ) {
                        // .themeBody { padding:4px 14px 8px }
                        ThemeSectionView(model: model)
                            .padding(.top, 4)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                    }

                    SettingsFold(
                        icon: "questionmark",
                        title: "使用说明",
                        subtitle: "查看功能说明与操作方法",
                        isExpanded: $model.guideExpanded,
                        isDark: isDark
                    ) {
                        GuideBodyView(isDark: isDark)
                            .padding(.top, 14)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 17)
                    }

                    SettingsFold(
                        icon: "clock",
                        title: "更新日志",
                        subtitle: "Version 1.0.6 · 当前版本",
                        isExpanded: $model.changelogExpanded,
                        isDark: isDark
                    ) {
                        ChangelogBodyView(isDark: isDark)
                            .padding(.top, 14)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 17)
                    }
                }

                // Footer
                VStack(spacing: 4) {
                    Text("特别鸣谢 Mk · 作者：优优")
                    Text("仅供学习交流")
                }
                .font(.system(size: 12))
                .foregroundColor(gray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 14) // .app { padding:0 14px }
        }
        .background(pageBackground)
    }
}

// MARK: - Collapsible card (.settingsFold)

/// .settingsFold { border-radius:22px; border:1px solid rgba(120,120,128,.18);
///   background:rgba(255,255,255,.50) }
/// Dark: background rgba(28,28,30,.48); border-color rgba(255,255,255,.13).
/// summary { min-height:76px; padding:12px 15px; grid: 42px 1fr 18px; gap:11px }
struct SettingsFold<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isExpanded: Bool
    let isDark: Bool
    @ViewBuilder let content: () -> Content

    private var cardBackground: Color {
        isDark ? Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255, opacity: 0.48)
               : Color.white.opacity(0.50)
    }
    private var cardBorder: Color {
        isDark ? Color(red: 1, green: 1, blue: 1, opacity: 0.13)
               : Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255, opacity: 0.18)
    }
    private var titleColor: Color {
        isDark ? Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255)
               : Color(red: 0x20 / 255, green: 0x28 / 255, blue: 0x32 / 255)
    }
    private var gray: Color {
        Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.28)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 11) {
                    // .settingsFoldIcon { 42x42 circle; background:rgba(255,255,255,.38); font-size:21px }
                    Image(systemName: icon)
                        .font(.system(size: 21))
                        .foregroundColor(titleColor)
                        .frame(width: 42, height: 42)
                        .background(
                            Circle().fill(
                                isDark ? Color.white.opacity(0.20)
                                       : Color.white.opacity(0.38)
                            )
                        )
                    // .settingsFoldText b { font-size:15px } small { 11.5px #8e8e93 }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(titleColor)
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundColor(gray)
                    }
                    Spacer(minLength: 0)
                    // 18px chevron slot
                    FoldChevron(expanded: isExpanded)
                        .frame(width: 18, alignment: .center)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .frame(minHeight: 76)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    // .settingsFoldBody { border-top:1px solid rgba(120,120,128,.14) }
                    Rectangle()
                        .fill(Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255, opacity: 0.14))
                        .frame(height: 1)
                    content()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 22).fill(cardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(cardBorder, lineWidth: 1)
        )
    }
}

/// CSS-drawn chevron: 10x10, 2px #9a9aa0, rotates 45°→225° on expand (.2s ease).
struct FoldChevron: View {
    let expanded: Bool

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 1, y: 3.5))
            p.addLine(to: CGPoint(x: 5, y: 7.5))
            p.addLine(to: CGPoint(x: 9, y: 3.5))
        }
        .stroke(Color(red: 0x9A / 255, green: 0x9A / 255, blue: 0xA0 / 255), lineWidth: 2)
        .frame(width: 10, height: 10)
        .rotationEffect(.degrees(expanded ? 180 : 0))
        .animation(.easeInOut(duration: 0.2), value: expanded)
    }
}

// MARK: - 使用说明 (.settingsFoldBody guideInline)

struct GuideBodyView: View {
    let isDark: Bool

    private var titleColor: Color {
        isDark ? Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255)
               : Color(red: 0x20 / 255, green: 0x28 / 255, blue: 0x32 / 255)
    }
    private var bodyColor: Color {
        isDark ? Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255)
               : Color(red: 0x73 / 255, green: 0x77 / 255, blue: 0x7F / 255)
    }
    private var leadColor: Color {
        isDark ? Color(red: 0xE8 / 255, green: 0xE8 / 255, blue: 0xED / 255)
               : Color(red: 0x27 / 255, green: 0x31 / 255, blue: 0x3C / 255)
    }

    private let items: [(String, String)] = [
        ("关键词批量导入：", "图片文件名使用网页标题中的关键词即可模糊匹配，模糊关键词至少 3 个字，两个字请使用完整标题。"),
        ("双分类补全：", "用一张补全图片同时填充 LiquidUI 与原版微信中还没有图片的项目。"),
        ("自动联动：", "同一图标对应多个内部命名时，上传一次即可在导出时自动生成相关文件。"),
        ("颜色修改：", "可分别设置浅色选中、深色选中和全部图标颜色；不开启时保留默认处理。"),
        ("排除图标：", "补全后不想更换的项目可以点卡片上的删除按钮，该项目不会进入本次 ZIP。"),
        ("导出：", "生成 ZIP 后可改名，再通过 iPhone 系统分享菜单保存或分享。导出的 ZIP 解压后，把全部图片放进「文件」App → 微信 → LiquidUI/Icons 根目录（不带 @3x 的那组图也放这里），再到 LiquidUI 设置 → 全局换图标点「重新扫描图片文件夹」或重启微信。"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // h3 { margin:0 0 8px; color:#202832; font-size:14px }
            Text("这个工具有什么用？")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(titleColor)
            Text("用于快速制作 LiquidUI / 微信图标替换包。只需按网页标题上传图片，管理器会自动处理对应命名、同名同步、补全、颜色和 ZIP 打包，不需要自己逐个查内部文件名。")
                .font(.system(size: 12.5))
                .foregroundColor(bodyColor)
                .lineSpacing(12.5 * 0.62) // line-height 1.62
            ForEach(items, id: \.0) { lead, text in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .font(.system(size: 12.5))
                        .foregroundColor(bodyColor)
                    (
                        Text(lead)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(leadColor)
                        + Text(text)
                            .font(.system(size: 12.5))
                            .foregroundColor(bodyColor)
                    )
                    .lineSpacing(12.5 * 0.62)
                }
            }
        }
    }
}

// MARK: - 更新日志 (.settingsFoldBody changelogInline)

struct ChangelogEntry: Identifiable {
    let id = UUID()
    let tag: String? // 新增 / 优化 / 修复
    let text: String
}

struct ChangelogVersion: Identifiable {
    let id = UUID()
    let title: String
    let isCurrent: Bool
    let entries: [ChangelogEntry]
}

struct ChangelogBodyView: View {
    let isDark: Bool

    private var titleColor: Color {
        isDark ? Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255)
               : Color(red: 0x20 / 255, green: 0x28 / 255, blue: 0x32 / 255)
    }
    private var bodyColor: Color {
        isDark ? Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255)
               : Color(red: 0x73 / 255, green: 0x77 / 255, blue: 0x7F / 255)
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "新增": return Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
        case "优化": return Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
        case "修复": return Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
        default: return bodyColor
        }
    }

    private let versions: [ChangelogVersion] = [
        ChangelogVersion(title: "Version 1.0.6", isCurrent: true, entries: [
            ChangelogEntry(tag: "新增", text: "支持图标上传、关键词批量导入、双分类补全与 ZIP 导出。"),
            ChangelogEntry(tag: "优化", text: "首页、规则与设置采用系统原生玻璃，低版本自动使用原生磨砂；缩小工具栏文字与规则条目间距。"),
            ChangelogEntry(tag: "优化", text: "原版微信与 LiquidUI 分类及导入入口互换，默认显示原版微信；统一反馈与客服联系入口图标。"),
            ChangelogEntry(tag: "优化", text: "移除分类描边、规则分割线及多余阴影；卡片颜色仅作用于授权上方的品牌卡，统一开关样式。"),
            ChangelogEntry(tag: "修复", text: "修复导入图片删除、补全导出、主题字体保存及底栏搜索布局切换。"),
            ChangelogEntry(tag: "修复", text: "优化底栏切换响应，恢复悬浮底栏与首页安全区，保持设置展开状态。"),
            ChangelogEntry(tag: "修复", text: "插件信息与更新日志支持定位展开，再次点击收起。"),
        ]),
        ChangelogVersion(title: "Version 1.0.5", isCurrent: false, entries: [
            ChangelogEntry(tag: "优化", text: "修复已知问题。"),
            ChangelogEntry(tag: nil, text: "该版本为首发测试。"),
        ]),
        ChangelogVersion(title: "Version 1.0.4", isCurrent: false, entries: [
            ChangelogEntry(tag: "新增", text: "主题支持工具栏卡片透明度、滚动缩小底栏及自定义背景图片；设置自动保存。"),
            ChangelogEntry(tag: "新增", text: "底栏搜索改为关闭、合并、分开三段切换，保留已保存的搜索布局；关闭后恢复顶部搜索框。"),
            ChangelogEntry(tag: "优化", text: "相同或相近用途的图标合并为一个上传入口，共用图标归原版微信；LiquidUI 分类保留专属入口，导出保留全部对应文件名。"),
            ChangelogEntry(tag: "优化", text: "首页上传项每排两列，左图右标题；LiquidUI 与原版微信的导入项和规则分组标题统一缩小；更新规则按大标题合并展示。"),
            ChangelogEntry(tag: "优化", text: "导出 ZIP 改名使用系统原生弹窗。"),
            ChangelogEntry(tag: "优化", text: "补全图片和自定义颜色入口略微加粗描边，增加柔和淡色底。"),
            ChangelogEntry(tag: "优化", text: "首页工具卡片改用纯色，其他卡片保持原生材质。"),
            ChangelogEntry(tag: "优化", text: "清空固定蓝色、白色文字；导出 ZIP 固定绿色、白色文字。"),
            ChangelogEntry(tag: "优化", text: "首页分类和设置切换同步配色：未选中底色跟随卡片颜色，选中底色跟随按钮颜色。"),
            ChangelogEntry(tag: "修复", text: "合并和分开底栏搜索均可点击，打开原生全屏搜索页，自动弹出键盘，关闭后返回原页面。"),
            ChangelogEntry(tag: "修复", text: "深色液态玻璃下六个按钮不明显，按钮保持独立纯色并自动适配文字颜色。"),
            ChangelogEntry(tag: "修复", text: "原生底栏文字跟随导入字体，恢复默认和重新打开也同步生效。"),
            ChangelogEntry(tag: "修复", text: "分开搜索改用系统原生独立搜索标签，底栏与搜索统一对齐、尺寸及安全区位置。"),
        ]),
        ChangelogVersion(title: "Version 1.0.3", isCurrent: false, entries: [
            ChangelogEntry(tag: "新增", text: "主题增加按钮颜色，首页按钮与分类底色同步；浅色、深色分别保存。"),
            ChangelogEntry(tag: "新增", text: "跟随系统、浅色与深色外观；背景颜色分别保存并随外观切换。"),
            ChangelogEntry(tag: "优化", text: "搜索框位于反馈问题下方，随材质切换为液态玻璃或原生磨砂。"),
            ChangelogEntry(tag: "优化", text: "首页六个操作按钮保持纯色，其他卡片保留原有材质。"),
            ChangelogEntry(tag: "优化", text: "分类未选中底色使用按钮颜色，增加透明度以呈现柔和层次。"),
            ChangelogEntry(tag: "优化", text: "分类、材质与外观使用紧凑原生分段控件；缩短设置卡片。"),
            ChangelogEntry(tag: "优化", text: "移除自定义卡片描边，鸣谢仅在设置页随内容排布。"),
            ChangelogEntry(tag: "修复", text: "展开动画结束时的高度跳动和重复点击状态。"),
        ]),
        ChangelogVersion(title: "Version 1.0.2", isCurrent: false, entries: [
            ChangelogEntry(tag: "新增", text: "卡片液态效果开关；关闭后切换为 UIKit 原生磨砂效果。"),
            ChangelogEntry(tag: "新增", text: "主题内自定义字体，可导入 TTF、OTF、WOFF、WOFF2 文件并持久保存。"),
            ChangelogEntry(tag: "新增", text: "卡片材质、液态玻璃、原生磨砂两种模式直接切换/低于26+不生效液态玻璃。"),
            ChangelogEntry(tag: "新增", text: "主题增加卡片颜色，可修改纯色卡片颜色"),
            ChangelogEntry(tag: "优化", text: "规则页移除图片导入入口，仅显示规则名称与图标规则名。"),
            ChangelogEntry(tag: "优化", text: "首页采用新的双列卡片UI，上传区工具区与顶部信息重新布局。"),
            ChangelogEntry(tag: "优化", text: "设置页入口卡片进一步压缩高度与文字尺寸。"),
            ChangelogEntry(tag: "优化", text: "首页白色工具控件、搜索框、颜色展开项、清空按钮、分类未选中项和上传框统一接入 UIKit 原生玻璃/磨砂材质。"),
            ChangelogEntry(tag: "优化", text: "材质切换与首页分类分段切换改为参考图的胶囊式，选中项使用内嵌白色圆角块。"),
            ChangelogEntry(tag: "优化", text: "首页按钮、搜索框、颜色入口与导出操作统一为分类栏同类圆润胶囊轮廓。"),
            ChangelogEntry(tag: "优化", text: "纯色模式下首页操作框统一为同一中性底色，补全图片、自定义颜色、清空等入口保持清晰可见。"),
            ChangelogEntry(tag: "修复", text: "设置页使用说明与更新日志改为原位下拉拉伸卡片。"),
            ChangelogEntry(tag: "修复", text: "规则页顶部安全区与状态栏重叠问题。"),
            ChangelogEntry(tag: "修复", text: "首页、规则、设置三页卡片视觉统一，首页工具卡不再使用单独的透明样式。"),
            ChangelogEntry(tag: "修复", text: "使用说明、更新日志与主题卡片收起响应延迟，收起动画改为快速响应。"),
            ChangelogEntry(tag: "修复", text: "纯色模式默认不显示卡片描边；只有主动开启卡片描边后才显示所选描边颜色。"),
            ChangelogEntry(tag: "修复", text: "背景颜色现在同步到 UIKit 根视图，修改后立即生效并保存。"),
            ChangelogEntry(tag: "修复", text: "首页双分类切换中间露出的白色材质块；分类容器不再重复叠加玻璃。"),
            ChangelogEntry(tag: "修复", text: "液态玻璃与原生磨砂在刷新、筛选和重绘时原生材质层重新绑定导致的跳动。"),
        ]),
        ChangelogVersion(title: "Version 1.0.1", isCurrent: false, entries: [
            ChangelogEntry(tag: "新增", text: "全局换图标规则页，可按规则名称与图标规则名查找。"),
            ChangelogEntry(tag: "新增", text: "关键词批量导入、双分类补全、同名项目自动联动与 ZIP 自定义名称分享。"),
            ChangelogEntry(tag: "新增", text: "浅色选中、深色选中及全部图标颜色自定义。"),
            ChangelogEntry(tag: "优化", text: "设置页的使用说明与更新日志改为原位下拉拉伸，不再弹出独立页面。"),
            ChangelogEntry(tag: "优化", text: "iOS 26+ 使用 UIKit 系统原生 Liquid Glass；不使用 CSS 自绘玻璃。"),
            ChangelogEntry(tag: "优化", text: "iOS 25 及以下自动回退 UIKit 原生 systemMaterial 磨砂。"),
            ChangelogEntry(tag: "优化", text: "规则页移除图片导入入口，只保留规则名称与图标规则名。"),
            ChangelogEntry(tag: "修复", text: "规则页安全区，避免标题与状态栏重叠。"),
        ]),
        ChangelogVersion(title: "Version 1.0.0", isCurrent: false, entries: [
            ChangelogEntry(tag: "新增", text: "优优 LUI 图标补全基础功能。"),
            ChangelogEntry(tag: "新增", text: "LiquidUI / 原版微信图标上传、补全与 ZIP 导出。"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(versions) { version in
                VStack(alignment: .leading, spacing: 9) {
                    // .inlineVersionTitle { font-size:15px; font-weight:700; margin-bottom:10px }
                    HStack(spacing: 8) {
                        Text(version.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(titleColor)
                        if version.isCurrent {
                            // .inlineVersionTitle span { font-size:12px; color:#0a84ff }
                            Text("当前版本")
                                .font(.system(size: 12))
                                .foregroundColor(Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255))
                        }
                    }
                    .padding(.bottom, 1)
                    ForEach(version.entries) { entry in
                        if let tag = entry.tag {
                            (
                                Text(tag)
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundColor(tagColor(tag))
                                + Text(" " + entry.text)
                                    .font(.system(size: 12.5))
                                    .foregroundColor(bodyColor)
                            )
                            .lineSpacing(12.5 * 0.62)
                        } else {
                            Text(entry.text)
                                .font(.system(size: 12.5))
                                .foregroundColor(bodyColor)
                                .lineSpacing(12.5 * 0.62)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsNativeView()
}
