import SwiftUI
import UIKit

// Native Theme Section - inline replacement for web theme section
// Uses iOS 26+ native .glassEffect for true Liquid Glass (no self-draw)
struct NativeThemeInline: View {
    var onShrinkToggle: (Bool) -> Void
    var onResetBackground: () -> Void
    var onResetCard: () -> Void
    var onResetButton: () -> Void
    var onImportFont: () -> Void
    var onResetFont: () -> Void
    
    @State private var shrinkOn: Bool
    @State private var appearance: String
    @State private var material: String
    
    init(onShrinkToggle: @escaping (Bool) -> Void,
         onResetBackground: @escaping () -> Void,
         onResetCard: @escaping () -> Void,
         onResetButton: @escaping () -> Void,
         onImportFont: @escaping () -> Void,
         onResetFont: @escaping () -> Void) {
        self.onShrinkToggle = onShrinkToggle
        self.onResetBackground = onResetBackground
        self.onResetCard = onResetCard
        self.onResetButton = onResetButton
        self.onImportFont = onImportFont
        self.onResetFont = onResetFont
        _shrinkOn = State(initialValue: UserDefaults.standard.bool(forKey: "youyou.minimizeBottomBar"))
        _appearance = State(initialValue: UserDefaults.standard.string(forKey: "youyou.theme.appearance") ?? "system")
        _material = State(initialValue: UserDefaults.standard.string(forKey: "youyou.cardMaterialMode") ?? "liquid")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Appearance
            VStack(alignment: .leading, spacing: 8) {
                Text("外观模式").font(.headline)
                Text("跟随系统外观").font(.caption).foregroundColor(.secondary)
                Picker("", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            
            // Material
            VStack(alignment: .leading, spacing: 8) {
                Text("卡片材质").font(.headline)
                Text("液态玻璃：iOS 26+ UIKit 原生 Liquid Glass").font(.caption).foregroundColor(.secondary)
                Picker("", selection: $material) {
                    Text("液态玻璃").tag("liquid")
                    Text("原生磨砂").tag("blur")
                }
                .pickerStyle(.segmented)
            }
            
            // Background color
            HStack {
                VStack(alignment: .leading) {
                    Text("背景颜色").font(.headline)
                    Text("浅色背景").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                glassButton("恢复", action: onResetBackground)
            }
            
            // Card color
            HStack {
                VStack(alignment: .leading) {
                    Text("卡片颜色").font(.headline)
                    Text("仅修改激活授权上方的品牌卡").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                glassButton("恢复", action: onResetCard)
            }
            
            // Shrink toggle - NATIVE Toggle
            HStack {
                VStack(alignment: .leading) {
                    Text("滚动时缩小底栏").font(.headline)
                    Text("向下滚动缩小，向上滚动恢复").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $shrinkOn)
                    .labelsHidden()
                    .onChange(of: shrinkOn) { onShrinkToggle($0) }
            }
            
            // Font
            HStack {
                VStack(alignment: .leading) {
                    Text("自定义字体").font(.headline)
                    Text("使用默认字体").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                glassButton("导入字体", action: onImportFont)
                glassButton("恢复", action: onResetFont)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // iOS 26+ native glass button, fallback to system button
    @ViewBuilder
    private func glassButton(_ title: String, action: @escaping () -> Void) -> some View {
        if #available(iOS 26.0, *) {
            Button(title, action: action)
                .buttonStyle(.glass)
        } else {
            Button(title, action: action)
                .buttonStyle(.bordered)
        }
    }
}
