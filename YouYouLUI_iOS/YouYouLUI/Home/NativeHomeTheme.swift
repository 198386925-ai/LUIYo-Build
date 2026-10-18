import Foundation

/// Palette + flags the bundled HTML reports for the native homepage.
struct NativeHomeTheme: Equatable {
    var background = "#F2F2F7"
    var card = "#FFFFFF"
    var button = "#FFFFFF"
    var actionText = "#202832"
    var dark = false
    var customButton = false
    var bottomSearchEnabled = true
    var toolbarOpacity = 1.0

    init() {}

    init(_ values: [String: Any]) {
        background = values["background"] as? String ?? background
        card = values["card"] as? String ?? card
        button = "#FFFFFF"
        actionText = "#202832"
        dark = values["dark"] as? Bool ?? dark
        customButton = false
        bottomSearchEnabled = values["bottomSearchEnabled"] as? Bool ?? bottomSearchEnabled
        toolbarOpacity = 1
    }
}
