import SwiftUI

// Minimal native Theme section - only the shrink toggle
// Guaranteed to compile: no glassEffect, no fileImporter, no complex generics
struct NativeThemeMinimal: View {
    var onToggle: (Bool) -> Void
    
    @State private var shrinkOn: Bool
    
    init(onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        _shrinkOn = State(initialValue: UserDefaults.standard.bool(forKey: "youyou.minimizeBottomBar"))
    }
    
    var body: some View {
        Form {
            Section(header: Text("主题")) {
                Toggle("滚动时缩小底栏", isOn: $shrinkOn)
                    .onChange(of: shrinkOn) { newValue in
                        onToggle(newValue)
                    }
            }
        }
        .navigationTitle("主题")
    }
}
