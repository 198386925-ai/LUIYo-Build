import SwiftUI

// Native Settings page (build 47+)
// Replaces the WebView-based settings tab with native SwiftUI.
// The WebView is kept only as a hidden JS engine.

final class NativeSettingsModel: ObservableObject {
    @Published var deviceCode: String = ""
    @Published var tier: String = "free"
    @Published var appBackgroundColor: String = "#F2F2F7"
    @Published var appCardColor: String = "#FFFFFF"
    @Published var appButtonColor: String = "#FFFFFF"
    
    var onCommand: ((String, [String: Any]) -> Void)?
    
    func send(_ action: String, _ values: [String: Any] = [:]) {
        onCommand?(action, values)
    }
}

struct LUIYoNativeSettings: View {
    @ObservedObject var model: NativeSettingsModel
    
    var body: some View {
        List {
            // Hero section
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("LUIYo")
                            .font(.system(size: 25, weight: .bold))
                        Text("设置")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    // Tier chip
                    Text(model.tier == "svip" ? "SVIP会员" : model.tier == "vip" ? "VIP会员" : "免费版")
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                }
                .padding(.vertical, 8)
                
                if !model.deviceCode.isEmpty {
                    HStack {
                        Text("设备码")
                        Spacer()
                        Text(model.deviceCode)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Theme section
            Section(header: Text("主题")) {
                ColorPickerRow(title: "背景颜色", hex: $model.appBackgroundColor) { hex in
                    model.send("theme", ["key": "appBackgroundColor", "value": hex])
                }
                ColorPickerRow(title: "卡片颜色", hex: $model.appCardColor) { hex in
                    model.send("theme", ["key": "appCardColor", "value": hex])
                }
                ColorPickerRow(title: "按钮颜色", hex: $model.appButtonColor) { hex in
                    model.send("theme", ["key": "appButtonColor", "value": hex])
                }
            }
            
            // About section
            Section(header: Text("关于")) {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.7 (Build 47)")
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("设置")
    }
}

struct ColorPickerRow: View {
    let title: String
    @Binding var hex: String
    let onChange: (String) -> Void
    
    @State private var color: Color
    
    init(title: String, hex: Binding<String>, onChange: @escaping (String) -> Void) {
        self.title = title
        self._hex = hex
        self.onChange = onChange
        self._color = State(initialValue: Color(hex: hex.wrappedValue) ?? .white)
    }
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            ColorPicker("", selection: $color)
                .labelsHidden()
                .onChange(of: color) { newColor in
                    let newHex = newColor.toHex() ?? "#FFFFFF"
                    hex = newHex
                    onChange(newHex)
                }
        }
    }
}

// Helpers
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
    
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
