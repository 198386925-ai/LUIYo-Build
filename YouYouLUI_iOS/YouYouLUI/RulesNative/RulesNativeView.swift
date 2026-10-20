import SwiftUI
import Combine

/// Shared state for the native Rules page. The shell's bottom search writes
/// its query here so the native list filters live.
final class RulesNativeModel: ObservableObject {
    @Published var query: String = ""
}

/// Native SwiftUI Rules page (route A migration, 2026-10-20).
/// Mirrors the current Web rules page: page head + one white card per
/// section, rows of rule title over target file name. Search comes from the
/// shell's bottom search bar via RulesNativeModel.
struct RulesNativeView: View {
    @ObservedObject var model: RulesNativeModel
    @ObservedObject var homeModel: NativeHomeModel
    @Environment(\.colorScheme) private var colorScheme

    init(model: RulesNativeModel = RulesNativeModel(), homeModel: NativeHomeModel = NativeHomeModel()) {
        self.model = model
        self.homeModel = homeModel
    }

    private var isDark: Bool { colorScheme == .dark }

    private var pageBackground: Color {
        isDark ? .black : Color(red: 0xF5 / 255, green: 0xF3 / 255, blue: 0xEF / 255)
    }
    private var headTitleColor: Color {
        isDark ? Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255)
               : Color(red: 0x18 / 255, green: 0x20 / 255, blue: 0x2A / 255)
    }
    private var headSubColor: Color {
        isDark ? Color(red: 0xA9 / 255, green: 0xA9 / 255, blue: 0xB0 / 255)
               : Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)
    }
    private var ruleNameColor: Color {
        isDark ? Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255)
               : Color(red: 0x20 / 255, green: 0x28 / 255, blue: 0x32 / 255)
    }
    private var ruleFileColor: Color {
        isDark ? Color(red: 0xA9 / 255, green: 0xA9 / 255, blue: 0xB0 / 255)
               : Color(red: 0x8A / 255, green: 0x94 / 255, blue: 0xA0 / 255)
    }
    private var rowDividerColor: Color {
        Color(red: 128 / 255, green: 134 / 255, blue: 144 / 255, opacity: 0.16)
    }

    private var filteredRules: [NamingRule] {
        let q = model.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return NamingRulesData.rules }
        return NamingRulesData.rules.filter {
            $0.title.lowercased().contains(q) ||
            $0.section.lowercased().contains(q) ||
            $0.file.lowercased().contains(q)
        }
    }

    private var groupedSections: [String] {
        var seen: [String] = []
        for rule in filteredRules where !seen.contains(rule.section) {
            seen.append(rule.section)
        }
        return seen
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("规则")
                        .font(.system(size: 25, weight: .heavy))
                        .foregroundColor(headTitleColor)
                    Text("LiquidUI 全局换图标命名规则")
                        .font(.system(size: 14))
                        .foregroundColor(headSubColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.horizontal, 2)
                .padding(.bottom, 16)

                if filteredRules.isEmpty {
                    Text("没有匹配的规则")
                        .font(.system(size: 14))
                        .foregroundColor(headSubColor)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }

                VStack(spacing: 14) {
                    ForEach(groupedSections, id: \.self) { section in
                        sectionCard(section)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 110)
        }
        .environment(\.nativeUseBlur, homeModel.useBlur)
        .environment(\.nativeHomeTheme, homeModel.theme)
        .background(Color(UIColor(nativeHex: homeModel.theme.background)))
    }

    private func sectionCard(_ section: String) -> some View {
        let sectionRules = filteredRules.filter { $0.section == section }
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(section)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ruleNameColor)
                Spacer()
                Text("\(sectionRules.count) 项")
                    .font(.system(size: 12))
                    .foregroundColor(ruleFileColor)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            ForEach(Array(sectionRules.enumerated()), id: \.element.id) { index, rule in
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rule.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(ruleNameColor)
                        Text(rule.file)
                            .font(.system(size: 11))
                            .foregroundColor(ruleFileColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    if index < sectionRules.count - 1 {
                        Rectangle()
                            .fill(rowDividerColor)
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }
            .padding(.bottom, 6)
        }
        .modifier(NativePageCardSurface(radius: 24))
    }
}

#Preview {
    RulesNativeView()
}
