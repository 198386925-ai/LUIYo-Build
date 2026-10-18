import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

/// The app shell: one WKWebView shared by three tabs, a native SwiftUI
/// homepage, the floating bottom search and the material layer behind the HTML.
///
/// This type owns composition and state only; behaviour is split across
/// extensions, one file each:
///  - `ShellTabs`            — tab construction and page selection
///  - `ShellWebPlacement`    — where the shared web view lives
///  - `ShellAppearance`      — appearance, palette, fonts, material mode
///  - `ShellCommands`        — requests sent to the web engine
///  - `ShellBridgeHandling`  — messages arriving from the web engine
///  - `ShellWebDelegates`    — navigation/UI delegates and tab bar delegate
///  - `ShellSnapshot`        — CI snapshot scenarios
///
/// Members are `internal` because those extensions live in separate files.
final class MainShellViewController: UITabBarController {
    // MARK: - Authorization

    var onActivationRequested: (() -> Void)?
    var onLicenseSubmitted: ((String) -> Void)?
    var onPageChanged: ((String) -> Void)?
    var isAuthorized = false
    var authorizationMessage = "未激活 · 仅可浏览"
    var authorizationBusy = false

    // MARK: - Collaborators

    let preferences = ThemePreferences.shared
    let homeModel = NativeHomeModel()
    let fontController = ThemeFontController()
    var webHost: WebContentHost!
    var materialLayer: CardMaterialLayer!
    var imagePicker: ImagePickerCoordinator!
    var zipExport: ZipExportCoordinator!

    // MARK: - Tabs

    var pageTabs: [UITabBarItem] = []
    var pageControllers: [UIViewController] = []
    let searchTabController = UIViewController()
    var retainedTabs: [String: AnyObject] = [:]
    var bottomSearchEnabled = false
    var separateSearch = false
    var activePage: ShellPage = .home

    // MARK: - Web placement

    var webView: WKWebView!
    var webHostConstraints: [NSLayoutConstraint] = []
    var boundScrollViews: [ObjectIdentifier: UIScrollView] = [:]
    var nativeHomeHost: UIHostingController<LUIYoNativeHome>?
    var nativeHomeConstraints: [NSLayoutConstraint] = []
    weak var nativeHomeScrollView: UIScrollView?
    var nativeHomeReady = false
    var switchingPage = false
    var suppressWebViewReveal = false
    var pageSwitchGeneration = 0
    var reportedTabTop: CGFloat = -1
    private var scrollOffsetObservation: NSKeyValueObservation?
    #if DEBUG
    private var nativeHomeScrollObservation: NSKeyValueObservation?
    #endif

    // MARK: - Search

    weak var activeSearchController: SearchOverlayViewController?
    var activeSearchPage = "home"
    var openingSearch = false

    // MARK: - Chrome

    let backgroundImageView = UIImageView()
    var settingsHero: UIView?
    var scrollMinimizeEnabled = false
    var restoredNativeFont = false
    let originalTabLabelFonts = NSMapTable<UILabel, UIFont>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    var defaultTabAppearance: UITabBarAppearance?
    var defaultScrollEdgeAppearance: UITabBarAppearance?

    /// The imported theme font — the blocked popup uses it to match the app.
    var currentThemeFont: UIFont? { fontController.font }

    // MARK: - Lifecycle

    override func loadView() {
        super.loadView()
        let rootView = view!
        // Shared native background on every page.
        rootView.backgroundColor = ThemePalette.adaptiveBackground
        installBackground(in: rootView)
        installWebContent(in: rootView)
        configureTabs()
    }

    override func viewDidLoad() {
        // Clear cache to force fresh HTML.
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                modifiedSince: Date(timeIntervalSince1970: 0)) { }
        super.viewDidLoad()
        preferences.registerDefaults()
        setScrollMinimize(preferences.minimizeBottomBar)
        separateSearch = preferences.isSeparateSearch
        setBottomSearchEnabled(preferences.bottomSearchEnabled)
        applyAppearance(preferences.appearanceMode)
        guard webHost.loadBundledPage() else {
            showLoadFailure()
            return
        }
    }

    deinit {
        scrollOffsetObservation?.invalidate()
        webHost.invalidate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Remove extra layer shadows without replacing native system glass.
        removeExtraLayerShadows(tabBar.layer)
        updateTabLabelFonts(in: tabBar)
        keepContentBelowNativeBar()
        updateLayoutMetrics()
        materialLayer.render()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded,
              previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyStoredPalette()
        setNeedsStatusBarAppearanceUpdate()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }

    // MARK: - Composition

    private func installBackground(in rootView: UIView) {
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backgroundImageView.isUserInteractionEnabled = false
        backgroundImageView.accessibilityElementsHidden = true
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        rootView.insertSubview(backgroundImageView, at: 0)
        NSLayoutConstraint.activate([
            backgroundImageView.topAnchor.constraint(equalTo: rootView.topAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor)
        ])
        // Custom background image feature removed — clear any previously stored image.
        backgroundImageView.image = nil
        try? FileManager.default.removeItem(at: AppPaths.legacyBackgroundImage)
        homeModel.backgroundImage = nil
    }

    private func installWebContent(in rootView: UIView) {
        webHost = WebContentHost(messageHandler: self)
        let webView = webHost.webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView

        materialLayer = CardMaterialLayer(scrollView: webView.scrollView)
        materialLayer.onToggleChanged = { [weak self] id, enabled in
            self?.evaluate(arguments: [id, enabled], function: "setBrandSwitch")
        }
        imagePicker = ImagePickerCoordinator(presenter: self)
        imagePicker.onFiles = { [weak self] files, kind, index in self?.receiveFiles(files, kind: kind, index: index) }
        imagePicker.onAvatar = { [weak self] data in self?.saveHeroAvatar(data) }
        imagePicker.onFailure = { [weak self] text in self?.showNotice(text) }
        zipExport = ZipExportCoordinator(presenter: self)
        zipExport.onNameChosen = { [weak self] name in
            self?.evaluate(arguments: [name], function: "shareZipWithName")
        }

        homeModel.onCommand = { [weak self] action, values in
            guard let self else { return }
            if action == "category" || action == "search" { self.runNativeEngine(action, values) }
            else { self.handleHomeCommand(action, values) }
        }
        homeModel.onScrollView = { [weak self] scroll in
            guard let self else { return }
            self.nativeHomeScrollView = scroll
            scroll.accessibilityIdentifier = "nativeHomeScroll"
            scroll.keyboardDismissMode = .interactive
            self.keepContentBelowNativeBar()
            #if DEBUG
            self.nativeHomeScrollObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                self?.writeNativeHomeDiagnostics()
            }
            self.writeNativeHomeDiagnostics()
            #endif
        }
        fontController.onFontChanged = { [weak self] font in
            self?.applyFont(font)
            // Update web font scheme handler
            FontSchemeHandlerStore.shared.handler?.fontData = self?.fontController.savedFontData
            // Update native home font
            self?.homeModel.importedFont = font
        }

        // Put materials in the SAME scrolling coordinate space as WebKit content.
        // UIScrollView moves both together, including momentum and rubber-banding.
        // No per-frame JS/native offset reconciliation is needed.
        scrollOffsetObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            self?.materialLayer.render()
        }

        rootView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: rootView.topAnchor),
            webView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
    }

    private func configureTabs() {
        // Standard UIKit UITabBar: when built with the iOS 26 SDK and run on
        // iOS 26+, the system supplies Liquid Glass. Do not set a custom
        // background, blur, material or shadow here. Font changes preserve the
        // system appearance.
        delegate = self
        pageTabs = ShellPage.allCases.map { page in
            let item = UITabBarItem(title: page.title,
                                    image: UIImage(systemName: page.iconName),
                                    selectedImage: UIImage(systemName: page.selectedIconName))
            item.tag = page.rawValue
            return item
        }
        pageControllers = pageTabs.map { item in
            let controller = UIViewController()
            controller.tabBarItem = item
            controller.view.backgroundColor = .clear
            return controller
        }
        searchTabController.tabBarItem = UITabBarItem(title: "搜索",
                                                      image: UIImage(systemName: "magnifyingglass"),
                                                      tag: 3)
        searchTabController.view.backgroundColor = .clear
        defaultTabAppearance = tabBar.standardAppearance
        defaultScrollEdgeAppearance = tabBar.scrollEdgeAppearance?.copy() as? UITabBarAppearance
        restoredNativeFont = fontController.restore()
        // Update the web view font scheme handler
        FontSchemeHandlerStore.shared.handler?.fontData = fontController.savedFontData
        // Update native home font
        homeModel.importedFont = fontController.font
    }

    private func showLoadFailure() {
        let label = UILabel()
        label.text = "内置网页资源缺失"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.frame = view.bounds.insetBy(dx: 24, dy: 24)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(label)
    }

    // MARK: - Authorization

    func setAuthorization(_ allowed: Bool, message: String? = nil, busy: Bool = false) {
        homeModel.authorized = allowed
        isAuthorized = allowed
        authorizationMessage = message ?? (allowed ? "已授权" : "未激活 · 仅可浏览")
        authorizationBusy = busy
        syncAuthorization()
        if allowed, nativeHomeReady { runNativeEngine("colors", ["values": homeModel.savedColors]) }
    }

    func syncAuthorization() {
        guard isViewLoaded, webView != nil else { return }
        evaluate(arguments: [isAuthorized, authorizationMessage, authorizationBusy], function: "luiyoSetAuthorized")
    }
}
