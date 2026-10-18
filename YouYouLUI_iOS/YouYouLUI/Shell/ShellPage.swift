import Foundation

/// The three content pages. Home is rendered natively (SwiftUI); rules and
/// settings come from the bundled HTML. All three share one WKWebView.
enum ShellPage: Int, CaseIterable {
    case home = 0
    case rules = 1
    case settings = 2

    /// Value used by `appNavTo()` and reported back through `pageState`.
    var name: String {
        switch self {
        case .home: return "home"
        case .rules: return "rules"
        case .settings: return "settings"
        }
    }

    var title: String {
        switch self {
        case .home: return "首页"
        case .rules: return "规则"
        case .settings: return "设置"
        }
    }

    var iconName: String {
        switch self {
        case .home: return "house"
        case .rules: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }

    var selectedIconName: String {
        switch self {
        case .home: return "house.fill"
        case .rules: return "list.bullet.rectangle.fill"
        case .settings: return "gearshape.fill"
        }
    }

    /// Stable identifier of the UIKit `UITab` that hosts this page.
    var tabIdentifier: String { "page." + String(rawValue) }

    init?(name: String) {
        guard let page = ShellPage.allCases.first(where: { $0.name == name }) else { return nil }
        self = page
    }

    init(clamping tag: Int) {
        self = ShellPage(rawValue: min(max(tag, 0), 2)) ?? .home
    }
}
