import SwiftUI

/// Native homepage: an icon grid driven by the shared web engine.
/// Layout and copy are unchanged from the shipped build.
struct LUIYoNativeHome: View {
    @ObservedObject var model: NativeHomeModel
    @State private var category = 0
    @State private var showColors = false
    @FocusState private var searchFocused: Bool
    @State private var selectedColor = Color.blue
    @State private var darkSelectedColor = Color.white
    @State private var allColor = Color(uiColor: .darkGray)
    @State private var selectedEnabled = false
    @State private var darkSelectedEnabled = false
    @State private var allEnabled = false

    private let catalog = NativeIconCatalog.load()
    private var query: String { model.query }
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
            .onChange(of: category) { value in
                model.send("category", ["category": value == 0 ? "wechat" : "liquidui"])
            }
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
                    model.saveColors(["selectedLightEnabled": selectedEnabled,
                                      "selectedDarkEnabled": darkSelectedEnabled,
                                      "allColorEnabled": allEnabled,
                                      "selectedColor": UIColor(selectedColor).nativeHex,
                                      "selectedDarkColor": UIColor(darkSelectedColor).nativeHex,
                                      "allColor": UIColor(allColor).nativeHex])
                }
            }
    }

    private var home: some View {
        ScrollViewReader { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if !model.theme.bottomSearchEnabled { inlineSearch }
                    tools
                    NativeHomeCategoryPicker(selection: $category, theme: model.theme,
                                             font: model.importedFont, useBlur: model.useBlur)
                        .frame(height: 34)
                    // Progress belongs after the picker, so loading cannot move the categories.
                    if !model.status.isEmpty && !model.status.hasPrefix("已上传 ") {
                        Text(model.status)
                            .font(model.font(size: 12))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("nativeHomeStatus")
                    }
                    categoryHeading
                    if visibleEntries.isEmpty && !query.isEmpty {
                        Text("没有匹配的图标").font(model.font(size: 13)).foregroundStyle(.secondary)
                    }
                    NativeGlassGroup {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                            ForEach(visibleEntries) { item in
                                HStack(spacing: 0) {
                                    Button { model.send("upload", ["id": item.id]) } label: {
                                        HStack(spacing: 8) {
                                            thumbnail(for: item)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(item.title)
                                                    .font(model.font(size: 12, weight: .semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(2)
                                                Text(model.images[item.id] == nil ? "点击上传" : "已上传 · 点击替换")
                                                    .font(model.font(size: 11))
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, minHeight: 64)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("上传" + item.title)
                                    if model.images[item.id] != nil {
                                        Button { model.send("remove", ["id": item.id]) } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 18))
                                                .foregroundStyle(.red)
                                                .frame(width: 44, height: 64)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("删除" + item.title)
                                        .accessibilityIdentifier("deleteIcon-\(item.id)")
                                    }
                                }
                                .modifier(NativeCardSurface())
                                .id(item.id)
                                .contextMenu {
                                    if model.images[item.id] != nil {
                                        Button("移除图标", role: .destructive) { model.send("remove", ["id": item.id]) }
                                    }
                                }
                            }
                        }
                    }
                }
                .labelStyle(NativeAlignedLabelStyle())
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .background(NativeHomeScrollLink(onAttach: { model.onScrollView?($0) }))
            }
            .background {
                if model.backgroundImage == nil {
                    Color(UIColor(nativeHex: model.theme.background)).ignoresSafeArea()
                } else {
                    Color.clear
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("LUIYo").font(model.font(size: 25, weight: .bold))
            Text("微信图标管理").font(model.font(size: 13)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Label(model.authorized ? "已授权" : "未授权",
                      systemImage: model.authorized ? "checkmark.seal.fill" : "lock.fill")
                    .font(model.font(size: 12, weight: .medium))
                    .foregroundStyle(model.authorized ? Color.green : Color.secondary)
                Text("已上传项目：\(model.uploadedCount) 项")
                    .accessibilityIdentifier("nativeUploadedCount")
                    .font(model.font(size: 12))
                    .foregroundStyle(.secondary)
                Link(destination: URL(string: "https://qm.qq.com/q/th1QshgzHW")!) {
                    HStack(spacing: 6) { ToolbarAssetIcon(name: "ToolbarSupport", size: 17); Text("反馈问题 · 联系客服") }
                }
                .font(model.font(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .accessibilityLabel("反馈问题，联系客服")
            }
        }
    }

    private var inlineSearch: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索图标", text: Binding(get: { model.query }, set: { value in
                model.query = value
                model.send("search", ["query": value])
            }))
            .font(model.font(size: 15))
            .submitLabel(.search)
            .focused($searchFocused)
            .onSubmit { searchFocused = false }
            .accessibilityIdentifier("nativeHomeSearch")
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    model.send("search", ["query": ""])
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .modifier(NativeSearchGlass())
    }

    private var categoryHeading: some View {
        HStack {
            Text(category == 0 ? "原版微信图标" : "LiquidUI 图标").font(model.font(size: 17, weight: .semibold))
            Spacer()
            Text("\(categoryEntries.count) 项").font(model.font(size: 12)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func thumbnail(for item: NativeIconEntry) -> some View {
        if let image = model.images[item.id] {
            Image(uiImage: image).resizable().scaledToFit().frame(width: 32, height: 32)
        } else {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(model.theme.customButton ? Color(UIColor(nativeHex: model.theme.actionText)) : Color.white)
                .frame(width: 32, height: 32)
                .background(
                    model.theme.customButton ? Color(UIColor(nativeHex: model.theme.button)) : Color.blue,
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
    }

    private var tools: some View {
        NativeGlassGroup {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button { model.send("batch", [:]) } label: {
                        HStack(spacing: 7) { ToolbarAssetIcon(name: "ToolbarImport", size: 18); Text("关键词批量导入") }
                            .font(model.font(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .modifier(NativeActionStyle())
                    .controlSize(.large)
                    Button { model.send("fillImage", [:]) } label: {
                        HStack(spacing: 7) { ToolbarAssetIcon(name: "ToolbarFill", size: 18); Text("补全图片") }
                            .font(model.font(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .modifier(NativeActionStyle())
                    .controlSize(.large)
                }
                Button { model.send("fill", [:]) } label: {
                    Label("双分类补全", systemImage: "square.3.layers.3d")
                        .font(model.font(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .modifier(NativeActionStyle())
                .controlSize(.large)
                Button {
                    if model.authorized { showColors = true } else { model.send("authorize", [:]) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 18))
                            .frame(width: 20, height: 20)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自定义修改颜色").font(model.font(size: 13, weight: .medium))
                            Text("浅色 / 深色 / 全部图标").font(model.font(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 1)
                }
                .modifier(NativeActionStyle())
                .controlSize(.large)
                .accessibilityIdentifier("nativeColorSettings")
                HStack(spacing: 8) {
                    NativeGlassActionButton(title: "清空", asset: "ToolbarClear", color: "#007AFE",
                                            font: model.importedFont, useBlur: model.useBlur) {
                        model.send("clear", [:])
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    NativeGlassActionButton(title: "导出 ZIP", asset: "ToolbarExport", color: "#46D86A",
                                            font: model.importedFont, useBlur: model.useBlur) {
                        model.send("export", [:])
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .font(model.font(size: 13, weight: .semibold))
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
                } header: {
                    Text("选中 · 浅色模式")
                } footer: {
                    Text("关闭时自动加深上传图片的颜色。")
                }
                Section {
                    Toggle("启用自定义颜色", isOn: $darkSelectedEnabled)
                    ColorPicker("选中颜色", selection: $darkSelectedColor, supportsOpacity: false)
                        .disabled(!darkSelectedEnabled)
                } header: {
                    Text("选中 · 深色模式")
                } footer: {
                    Text("关闭时自动反转上传图片的颜色。")
                }
                Section {
                    Toggle("启用统一颜色", isOn: $allEnabled)
                    ColorPicker("图标颜色", selection: $allColor, supportsOpacity: false)
                        .disabled(!allEnabled)
                } header: {
                    Text("全部图标")
                } footer: {
                    Text("关闭时保留上传图片的原本颜色。")
                }
            }
            .navigationTitle("自定义颜色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showColors = false }
                }
            }
        }
        .navigationViewStyle(.stack)
        .font(model.font(size: 15))
    }
}
