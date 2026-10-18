import Foundation

/// Every `window.webkit.messageHandlers.*` channel the bundled HTML may call.
/// Registering and removing handlers is driven by this list, so a channel can
/// never be added on one side only.
enum BridgeMessage: String, CaseIterable {
    case nativeHomeState
    case shareZip
    case infoPage
    case materialMode
    case cardGlassRects
    case themeBackground
    case cardColor
    case buttonColor
    case nativeToggleRects
    case appearanceMode
    case themeFont
    case zipName
    case backgroundImage
    case minimizeBottomBar
    case pageState
    case settingsHeroFrame
    case bottomSearch
    case activationOpen
    case activationSubmit
    case luiyoBlocked
    case blockedPopup

    var name: String { rawValue }
}
