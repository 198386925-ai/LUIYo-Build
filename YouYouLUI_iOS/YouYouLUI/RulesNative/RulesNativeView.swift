import SwiftUI

/// Native SwiftUI replacement for the web-based Rules page (Build 111).
/// Replicates the web's custom design exactly — no Form, no Section,
/// no default List styling, no UISegmentedControl.
struct RulesNativeView: View {
    @State private var searchText = ""
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    // MARK: - Palette (from Build 111 Web/index.html)
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
    private var searchBackground: Color {
        isDark ? Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
               : .white
    }
    private var searchBorder: Color {
        isDark ? Color(red: 0x34 / 255, green: 0x34 / 255, blue: 0x38 / 255)
               : Color(red: 205 / 255, green: 212 / 255, blue: 220 / 255, opacity: 0.72)
    }
    private var searchTextColor: Color {
        isDark ? Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255)
               : headTitleColor
    }
    private var groupTitleColor: Color {
        Color(red: 0x77 / 255, green: 0x81 / 255, blue: 0x8D / 255)
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
        if searchText.isEmpty {
            return NamingRulesData.rules
        }
        let q = searchText.lowercased()
        return NamingRulesData.rules.filter {
            $0.title.lowercased().contains(q) ||
            $0.section.lowercased().contains(q) ||
            $0.file.lowercased().contains(q)
        }
    }

    private var groupedSections: [String] {
        var seen: [String] = []
        for rule in filteredRules {
            if !seen.contains(rule.section) {
                seen.append(rule.section)
            }
        }
        return seen
    }

    private func rules(in section: String) -> [NamingRule] {
        filteredRules.filter { $0.section == section }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // .pageHead { margin:8px 2px 16px }
                // h1 { font-size:25px; font-weight:800; color:#18202a }
                VStack(alignment: .leading, spacing: 5) {
                    Text("规则")
                        .font(.system(size: 25, weight: .heavy)) // weight 800
                        .foregroundColor(headTitleColor)
                    Text("共 426 条命名规则")
                        .font(.system(size: 14))
                        .foregroundColor(headSubColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.horizontal, 2)
                .padding(.bottom, 16)

                // .ruleSearch { height:46px; border-radius:16px;
                //   border:1px solid rgba(205,212,220,.72); padding:0 15px;
                //   margin:0 0 14px; background:#fff; font-size:14px }
                TextField(
                    "",
                    text: $searchText,
                    prompt: Text("搜索规则")
                        .foregroundColor(Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255))
                )
                .font(.system(size: 14))
                .foregroundColor(searchTextColor)
                .padding(.horizontal, 15)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 16).fill(searchBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(searchBorder, lineWidth: 1)
                )
                .padding(.bottom, 14)

                // Groups + rows
                ForEach(groupedSections, id: \.self) { section in
                    // .ruleGroupTitle { font-size:13px; font-weight:750; color:#77818d;
                    //   padding:10px 4px 1px }
                    Text(section)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(groupTitleColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 1)

                    let sectionRules = rules(in: section)
                    ForEach(Array(sectionRules.enumerated()), id: \.element.id) { index, rule in
                        VStack(spacing: 0) {
                            // .ruleName { font-size:14px; font-weight:760; color:#202832 }
                            // .ruleFile { font-size:11px; color:#8a94a0 }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.title)
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundColor(ruleNameColor)
                                Text(rule.file)
                                    .font(.system(size: 11))
                                    .foregroundColor(ruleFileColor)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            if index < sectionRules.count - 1 {
                                Rectangle()
                                    .fill(rowDividerColor)
                                    .frame(height: 1)
                            }
                        }
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 14) // .app { padding:0 14px }
        }
        .background(pageBackground)
    }
}

#Preview {
    RulesNativeView()
}
