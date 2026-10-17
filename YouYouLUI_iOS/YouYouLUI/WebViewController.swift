import UIKit
import WebKit
import CoreText
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Native material shell.
/// iOS 26+ uses UIKit Liquid Glass; older systems use UIKit systemMaterial blur.
/// HTML is content-only and never draws blur/glass itself.
final class WebViewController: UITabBarController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UITabBarControllerDelegate, UIDocumentPickerDelegate, PHPickerViewControllerDelegate {
    private var webView: WKWebView!
    private var nativeShrinkSwitch: UISwitch?
    private let nativeHomeModel = NativeHomeModel()
    private var nativeHomeHost: UIHostingController<LUIYoNativeHome>?
    private var nativeHomeConstraints: [NSLayoutConstraint] = []
    private weak var nativeHomeScrollView: UIScrollView?
    #if DEBUG
    private var nativeHomeScrollObservation: NSKeyValueObservation?
    #endif
    private var nativeHomeReady = false
    private var nativeUploadKind = "upload"
    private var nativeUploadIndex: Int?

    private var isAuthorized = false
    var onActivationRequested: (() -> Void)?
    var onLicenseSubmitted: ((String) -> Void)?
    var onPageChanged: ((String) -> Void)?
    private var authorizationMessage = "未激活 · 仅可浏览"
    private var authorizationBusy = false

    func setAuthorization(_ allowed: Bool, message: String? = nil, busy: Bool = false) {
        nativeHomeModel.authorized = allowed
        isAuthorized = allowed
        authorizationMessage = message ?? (allowed ? "已授权" : "未激活 · 仅可浏览")
        authorizationBusy = busy
        syncAuthorization()
        if allowed, nativeHomeReady { runNativeEngine("colors", ["values": nativeHomeModel.savedColors]) }
    }

    /// Show the blocked popup using the official HTML design (user's upload.html).
    /// Injected into the main WebView so it inherits the app's theme fonts automatically.
    func showBlockedPopup(title: String, desc: String, reasonLabel: String, reason: String) {
        guard let webView else { return }
        func esc(_ v: String) -> String {
            v.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
             .replacingOccurrences(of: "\"", with: "&quot;")
        }
        let t = esc(title), d = esc(desc), rl = esc(reasonLabel)
        // Explicit theme font so the popup always matches the app's custom font.
        let fontStyle: String = {
            if let name = themeFont?.fontName, !name.isEmpty {
                let safe = name.replacingOccurrences(of: "'", with: "")
                return "font-family:'" + safe + "',-apple-system,'PingFang SC',sans-serif;"
            }
            return ""
        }()
        let rv = esc(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\u{2014}" : reason)
        let h = """
        <div id="luiyo-blocked-overlay" style="position:fixed;inset:0;z-index:2147483647;display:flex;align-items:center;justify-content:center;padding:24px;background:rgba(0,0,0,.45);">
        <div id="luiyo-blocked-card" style="width:320px;max-width:100%;background:#fff;border-radius:24px;padding:20px 20px 18px;box-shadow:0 12px 40px rgba(0,0,0,.18);text-align:center;\(fontStyle)">
        <div style="width:60px;height:60px;margin:0 auto 10px;border-radius:18px;background:#FFF0E6;display:flex;align-items:center;justify-content:center;">
        <svg viewBox="0 0 24 24" width="32" height="32" xmlns="http://www.w3.org/2000/svg"><path d="M12 2 4 5v6c0 5 3.4 8.5 8 11 4.6-2.5 8-6 8-11V5l-8-3z" fill="#FF7A00"/><path d="M9.5 12l1.8 1.8L15 10" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/></svg></div>
        <div style="font-size:19px;font-weight:700;color:#1A1A1A;margin-bottom:4px;">\(t)</div>
        <div style="font-size:14px;line-height:1.5;color:#999;margin-bottom:10px;">\(d)</div>
        <div style="text-align:left;background:#FAFAFA;border-radius:12px;padding:10px 12px;margin-bottom:12px;">
        <div style="font-size:12px;color:#BBB;margin-bottom:2px;">\(rl)</div>
        <div style="font-size:14px;color:#333;font-weight:500;">\(rv)</div></div>
        <button id="luiyo-blocked-confirm" style="width:100%;border:none;border-radius:14px;background:#FF7A00;color:#fff;font-size:16px;font-weight:600;padding:12px 0;">立即确认</button>
        </div></div>
        """
        guard let data = try? JSONSerialization.data(withJSONObject: [h]),
              var json = String(data: data, encoding: .utf8) else { return }
        // json is ["<html>"]; use index [0] in JS
        let js = "(function(){if(document.getElementById('luiyo-blocked-overlay'))return;var html=" + json + "[0];var d=document.createElement('div');d.innerHTML=html;var ov=d.firstChild;document.body.appendChild(ov);var card=document.getElementById('luiyo-blocked-card');try{ov.animate([{opacity:0},{opacity:1}],{duration:220,easing:'ease-out'});if(card)card.animate([{transform:'translateY(90px) scale(.96)',opacity:0},{transform:'translateY(0) scale(1)',opacity:1}],{duration:420,easing:'cubic-bezier(.2,.85,.3,1.1)'});}catch(e){}var b=document.getElementById('luiyo-blocked-confirm');if(b)b.addEventListener('click',function(){try{window.webkit.messageHandlers.luiyoBlocked.postMessage('confirm');}catch(e){}});})();"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func syncAuthorization() {
        guard isViewLoaded, let webView else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: [isAuthorized, authorizationMessage, authorizationBusy]),
              let args = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__luiyoSetAuthorized?.(..." + args + ")")
    }
    private var pageItems: [UITabBarItem] = []
    private var pageControllers: [UIViewController] = []
    private let searchController = UIViewController()
    private var bottomSearchEnabled = false
    private var activePageTag = 0
    private var separateSearch = false
    private weak var activeSearchPageController: LUIYoSearchViewController?
    private var webHostConstraints: [NSLayoutConstraint] = []
    private var boundScrollViews: [ObjectIdentifier: UIScrollView] = [:]
    private let backgroundImageView = UIImageView()
    private var scrollMinimizeEnabled = false
    private var nativePageName = "home"
    private var openingSearch = false
    private var activeSearchPage = "home"
    private var themeFont: UIFont?
    private var themeFontData: Data?
    /// The app's custom theme font, if the user has set one. Used by the blocked popup.
    var currentThemeFont: UIFont? { themeFont }
    private let originalTabLabelFonts = NSMapTable<UILabel, UIFont>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private var registeredThemeGraphicsFont: CGFont?
    private var restoredNativeFont = false
    private var defaultTabAppearance: UITabBarAppearance?
    private var defaultScrollEdgeAppearance: UITabBarAppearance?
    private var reportedTabTop: CGFloat = -1
    private let glassContainer = UIView()
    private var cardMaterialViews: [String: UIVisualEffectView] = [:]
    private var cardMaterialHosts: [String: UIView] = [:]
    private var cardDocumentFrames: [String: CGRect] = [:]
    private var cardSpecs: [String: [String: Any]] = [:]
    private var cardOrder: [String] = []
    private var nativeSegments: [String: UISegmentedControl] = [:]
    private var nativeSelectedPills: [String: UIView] = [:]
    private var settingsHero: UIView?
    private var nativeThemeSwitches: [String: UIControl] = [:]
    private var switchingNativePage = false
    private var suppressWebViewReveal = false
    private var pageSwitchGeneration = 0
    private var didPreRenderRules = false
    private var nativeLicenseButtons: [String: UIButton] = [:]
    private var retainedTabs: [String: AnyObject] = [:]
    private var nativeSymbols: [String: UIImageView] = [:]
    private var nativeSegmentStyles: [String: UIUserInterfaceStyle] = [:]
    private var scrollOffsetObservation: NSKeyValueObservation?
    private enum CardMaterialMode { case liquid, blur }
    private var cardMaterialMode: CardMaterialMode = .liquid
    private var cardTintColor: UIColor = .secondarySystemGroupedBackground
    static let adaptiveBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 18.0/255.0, green: 18.0/255.0, blue: 20.0/255.0, alpha: 1)
            : UIColor(red: 242.0/255.0, green: 242.0/255.0, blue: 247.0/255.0, alpha: 1)
    }

    private static let activationPreviewScript = #"""
    (() => {
      let authorized = false;
      const css = document.createElement('style');
      css.textContent = `.luiyoActivationEntry{margin:0 0 8px;padding:17px 18px;border:0;border-radius:28px;background:var(--card-color,#fff)}
        body.native-card-glass .luiyoActivationEntry{background:transparent!important;box-shadow:none!important}
        .luiyoActivationEntry strong{display:block;font-size:15px}.luiyoActivationEntry small{display:block;margin-top:5px;color:var(--muted,#8b8f98);font-size:12px}
        .luiyoActivationForm{display:flex;gap:8px;margin:8px 12px 12px!important;align-items:center}.luiyoActivationForm[hidden]{display:none!important}
        #luiyoLicenseCode{flex:1;min-width:0;height:44px;box-sizing:border-box;padding:0 12px;border:0;border-radius:22px;background:transparent;color:inherit;font-size:14px}
        #luiyoLicenseSubmit{height:44px;border:0;border-radius:22px;padding:0 14px;background:#6968e8;color:white;font-weight:600;white-space:nowrap}
        body.native-card-glass #luiyoLicenseSubmit{background:transparent!important;color:transparent!important}
        body.native-card-glass #luiyoLicenseCode{background:transparent!important;border:0!important}`;
      document.head.appendChild(css);
      const settings = document.getElementById('settingsTarget');
      if (settings) {
        const box = document.createElement('section');
        box.className = 'luiyoActivationEntry';box.id='luiyoActivationCard';
        box.innerHTML = '<div class="settingsAuthHeading"><span class="settingsFoldIcon" data-system-icon="checkmark.shield">✓</span><span class="settingsFoldText"><b>激活授权</b><small id="luiyoAuthState">未激活 · 仅可浏览</small></span></div><form class="luiyoActivationForm" id="luiyoActivationForm"><input id="luiyoLicenseCode" aria-label="卡密" placeholder="输入卡密" autocomplete="one-time-code" autocapitalize="characters" spellcheck="false"><button id="luiyoLicenseSubmit" type="submit">激活</button></form>';
        settings.querySelector('.settingsHead')?.insertAdjacentElement('afterend', box);
        const hero=document.createElement('div');hero.id='luiyoSettingsHero';hero.style.cssText='height:116px;margin-bottom:8px';
        box.insertAdjacentElement('beforebegin',hero);
        let queued=false,last='';
        const syncHero=()=>{if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;const r=hero.getBoundingClientRect();const payload={visible:!!hero.getClientRects().length,x:r.left+scrollX,y:r.top+scrollY,width:r.width,height:r.height};const signature=JSON.stringify(payload);if(signature!==last){last=signature;window.webkit?.messageHandlers?.settingsHeroFrame?.postMessage(payload)}})};
        if(window.ResizeObserver)new ResizeObserver(syncHero).observe(settings);
        new MutationObserver(syncHero).observe(document.body,{subtree:true,attributes:true,childList:true,characterData:true});
        window.addEventListener('resize',syncHero);syncHero();
        box.querySelector('form').addEventListener('submit', e => {
          e.preventDefault();const code=box.querySelector('input').value.trim();
          if(code)window.webkit?.messageHandlers?.activationSubmit?.postMessage({code});
        });
      }
      window.__luiyoSetAuthorized = (enabled,message,busy=false) => {
        authorized = !!enabled;
        document.documentElement.dataset.luiyoAuthorized = authorized ? 'yes' : 'no';
        const state=document.getElementById('luiyoAuthState'), form=document.getElementById('luiyoActivationForm');
        if(state)state.textContent=message||(authorized?'已授权':'未激活 · 仅可浏览');
        if(form){form.hidden=authorized;const field=form.querySelector('input'),button=form.querySelector('button');field.disabled=busy;button.disabled=busy;button.textContent=busy?'验证中…':'激活';if(authorized){field.blur();field.value=''}}
        window.__syncNativeCardGlass?.();
      };
      function showLicenseNotice() {
        let el=document.getElementById('luiyoLicenseNotice');
        if(!el) {
          el=document.createElement('div');
          el.id='luiyoLicenseNotice';
          el.setAttribute('role','status');
          el.style.cssText='position:fixed;z-index:2147483647;left:50%;bottom:calc(env(safe-area-inset-bottom,0px) + 94px);transform:translateX(-50%);max-width:calc(100vw - 36px);box-sizing:border-box;padding:13px 20px;border-radius:16px;color:#fff;background:rgba(35,36,44,.92);font-size:14px;font-weight:600;text-align:center;box-shadow:0 5px 24px rgba(0,0,0,.18);pointer-events:none';
          document.body.appendChild(el);
        }
        el.textContent='未授权用户，请授权后使用';
        el.hidden=false;
        clearTimeout(window.__luiyoNoticeTimeout);
        window.__luiyoNoticeTimeout=setTimeout(()=>{el.hidden=true},2300);
      }
      function protect(e) {
        if(authorized) return;
        const t=e.target;
        if(!(t instanceof Element) || !t.closest('#homeTools'))return;
        if(!t.closest('button,input,textarea,select,label,a,[contenteditable],[role="button"]'))return;
        e.preventDefault();e.stopImmediatePropagation();
        if(e.type==='click')showLicenseNotice();
      }
      ['click','change','input','submit','keydown','drop','paste'].forEach(t=>document.addEventListener(t,protect,true));
      window.__luiyoSetAuthorized(false);
    })();
    """#

    override func loadView() {
        super.loadView()
        let rootView = view!
        // Shared native background on every page.
        rootView.backgroundColor = Self.adaptiveBackground

        // Native host for per-card materials. HTML supplies content only.
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
        try? FileManager.default.removeItem(at: nativeBackgroundURL)
        nativeHomeModel.backgroundImage = nil
        glassContainer.backgroundColor = .clear
        glassContainer.isUserInteractionEnabled = false
        glassContainer.accessibilityElementsHidden = true

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(source: "if(localStorage.getItem('youyou.theme.bottomSearchMode')===null && localStorage.getItem('youyou.theme.bottomSearchEnabled')===null){localStorage.setItem('youyou.theme.bottomSearchMode','separate')}", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(self, name: "nativeHomeState")
        configuration.userContentController.add(self, name: "shareZip")
        configuration.userContentController.add(self, name: "infoPage")
        configuration.userContentController.add(self, name: "materialMode")
        configuration.userContentController.add(self, name: "cardGlassRects")
        configuration.userContentController.add(self, name: "themeBackground")
        configuration.userContentController.add(self, name: "cardColor")
        configuration.userContentController.add(self, name: "nativeToggleRects")
        configuration.userContentController.add(self, name: "buttonColor")
        configuration.userContentController.add(self, name: "appearanceMode")
        configuration.userContentController.add(self, name: "themeFont")
        configuration.userContentController.add(self, name: "zipName")
        configuration.userContentController.add(self, name: "backgroundImage")
        configuration.userContentController.add(self, name: "minimizeBottomBar")
        configuration.userContentController.add(self, name: "shrinkSwitchPosition")
        configuration.userContentController.add(self, name: "pageState")
        configuration.userContentController.add(self, name: "settingsHeroFrame")
        configuration.userContentController.add(self, name: "bottomSearch")
        configuration.userContentController.add(self, name: "activationOpen")
        configuration.userContentController.add(self, name: "activationSubmit")
        configuration.userContentController.add(self, name: "luiyoBlocked")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.activationPreviewScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        if let url = Bundle.main.url(forResource: "native-home-bridge", withExtension: "js", subdirectory: "Web"),
           let script = try? String(contentsOf: url, encoding: .utf8) {
            configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        nativeHomeModel.onCommand = { [weak self] action, values in
            if ["category", "search"].contains(action) { self?.runNativeEngine(action, values) }
            else { self?.nativeHomeCommand(action, values) }
        }
        nativeHomeModel.onScrollView = { [weak self] scroll in
            guard let self else { return }
            self.nativeHomeScrollView = scroll
            scroll.accessibilityIdentifier = "nativeHomeScroll"
            scroll.keyboardDismissMode = .interactive
            self.keepContentBelowNativeBar()
            #if DEBUG
            self.nativeHomeScrollObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in self?.writeNativeHomeDiagnostics() }
            self.writeNativeHomeDiagnostics()
            #endif
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.translatesAutoresizingMaskIntoConstraints = false
        self.webView = webView
        // Put materials in the SAME scrolling coordinate space as WebKit content.
        // UIScrollView moves both together, including momentum and rubber-banding.
        // No per-frame JS/native offset reconciliation is needed.
        webView.scrollView.insertSubview(glassContainer, at: 0)
        scrollOffsetObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            self?.renderVisibleNativeMaterials()
        }

        // Standard UIKit UITabBar: when built with the iOS 26 SDK and run on
        // iOS 26+, the system supplies Liquid Glass. Do not set a custom
        // background, blur, material or shadow here. Font changes preserve the system appearance.
        delegate = self
        let home = UITabBarItem(title: "首页", image: UIImage(systemName: "house"), selectedImage: UIImage(systemName: "house.fill"))
        home.tag = 0
        let rules = UITabBarItem(title: "规则", image: UIImage(systemName: "list.bullet.rectangle"), selectedImage: UIImage(systemName: "list.bullet.rectangle.fill"))
        rules.tag = 1
        let settings = UITabBarItem(title: "设置", image: UIImage(systemName: "gearshape"), selectedImage: UIImage(systemName: "gearshape.fill"))
        settings.tag = 2
        pageItems = [home, rules, settings]
        pageControllers = pageItems.map { item in
            let controller = UIViewController()
            controller.tabBarItem = item
            controller.view.backgroundColor = .clear
            return controller
        }
        searchController.tabBarItem = UITabBarItem(title: "搜索", image: UIImage(systemName: "magnifyingglass"), tag: 3)
        searchController.view.backgroundColor = .clear
        defaultTabAppearance = tabBar.standardAppearance.copy() as? UITabBarAppearance
        defaultScrollEdgeAppearance = tabBar.scrollEdgeAppearance?.copy() as? UITabBarAppearance
        if let data = try? Data(contentsOf: nativeFontURL), setNativeFont(data) {
            restoredNativeFont = true
        }

        rootView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: rootView.topAnchor),
            webView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        // Avoid mutating UITabBarController.tabs during loadView: on iOS 26,
        // changing the tab hierarchy while UIKit is creating its view can
        // re-enter controller initialization before the root hierarchy exists.
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        UserDefaults.standard.register(defaults: ["youyou.bottomSearchEnabled": true, "youyou.bottomSearchLayout": "separate"])
        setScrollMinimize(UserDefaults.standard.bool(forKey: "youyou.minimizeBottomBar"))
        separateSearch = UserDefaults.standard.string(forKey: "youyou.bottomSearchLayout") == "separate"
        setBottomSearchEnabled(UserDefaults.standard.bool(forKey: "youyou.bottomSearchEnabled"))
        applyAppearance(UserDefaults.standard.string(forKey: "youyou.appearanceMode") ?? "system")
        guard let webRoot = Bundle.main.url(forResource: "Web", withExtension: nil),
              let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") else {
            showError("内置网页资源缺失")
            return
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: webRoot)
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "nativeHomeState")
        scrollOffsetObservation?.invalidate()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "shareZip")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "infoPage")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "materialMode")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "cardGlassRects")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "themeBackground")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "cardColor")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "nativeToggleRects")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "buttonColor")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "appearanceMode")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "themeFont")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "zipName")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "backgroundImage")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "minimizeBottomBar")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "shrinkSwitchPosition")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "pageState")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "settingsHeroFrame")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "bottomSearch")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "activationOpen")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "activationSubmit")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        nativeHomeReady = true
        syncAuthorization()
        if isAuthorized { runNativeEngine("colors", ["values": nativeHomeModel.savedColors]) }
        runNativeEngine("state", [:])
        navigateFromNativeTab(activePageTag)
        keepContentBelowNativeBar()
        updateLayoutMetrics(force: true)
        // Pre-render rules page at launch so first tab switch doesn't flash
        // Pre-render removed entirely: caused race conditions where WebView
        // got stuck showing wrong page when user tapped tab during pre-render.
        // CI exercises the same taps, native traits and saved appearance as users.
        guard let rawScenario = ProcessInfo.processInfo.environment["LUI_SNAPSHOT"] else { return }
        if rawScenario.hasPrefix("preview-") {
            let page = rawScenario.contains("rules") ? "rules" : (rawScenario.contains("settings") ? "settings" : "home")
            let tag = page == "rules" ? 1 : (page == "settings" ? 2 : 0)
            webView.evaluateJavaScript("document.querySelector('[data-appearance-mode=light]').click();window.__setBottomSearchMode('separate');appNavTo('\(page)');window.__applyBottomSearch('','\(page)')")
            selectNativePage(tag)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                if rawScenario.contains("search") { self.presentBottomSearch() }
                var previewNeedsFillImage = rawScenario == "preview-inline-auth"
                #if DEBUG
                previewNeedsFillImage = previewNeedsFillImage || rawScenario == "preview-native-theme"
                #endif
                if previewNeedsFillImage {
                    self.webView.evaluateJavaScript("fillFile=new File([Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAFklEQVR4nGNUqPj1nwEPYMInOXwUAACm9AKhD318TgAAAABJRU5ErkJggg=='),c=>c.charCodeAt(0))],'test.png',{type:'image/png'})")
                }
                #if DEBUG
                if rawScenario == "preview-native-theme" {
                    self.nativeHomeModel.fontName = "Courier"
                    self.nativeHomeModel.importedFont = UIFont(name: "Courier", size: 10)
                    self.webView.evaluateJavaScript("for(const [id,value] of Object.entries({appBackgroundColor:'#dce7f2',appCardColor:'#f3e8dc',appButtonColor:'#385170'})){const input=document.getElementById(id);input.value=value;input.dispatchEvent(new Event('input',{bubbles:true}))}document.querySelector('[data-material=blur]').click();window.__applyToolbarTransparency(35);window.__setBottomSearchMode('off');window.__setMinimizeBottomBar(true);")
                }
                #endif
                if rawScenario.contains("zip-name") { self.webView.evaluateJavaScript("const zip=new JSZip();zip.file('check.txt','ok');zip.generateAsync({type:'blob'}).then(blob=>{preparedZipBlob=blob;openShareModal()})") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    let marker = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("preview-ready.txt")
                    try? Data("ready".utf8).write(to: marker)
                }
            }
            return
        }
        var scenario = rawScenario.hasPrefix("dark-") ? String(rawScenario.dropFirst(5)) : rawScenario
        let appearance = scenario.contains("forced-dark-") ? "dark" : (scenario.contains("forced-light-") ? "light" : "system")
        scenario = scenario.replacingOccurrences(of: "forced-dark-", with: "").replacingOccurrences(of: "forced-light-", with: "")
        let mode = scenario.contains("blur") ? "blur" : "liquid"
        let page = scenario.contains("settings") ? "settings" : (scenario.contains("rules") ? "rules" : "home")
        let log = scenario.contains("log")
        let folded = scenario.contains("folded")
        let foldSelector = log ? ".changelogInline" : ".themeBody"
        var fontTestJS = ""
        if rawScenario.contains("font-") && !rawScenario.contains("restored") && !rawScenario.contains("reset"),
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = try? Data(contentsOf: documents.appendingPathComponent("ThemeFontTest.ttf")) {
            fontTestJS = "setTimeout(()=>window.__importThemeFontForTest(Uint8Array.from(atob('\(data.base64EncodedString())'),c=>c.charCodeAt(0)).buffer,'Arial.ttf'),300);"
        } else if rawScenario.contains("font-reset") {
            fontTestJS = "setTimeout(()=>document.getElementById('resetCustomFont').click(),300);"
        }
        let js = """
        \(fontTestJS)
        document.querySelector('[data-appearance-mode="\(appearance)"]').click();
        document.querySelector('[data-material="\(mode)"]').click();
        appNavTo('\(page)');
        if (!\(rawScenario.contains("restored"))) window.__setBottomSearchMode('off');
        if ('\(page)' === 'settings') {
            document.querySelector('\(foldSelector)').closest('details').querySelector('summary').click();
        }
        if (\(folded)) setTimeout(function(){document.querySelector('.themeFold summary').click();},500);
        if (\(rawScenario.contains("custom"))) {
            const bg=document.getElementById('appBackgroundColor');bg.value='#325A70';bg.dispatchEvent(new Event('input'));
            const card=document.getElementById('appCardColor');card.value=\(rawScenario.hasPrefix("dark-") ? "'#503B48'" : "'#F2C9B0'");card.dispatchEvent(new Event('input'));
            const color=document.getElementById('appButtonColor');color.value=\(rawScenario.hasPrefix("dark-") ? "'#446078'" : "'#C58C48'");color.dispatchEvent(new Event('input'));
            if ('\(page)' === 'home') document.getElementById('tabWechat').click();
        }
        if (\(rawScenario.contains("buttons-reset"))) {
            const color=document.getElementById('appButtonColor');color.value='#446078';color.dispatchEvent(new Event('input'));
            document.getElementById('resetButtonColor').click();
        }
        if (\(rawScenario.contains("bottom-"))) {
            setTimeout(()=>{
                const setSearch=window.__setBottomSearchMode;
                if (!\(rawScenario.contains("restored"))) {
                    setSearch('\(rawScenario.contains("separate") ? "separate" : "merged")');
                }
                window.__applyBottomSearch('\(page == "settings" ? "更新日志" : "底栏微信")');
                if (\(rawScenario.contains("bottom-off-"))) {
                    window.__applyBottomSearch('');setSearch('off');
                }
            },350);
        }
        setTimeout(function(){window.__syncNativeCardGlass();},800);
        if (\(rawScenario.contains("bottom-dialog"))) setTimeout(()=>window.__openBottomSearch(),1400);
        """
        webView.evaluateJavaScript(js)
        selectNativePage(page == "settings" ? 2 : (page == "rules" ? 1 : 0))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            let dark = self.traitCollection.userInterfaceStyle == .dark
            let expectedDark = appearance == "dark" || (appearance == "system" && rawScenario.hasPrefix("dark-"))
            let hasPicker = self.cardSpecs["id:materialModePicker"] != nil
            let styleJS = """
            (()=>{
              const rect=id=>document.getElementById(id).getBoundingClientRect();
              const credits=document.getElementById('settingsCredits'), c=rect('settingsCredits');
              const folds=[...document.querySelectorAll('.settingsFold:not([hidden])')];
              const last=folds.at(-1).getBoundingClientRect();
              return {pageTitleSizes:[...document.querySelectorAll('.pageHead h1,.settingsHead h1')].map(el=>parseFloat(getComputedStyle(el).fontSize)),neutralToolBorders:[...document.querySelectorAll('#homeTools .fillpick,#homeTools .colorfold')].map(el=>parseFloat(getComputedStyle(el).borderTopWidth)),bottomSearchEnabled:document.body.classList.contains('bottom-search-enabled'),homeSearchHidden:getComputedStyle(document.getElementById('searchInput')).display==='none',ruleSearchHidden:getComputedStyle(document.getElementById('ruleSearch')).display==='none',searchState:window.__bottomSearchState(),resultCount:document.querySelectorAll(document.body.classList.contains('nav-rules')?'.ruleCard':'.card').length,settingsSearchCount:folds.filter(f=>!f.classList.contains('search-hidden')).length,documentHeight:document.documentElement.scrollHeight,viewportHeight:innerHeight,toolsFill:getComputedStyle(document.getElementById('homeTools')).backgroundColor,toolsShadow:getComputedStyle(document.getElementById('homeTools')).boxShadow,actionShadows:[...document.querySelectorAll('#homeTools .batch,#homeTools .fillpick,#homeTools .fill,#homeTools .colorfold,#homeTools .clear,#homeTools .zip')].map(el=>getComputedStyle(el).boxShadow),creditFontSize:parseFloat(getComputedStyle(credits).fontSize),actionHeights:[...document.querySelectorAll('#homeTools .batch,#homeTools .fillpick,#homeTools .fill,#homeTools .colorfold,#homeTools .clear,#homeTools .zip')].map(el=>el.getBoundingClientRect().height),actions:[...document.querySelectorAll('#homeTools .batch,#homeTools .fillpick,#homeTools .fill,#homeTools .colorfold,#homeTools .clear,#homeTools .zip')].map(el=>getComputedStyle(el).color),category:[...document.querySelectorAll('.categorytabs button')].map(el=>getComputedStyle(el).color),dark:document.documentElement.dataset.appearance==='dark',mode:localStorage.getItem('youyou.theme.appearance'),categoryHeight:document.querySelector('.categorytabs').getBoundingClientRect().height,materialHeight:rect('materialModePicker').height,appearanceHeight:rect('appearanceModePicker').height,creditVisible:c.width>0&&c.height>0,creditTop:c.top,creditBottom:c.bottom,logBottom:last.bottom,cardHeights:folds.filter(d=>!d.open).map(d=>d.getBoundingClientRect().height),cardBorders:folds.map(d=>getComputedStyle(d).borderTopWidth),surfaceBackgrounds:[...document.querySelectorAll(".inlineVersion,.card,.ruleCard,.settingsFold,.categorytabs,#materialModePicker,#appearanceModePicker")].map(el=>getComputedStyle(el).backgroundColor),searchBelowFeedback:(()=>{const q=rect('searchInput'),f=document.querySelector('.homeFeedback').getBoundingClientRect(),t=rect('homeTools');return q.top>=f.bottom&&q.bottom<t.top&&document.getElementById('searchInput').parentElement.id==='homeTarget'})(),actionFills:[...document.querySelectorAll('#homeTools .batch,#homeTools .fillpick,#homeTools .fill,#homeTools .colorfold,#homeTools .clear,#homeTools .zip')].map(el=>getComputedStyle(el).backgroundColor),motion:window.__foldMotionChecks||[]};
            })()
            """
            self.webView.evaluateJavaScript(styleJS) { value, _ in
                let styles = value as? [String: Any] ?? [:]
                let actionColors = styles["actions"] as? [String] ?? []
                let categoryColors = styles["category"] as? [String] ?? []
                let home = page == "home"
                let expectedText = rawScenario.contains("custom") && dark ? "rgb(242, 242, 247)" : "rgb(32, 40, 50)"
                let defaultText = ["rgb(242, 242, 247)", "rgb(32, 40, 50)", "rgb(32, 40, 50)", "rgb(32, 40, 50)", "rgb(255, 255, 255)", "rgb(255, 255, 255)"]
                let expectedTexts = rawScenario.contains("custom") ? [expectedText, expectedText, expectedText, expectedText, "rgb(255, 255, 255)", "rgb(255, 255, 255)"] : defaultText
                let readable = !home || actionColors == expectedTexts
                let nativeTitlesOnly = !home || (categoryColors.count == 2 && categoryColors.allSatisfy { $0 == "rgba(0, 0, 0, 0)" })
                let compactCategory = home ? abs((styles["categoryHeight"] as? Double ?? 0) - 32) < 0.5
                    : (styles["categoryHeight"] as? Double ?? 999) < 0.5
                let compactMaterial = page != "settings" || folded || log || rawScenario.contains("bottom-") || (abs((styles["materialHeight"] as? Double ?? 0) - 32) < 0.5 && abs((styles["appearanceHeight"] as? Double ?? 0) - 32) < 0.5)
                let creditCorrect = (styles["creditVisible"] as? Bool) == (page == "settings")
                    && (!log || (styles["creditTop"] as? Double ?? 0) >= (styles["logBottom"] as? Double ?? 0))
                let checks = styles["motion"] as? [[String: Any]] ?? []
                let surfaceColors = styles["surfaceBackgrounds"] as? [String] ?? []
                let nativeSurfacesVisible = !surfaceColors.isEmpty && surfaceColors.allSatisfy { $0 == "rgba(0, 0, 0, 0)" }
                let fills = styles["actionFills"] as? [String] ?? []
                let expectedFill = rawScenario.contains("custom") ? (dark ? "rgb(68, 96, 120)" : "rgb(197, 140, 72)")
                    : "rgb(255, 255, 255)"
                let expectedFills = rawScenario.contains("custom") ? Array(repeating: expectedFill, count: 4) + ["rgb(0, 122, 254)", "rgb(70, 216, 106)"]
                    : ["rgb(0, 122, 254)", "rgb(255, 255, 255)", "rgb(70, 216, 106)", "rgb(255, 255, 255)", "rgb(0, 122, 254)", "rgb(70, 216, 106)"]
                // Four accent controls retain their configured solid fills.
                // The two neutral controls intentionally add a subtle tint.
                let neutralBorders = styles["neutralToolBorders"] as? [Double] ?? []
                let solidActions = fills.count == 6 && [0, 2, 4, 5].allSatisfy { fills[$0] == expectedFills[$0] }
                    && [1, 3].allSatisfy { fills[$0] != "rgba(0, 0, 0, 0)" }
                    && neutralBorders.count == 2 && neutralBorders.allSatisfy { $0 >= 1 }
                let searchSurface = self.cardMaterialViews["id:searchInput"]
                let searchPresent = self.cardSpecs["id:searchInput"] != nil
                var searchLiquid = false
                if #available(iOS 26.0, *) { searchLiquid = searchSurface?.effect is UIGlassEffect }
                let searchBlur = searchSurface?.effect is UIBlurEffect
                let noNativeActions = !self.cardSpecs.values.contains { ($0["homeControl"] as? Bool) == true }
                let bottomEnabled = rawScenario.contains("bottom-") && !rawScenario.contains("bottom-off-")
                let searchCorrect = !home || (bottomEnabled ? (!searchPresent && (styles["homeSearchHidden"] as? Bool) == true) : (searchPresent && (mode == "blur" ? searchBlur : searchLiquid) && (styles["searchBelowFeedback"] as? Bool) == true))
                let toolsExpected = rawScenario.contains("custom") ? (dark ? "rgb(80, 59, 72)" : "rgb(242, 201, 176)") : (dark ? "rgb(28, 28, 30)" : "rgb(255, 255, 255)")
                let solidToolCard = self.cardSpecs["id:homeTools"] == nil && (styles["toolsFill"] as? String) == toolsExpected && (styles["toolsShadow"] as? String) == "none"
                let bottomCorrect = self.bottomSearchEnabled == bottomEnabled && (self.tabBar.items?.count ?? 0) == (bottomEnabled ? 4 : 3) && (styles["bottomSearchEnabled"] as? Bool) == bottomEnabled
                let searchDialogCorrect = !rawScenario.contains("bottom-dialog") || (self.activeSearchPageController?.presentingViewController != nil && self.tabBar.selectedItem?.tag == 0)
                let titleSizes = styles["pageTitleSizes"] as? [Double] ?? []
                let titlesMatch = titleSizes.count == 2 && titleSizes.allSatisfy { abs($0 - 25) < 0.1 }
                let categorySegment = self.nativeSegments.first { self.cardSpecs[$0.key]?["segment"] as? String == "category" }?.value
                let track = categorySegment?.superview?.backgroundColor?.resolvedColor(with: self.traitCollection).cgColor.components ?? []
                let smooth = checks.allSatisfy { ($0["jump"] as? Double ?? 999) < 0.5 && ($0["monotonic"] as? Bool) == true }
                let bg = self.view.backgroundColor?.resolvedColor(with: self.traitCollection).cgColor.components ?? []
                var result = styles
                result["scenario"] = rawScenario
                result["settingsScrollIndicator"] = self.webView.scrollView.showsVerticalScrollIndicator
                result["pageTitlesMatch"] = titlesMatch
                result["webContentInSelectedPage"] = self.webView.superview === self.selectedViewController?.view
                result["passed"] = (!folded || !hasPicker) && titlesMatch && readable && nativeTitlesOnly && compactCategory && compactMaterial && creditCorrect && smooth && nativeSurfacesVisible && solidActions && solidToolCard && bottomCorrect && searchDialogCorrect && noNativeActions && searchCorrect && dark == expectedDark && (styles["dark"] as? Bool) == dark
                result["selectedCapsuleAlphas"] = self.nativeSelectedPills.values.map { Double($0.backgroundColor?.cgColor.alpha ?? 1) }
                result["pickerStyles"] = self.nativeSegments.map { key, segment -> [String: Any] in
                    let attributes = segment.titleTextAttributes(for: .selected) ?? [:]
                    let text = attributes[.foregroundColor] as? UIColor
                    return ["kind": self.cardSpecs[key]?["segment"] as? String ?? "", "selected": segment.selectedSegmentIndex,
                        "track": segment.superview?.backgroundColor?.cgColor.components?.map { Double($0) } ?? [],
                        "capsule": self.nativeSelectedPills[key]?.backgroundColor?.cgColor.components?.map { Double($0) } ?? [],
                        "selectedText": text?.resolvedColor(with: self.traitCollection).cgColor.components?.map { Double($0) } ?? []]
                }
                result["nativeFontRestoredOnLoad"] = self.restoredNativeFont
                result["nativeTabFonts"] = (self.tabBar.items ?? []).map { ($0.titleTextAttributes(for: .normal)?[.font] as? UIFont)?.fontName ?? "system" }
                result["nativeSelectedTabFonts"] = (self.tabBar.items ?? []).map { ($0.titleTextAttributes(for: .selected)?[.font] as? UIFont)?.fontName ?? "system" }
                result["appName"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
                result["appVersion"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                result["appBuild"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
                if #available(iOS 18.0, *) {
                    result["nativeSeparateSearch"] = self.tabs.contains { $0 is UISearchTab }
                }
                result["categoryTrack"] = track.map { Double($0) }
                result["nativeSearchEnabled"] = self.bottomSearchEnabled
                result["nativeSearchDialogVisible"] = self.activeSearchPageController?.presentingViewController != nil
                result["nativeSearchDialogQuery"] = self.activeSearchPageController?.searchField.text ?? ""
                result["nativeSelectedTab"] = self.tabBar.selectedItem?.tag ?? -1
                result["nativeToolsPresent"] = self.cardSpecs["id:homeTools"] != nil
                result["searchLiquid"] = searchLiquid
                result["searchBlur"] = searchBlur
                result["nativeCardColor"] = UserDefaults.standard.string(forKey: "youyou.cardColor." + (dark ? "dark" : "light")) ?? ""
                result["nativeButtonColor"] = UserDefaults.standard.string(forKey: "youyou.buttonColor." + (dark ? "dark" : "light")) ?? ""
                result["logNativeCards"] = self.cardSpecs.values.filter { ($0["key"] as? String)?.hasPrefix("node:") == true }.count
                result["nativeActionCount"] = self.cardSpecs.values.filter { ($0["homeControl"] as? Bool) == true }.count
                result["materialPickerPresent"] = hasPicker
                result["nativeDark"] = dark
                result["background"] = bg.map { Double($0) }
                result["nativeTabTop"] = Double(self.tabBar.frame.minY)
                result["nativeMode"] = UserDefaults.standard.string(forKey: "youyou.appearanceMode") ?? "system"
                if let data = try? JSONSerialization.data(withJSONObject: result),
                   let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? data.write(to: documents.appendingPathComponent("ui-layout-verification.json"), options: .atomic)
                }
            }
        }
    }

    private func setBottomSearchLayout(_ value: String) {
        let requestedSeparate = value == "separate"
        guard separateSearch != requestedSeparate else { return }
        separateSearch = requestedSeparate
        UserDefaults.standard.set(separateSearch ? "separate" : "merged", forKey: "youyou.bottomSearchLayout")
        refreshSearchTabItems()
    }

    private func refreshSearchTabItems() {
        if #available(iOS 18.0, *) {
            // UIKit owns the complete bar geometry, including the detached
            // search surface. Never shrink the bar or position a glass button
            // using separate width, height or safe-area offsets.
            // A UITab owns its provider's UIViewController. The old implementation
            // returned the SAME pageControllers every time tabs were rebuilt.
            // UIKit 27 asserts inside -[UITab viewController] when an already-owned
            // controller is handed to a newly created UITab (see device .ips).
            // Give each newly-created tab its own, never-before-owned controller.
            var nativeTabs = pageItems.enumerated().map { index, item -> UITab in
                let identifier = "page.\(index)"
                if let existing = retainedTabs[identifier] as? UITab { return existing }
                let controller = UIViewController()
                controller.view.backgroundColor = .clear
                let tab = UITab(title: item.title ?? "", image: item.image,
                                identifier: identifier) { _ in controller }
                retainedTabs[identifier] = tab
                return tab
            }
            if bottomSearchEnabled {
                let controller = UIViewController()
                controller.view.backgroundColor = .clear
                if separateSearch {
                    let search = UISearchTab { _ in controller }
                    if #available(iOS 26.0, *) { search.automaticallyActivatesSearch = false }
                    nativeTabs.append(search)
                } else {
                    nativeTabs.append(UITab(title: "搜索", image: UIImage(systemName: "magnifyingglass"),
                                            identifier: "action.search") { _ in controller })
                }
            }
            setTabs(nativeTabs, animated: false)
        } else {
            setViewControllers(pageControllers + (bottomSearchEnabled ? [searchController] : []), animated: false)
        }
        // Keep the shared WebKit document alive while native tabs change.
        selectNativePage(activePageTag)
        for (index, item) in (tabBar.items ?? []).enumerated() { item.tag = index }
        applyTabFont()
        keepContentBelowNativeBar()
        view.setNeedsLayout()
        updateLayoutMetrics(force: true)
    }

    private func selectNativePage(_ tag: Int) {
        activePageTag = min(max(tag, 0), 2)
        if #available(iOS 18.0, *) {
            selectedTab = tabs.first { $0.identifier == "page.\(activePageTag)" }
        } else if pageControllers.indices.contains(activePageTag) {
            selectedViewController = pageControllers[activePageTag]
        }
        keepContentBelowNativeBar()
    }

    private func keepContentBelowNativeBar() {
        guard let webView, isViewLoaded, let parent = selectedViewController,
              let host = parent.view else { return }
        // Content belongs to the selected tab. UIKit keeps its native floating
        // bar above this page and propagates the page's safe-area insets.
        if webView.superview !== host {
            UIView.performWithoutAnimation {
                webView.isHidden = true
                NSLayoutConstraint.deactivate(webHostConstraints)
                webView.removeFromSuperview()
                host.insertSubview(webView, at: 0)
            webView.translatesAutoresizingMaskIntoConstraints = false
                webHostConstraints = [webView.topAnchor.constraint(equalTo: host.topAnchor),
                    webView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                    webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                    webView.trailingAnchor.constraint(equalTo: host.trailingAnchor)]
                NSLayoutConstraint.activate(webHostConstraints)
                // Don't force layout here - it can interfere with tab bar layout during switch.
                // The constraints will apply on the next natural layout pass.
                if !suppressWebViewReveal { webView.isHidden = false }
            }
        }
        attachNativeHome(to: parent, host: host)
        let scroll = nativePageName == "home" ? (nativeHomeScrollView ?? webView.scrollView) : webView.scrollView
        if boundScrollViews[ObjectIdentifier(parent)] !== scroll {
            parent.setContentScrollView(scroll, for: .bottom)
            boundScrollViews[ObjectIdentifier(parent)] = scroll
        }
    }

    private func setBottomSearchEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "youyou.bottomSearchEnabled")
        bottomSearchEnabled = enabled
        refreshSearchTabItems()
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if viewController === searchController {
            // Action-only item: keep the currently selected page.
            presentBottomSearch()
            return false
        }
        guard let tag = pageControllers.firstIndex(of: viewController) else { return true }
        return prepareNativePageSelection(tag)
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        if tab is UISearchTab || tab.identifier == "action.search" {
            // Both native entries open the same full-screen search page.
            // Keep the content tab selected so closing search restores it.
            presentBottomSearch()
            return false
        }
        guard let tag = Int(tab.identifier.replacingOccurrences(of: "page.", with: "")) else { return true }
        return prepareNativePageSelection(tag)
    }

    private func prepareNativePageSelection(_ tag: Int) -> Bool {
        guard nativeHomeReady, tag != activePageTag else { return true }
        let page = tag == 1 ? "rules" : tag == 2 ? "settings" : "home"
        // Root cause of the tab-switch flash: the old code moved the shared
        // WKWebView into the new tab and revealed it BEFORE the async
        // appNavTo() JS swapped the page, so the old page's DOM showed through
        // the new tab for a few frames. Neither performWithoutAnimation nor
        // hide-during-move could fix that ordering. Fix: keep the webView
        // hidden until the new page's DOM is live, then seat it and reveal.
        // (Same principle as navigateFromNativeTab: JS content first, move after.)
        pageSwitchGeneration += 1
        let generation = pageSwitchGeneration
        switchingNativePage = true
        suppressWebViewReveal = true
        // Don't hide or fade out at start - keep old content visible.
        // The smooth fade-in at the end will mask the transition.
        // Switch tab UI immediately for instant feedback (user sees tab change)
        UIView.performWithoutAnimation {
            self.selectNativePage(tag)
            self.updatePageScroll(page)
        }
        self.keepContentBelowNativeBar()
        self.updateLayoutMetrics(force: true)
        // Navigate and wait for render (2 frames) before revealing - no flash
        let js = "appNavTo('" + page + "');window.__syncNativeCardGlass?.();"
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            guard let self else { return }
            guard self.pageSwitchGeneration == generation else { return }
            // Wait a tick for render, then reveal
            DispatchQueue.main.async {
                guard self.pageSwitchGeneration == generation else { return }
                if page == "home" {
                    // Homepage is native: fade WebView out, keep hidden
                    UIView.animate(withDuration: 0.3, animations: {
                        self.webView?.alpha = 0.0
                    }, completion: { _ in
                        self.webView?.isHidden = true
                    })
                } else {
                    // Web pages: gradual fade-in for smooth appearance
                    self.webView?.isHidden = false
                    self.webView?.alpha = 0.0
                    UIView.animate(withDuration: 0.35, delay: 0.05, options: .curveEaseOut, animations: {
                        self.webView?.alpha = 1.0
                    }, completion: nil)
                }
                self.switchingNativePage = false
                self.suppressWebViewReveal = false
            }
        }
        return false
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        guard let tag = Int(selectedTab.identifier.replacingOccurrences(of: "page.", with: "")) else { return }
        navigateFromNativeTab(tag)
    }

    private func presentBottomSearch() {
        guard bottomSearchEnabled, !openingSearch, activeSearchPageController == nil, presentedViewController == nil else { return }
        openingSearch = true
        webView.evaluateJavaScript("window.__bottomSearchState?.()") { [weak self] value, _ in
            guard let self else { return }
            self.openingSearch = false
            guard self.presentedViewController == nil else { return }
            let state = value as? [String: Any] ?? [:]
            self.activeSearchPage = state["page"] as? String ?? "home"
            let page = LUIYoSearchViewController()
            page.query = state["query"] as? String ?? ""
            page.themeFont = self.themeFont
            page.backgroundImage = self.backgroundImageView.image
            page.placeholder = state["placeholder"] as? String ?? "搜索"
            page.onSearch = { [weak self] query in self?.applyBottomSearch(query) }
            page.onClose = { [weak self] in
                guard let self else { return }
                self.nativeHomeModel.query = ""
                self.webView.evaluateJavaScript("window.__clearBottomSearch?.()")
                let search = self.activeSearchPageController
                self.activeSearchPageController = nil
                search?.willMove(toParent: nil)
                search?.view.removeFromSuperview()
                search?.removeFromParent()
                UIView.performWithoutAnimation {
                    self.keepContentBelowNativeBar()
                    self.view.layoutIfNeeded()
                    self.updateLayoutMetrics(force: true)
                }
            }
            page.onLayout = { [weak self] in
                guard let self else { return }
                guard let search = self.activeSearchPageController else { return }
                let top = search.searchField.convert(search.searchField.bounds, to: self.webView).minY
                self.webView.evaluateJavaScript("window.__setNativeTabTop?.(\(top));window.__syncNativeCardGlass?.()")
            }
            self.activeSearchPageController = page
            // A transparent child overlay leaves the live page and tab bar attached.
            self.addChild(page)
            page.view.frame = self.view.bounds
            page.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.view.addSubview(page.view)
            page.view.layer.zPosition = 3
            page.didMove(toParent: self)
            page.view.layoutIfNeeded()
            page.searchField.becomeFirstResponder()
        }
    }

    private func applyBottomSearch(_ query: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: [query, activeSearchPage]),
              let arguments = String(data: data, encoding: .utf8) else { return }
        if activeSearchPage == "home" { nativeHomeModel.query = query }
        webView.evaluateJavaScript("window.__applyBottomSearch?.(..." + arguments + ")")
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if #available(iOS 18.0, *) { return }
        if viewController === searchController {
            selectNativePage(activePageTag)
            presentBottomSearch()
            return
        }
        guard let tag = pageControllers.firstIndex(of: viewController) else { return }
        navigateFromNativeTab(tag)
    }

    private func openHeroSection(_ selector: String) {
        webView.evaluateJavaScript("window.__toggleHeroSection?.('" + selector + "')")
    }

    private func navigateFromNativeTab(_ tag: Int) {
        activePageTag = tag
        let page: String
        switch tag {
        case 1: page = "rules"
        case 2: page = "settings"
        default: page = "home"
        }
        updatePageScroll(page)
        guard nativeHomeReady else {
            keepContentBelowNativeBar()
            return
        }
        // Switch content FIRST via JS (instant CSS toggle), then move WebView.
        // This prevents ghosting: WebView already shows correct page when moved.
        webView.evaluateJavaScript("appNavTo(\'" + page + "\')") { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.keepContentBelowNativeBar()
            }
        }
    }

    static var savedAppearanceStyle: UIUserInterfaceStyle {
        switch UserDefaults.standard.string(forKey: "youyou.appearanceMode") {
        case "light": return .light
        case "dark": return .dark
        default: return .unspecified
        }
    }

    private func applyAppearance(_ rawMode: String) {
        let mode = ["light", "dark"].contains(rawMode) ? rawMode : "system"
        UserDefaults.standard.set(mode, forKey: "youyou.appearanceMode")
        let style = Self.savedAppearanceStyle
        overrideUserInterfaceStyle = style
        view.window?.overrideUserInterfaceStyle = style
        webView.overrideUserInterfaceStyle = style
        applyStoredPalette()
        setNeedsStatusBarAppearanceUpdate()
    }

    private func storedColor(_ kind: String, lightDefault: String, darkDefault: String) -> UIColor {
        let defaults = UserDefaults.standard
        let light = color(fromHex: defaults.string(forKey: "youyou.\(kind).light") ?? lightDefault) ?? .white
        let dark = color(fromHex: defaults.string(forKey: "youyou.\(kind).dark") ?? darkDefault) ?? .black
        return UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
    }

    private func applyStoredPalette() {
        // Keep solid palette only when no custom background image is active.
        if backgroundImageView.image == nil {
            view.backgroundColor = storedColor("background", lightDefault: "#F2F2F7", darkDefault: "#121214")
        } else {
            view.backgroundColor = .clear
        }
        nativeHomeHost?.view.backgroundColor = backgroundImageView.image == nil ? view.backgroundColor : .clear
        cardTintColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(nativeHex: "#1C1C1E") : .white }
        if let hero = settingsHero { LUIYoRefreshSettingsHero(hero); LUIYoSetSettingsHeroFont(hero, themeFont) }
        updateNativeCardTint()
        renderVisibleNativeMaterials()
    }

    /// Drop every native card material host so the next rect sync rebuilds a clean layer stack.
    private func clearAllNativeCardMaterials() {
        for key in Array(cardMaterialViews.keys) {
            cardMaterialViews.removeValue(forKey: key)?.removeFromSuperview()
            cardMaterialHosts.removeValue(forKey: key)?.removeFromSuperview()
            nativeSymbols.removeValue(forKey: key)?.removeFromSuperview()
            nativeSegments.removeValue(forKey: key)
            nativeLicenseButtons.removeValue(forKey: key)?.removeFromSuperview()
            nativeSelectedPills.removeValue(forKey: key)?.removeFromSuperview()
            nativeThemeSwitches.removeValue(forKey: key)?.removeFromSuperview()
            nativeSegmentStyles.removeValue(forKey: key)
        }
        cardDocumentFrames.removeAll()
        cardSpecs.removeAll()
        cardOrder.removeAll()
    }

    private func updateLayoutMetrics(force: Bool = false) {
        guard activeSearchPageController == nil, let webView, tabBar.frame.minY > 0 else { return }
        let top = tabBar.convert(tabBar.bounds, to: webView).minY
        guard force || abs(top - reportedTabTop) > 0.5 else { return }
        reportedTabTop = top
        webView.evaluateJavaScript("window.__setNativeTabTop?.(\(top))")
    }

    private func nativeCardEffect() -> UIVisualEffect {
        switch cardMaterialMode {
        case .liquid:
            if #available(iOS 26.0, *) {
                let glass = UIGlassEffect(style: .regular)
                let hex = cardTintColor.nativeHex.uppercased()
                if !["#FFFFFF", "#1C1C1E"].contains(hex) { glass.tintColor = cardTintColor.withAlphaComponent(0.12) }
                return glass
            }
            return UIBlurEffect(style: .systemMaterial)
        case .blur:
            return UIBlurEffect(style: .systemMaterial)
        }
    }

    private func setCardMaterialMode(_ rawMode: String) {
        nativeHomeModel.useBlur = rawMode == "blur"
        cardMaterialMode = rawMode == "blur" ? .blur : .liquid
        UIView.performWithoutAnimation {
            for (key, surface) in cardMaterialViews {
                surface.effect = effect(for: cardSpecs[key] ?? [:])
            }
            updateNativeCardTint()
        }
    }

    private func color(fromHex hex: String) -> UIColor? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = Int(value, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1
        )
    }

    private func setCardTintColor(_ color: UIColor) {
        guard !cardTintColor.isEqual(color) else { return }
        cardTintColor = color
        for (key, surface) in cardMaterialViews { surface.effect = effect(for: cardSpecs[key] ?? [:]) }
        updateNativeCardTint()
    }

    private func effect(for spec: [String: Any]) -> UIVisualEffect {
        if (spec["forceLiquid"] as? Bool) == true, #available(iOS 26.0, *) {
            return UIGlassEffect()
        }
        return nativeCardEffect()
    }

    private func applyTint(to surface: UIVisualEffectView, spec: [String: Any]) {
        // Glass supplies its own fill/refraction. A painted fill conceals it.
        if #available(iOS 26.0, *), surface.effect is UIGlassEffect {
            surface.contentView.backgroundColor = .clear
        } else { surface.contentView.backgroundColor = cardTintColor.withAlphaComponent(0.24) }
    }

    private func updateNativeCardTint() {
        for (key, surface) in cardMaterialViews {
            applyTint(to: surface, spec: cardSpecs[key] ?? [:])
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Remove extra layer shadows without replacing native system glass.
        removeExtraLayerShadows(tabBar.layer)
        updateTabLabelFonts(in: tabBar)
        keepContentBelowNativeBar()
        updateLayoutMetrics()
        renderVisibleNativeMaterials()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded, previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyStoredPalette()
        setNeedsStatusBarAppearanceUpdate()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }

    private var nativeBackgroundURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ThemeBackground.jpg")
    }

    private func setScrollMinimize(_ enabled: Bool) {
        scrollMinimizeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "youyou.minimizeBottomBar")
        if #available(iOS 26.0, *) { tabBarMinimizeBehavior = enabled ? .onScrollDown : .never }
    }

    private func updateNativeShrinkSwitch(_ payload: [String: Any]) {
        let x = payload["x"] as? CGFloat ?? 0
        let y = payload["y"] as? CGFloat ?? 0
        let visible = payload["visible"] as? Bool ?? false
        let enabled = payload["enabled"] as? Bool ?? false
        DispatchQueue.main.async { [weak self] in
            guard let self, let webView = self.webView else { return }
            if self.nativeShrinkSwitch == nil {
                let sw = UISwitch()
                sw.addTarget(self, action: #selector(self.shrinkSwitchChanged(_:)), for: .valueChanged)
                // Add to webView's superview so coordinates match
                if let host = webView.superview {
                    host.addSubview(sw)
                } else {
                    self.view.addSubview(sw)
                }
                self.nativeShrinkSwitch = sw
            }
            guard let sw = self.nativeShrinkSwitch else { return }
            // Ensure switch is in the correct superview (webView may move between tabs)
            if sw.superview !== webView.superview, let host = webView.superview {
                sw.removeFromSuperview()
                host.addSubview(sw)
            }
            let isSettings = self.activePageTag == 2
            sw.isHidden = !(visible && isSettings)
            if visible && isSettings {
                // x,y are relative to webView, which matches superview coordinates
                sw.frame = CGRect(x: x, y: y, width: 51, height: 31)
                sw.isOn = enabled
                sw.superview?.bringSubviewToFront(sw)
            }
        }
    }

    @objc private func shrinkSwitchChanged(_ sender: UISwitch) {
        let enabled = sender.isOn
        setScrollMinimize(enabled)
        webView?.evaluateJavaScript("if(typeof applyShrink==='function')applyShrink(\(enabled))", completionHandler: nil)
    }

    private func updatePageScroll(_ page: String) {
        nativePageName = page
        keepContentBelowNativeBar()
        webView.scrollView.showsVerticalScrollIndicator = page != "settings"
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.alwaysBounceVertical = page != "settings"
    }

    private func presentZipName(_ name: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "导出 ZIP", message: "修改文件名", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = name
            field.placeholder = "优优LUI图标包"
            field.accessibilityIdentifier = "zipExportName"
            field.clearButtonMode = .whileEditing
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "分享", style: .default) { [weak self, weak alert] _ in
            let value = alert?.textFields?.first?.text ?? "优优LUI图标包"
            guard let data = try? JSONSerialization.data(withJSONObject: [value]), let args = String(data: data, encoding: .utf8) else { return }
            let share: () -> Void = { [weak self] in
                self?.webView.evaluateJavaScript("window.__shareZipWithName?.(..." + args + ")")
            }
            // Finish the name alert before WebKit can request the share sheet.
            if let alert, self?.presentedViewController === alert { alert.dismiss(animated: false, completion: share) }
            else { share() }
        })
        present(alert, animated: true)
    }

    private var nativeFontURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ThemeFont.data")
    }

    @discardableResult private func setNativeFont(_ data: Data) -> Bool {
        if themeFontData == data {
            nativeHomeModel.importedFont = themeFont
            applyTabFont()
            return true
        }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return false }
        if let font = registeredThemeGraphicsFont { CTFontManagerUnregisterGraphicsFont(font, nil) }
        let createdFont = CTFontCreateWithFontDescriptor(descriptor, 10, nil)
        let graphicsFont = CTFontCopyGraphicsFont(createdFont, nil)
        registeredThemeGraphicsFont = CTFontManagerRegisterGraphicsFont(graphicsFont, nil) ? graphicsFont : nil
        themeFont = createdFont as UIFont
        nativeHomeModel.fontName = themeFont?.fontName
        nativeHomeModel.importedFont = themeFont
        themeFontData = data
        applyTabFont()
        return true
    }

    private func applyTabFont() {
        // Change title fonts only; retain all UIKit Liquid Glass/background settings.
        if let base = defaultTabAppearance?.copy() as? UITabBarAppearance {
            if let font = themeFont {
                for layout in [base.stackedLayoutAppearance, base.inlineLayoutAppearance, base.compactInlineLayoutAppearance] {
                    var normal = layout.normal.titleTextAttributes
                    var selected = layout.selected.titleTextAttributes
                    normal[.font] = font; selected[.font] = font
                    layout.normal.titleTextAttributes = normal
                    layout.selected.titleTextAttributes = selected
                }
            }
            tabBar.standardAppearance = base
            if let edge = defaultScrollEdgeAppearance?.copy() as? UITabBarAppearance {
                if let font = themeFont {
                    for layout in [edge.stackedLayoutAppearance, edge.inlineLayoutAppearance, edge.compactInlineLayoutAppearance] {
                        var normal = layout.normal.titleTextAttributes
                        var selected = layout.selected.titleTextAttributes
                        normal[.font] = font; selected[.font] = font
                        layout.normal.titleTextAttributes = normal
                        layout.selected.titleTextAttributes = selected
                    }
                }
                tabBar.scrollEdgeAppearance = edge
            }
        }
        for item in tabBar.items ?? [] {
            let attributes: [NSAttributedString.Key: Any]? = themeFont.map { [.font: $0] }
            item.setTitleTextAttributes(attributes, for: .normal)
            item.setTitleTextAttributes(attributes, for: .selected)
        }
        updateTabLabelFonts(in: tabBar)
        activeSearchPageController?.themeFont = themeFont
        // Apply theme font to the settings hero card (native view).
        if let hero = settingsHero { LUIYoSetSettingsHeroFont(hero, themeFont) }
        tabBar.setNeedsLayout()
        // Defer expensive material rendering to avoid stutter during tab switch
        DispatchQueue.main.async { [weak self] in
            self?.renderVisibleNativeMaterials()
        }
    }

    private func updateTabLabelFonts(in view: UIView) {
        if let label = view as? UILabel, let text = label.text,
           ["首页", "规则", "设置", "搜索", "Search"].contains(text) {
            if originalTabLabelFonts.object(forKey: label) == nil {
                let original = themeFont == nil ? label.font! : UIFont.systemFont(ofSize: label.font.pointSize)
                originalTabLabelFonts.setObject(original, forKey: label)
            }
            if let original = originalTabLabelFonts.object(forKey: label) {
                let desired = themeFont?.withSize(original.pointSize) ?? original
                if label.font != desired { label.font = desired }
            }
        }
        for child in view.subviews { updateTabLabelFonts(in: child) }
    }

    private func configureSymbol(in surface: UIVisualEffectView, key: String, spec: [String: Any]) {
        guard let name = spec["systemIcon"] as? String, !name.isEmpty else {
            nativeSymbols.removeValue(forKey: key)?.removeFromSuperview()
            return
        }
        let icon: UIImageView
        if let existing = nativeSymbols[key] { icon = existing }
        else {
            icon = UIImageView()
            icon.isUserInteractionEnabled = false
            icon.isAccessibilityElement = false
            icon.contentMode = .scaleAspectFit
            surface.contentView.addSubview(icon)
            nativeSymbols[key] = icon
        }
        if name.hasPrefix("icon-"),
           let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Web"),
           let custom = UIImage(contentsOfFile: url.path) {
            icon.image = custom.withRenderingMode(.alwaysOriginal)
            icon.tintColor = nil
        } else {
            icon.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
            icon.tintColor = .label
        }
        let x = CGFloat((spec["iconX"] as? NSNumber)?.doubleValue ?? 0)
        let y = CGFloat((spec["iconY"] as? NSNumber)?.doubleValue ?? 0)
        let width = CGFloat((spec["iconWidth"] as? NSNumber)?.doubleValue ?? 28)
        let height = CGFloat((spec["iconHeight"] as? NSNumber)?.doubleValue ?? 28)
        icon.frame = CGRect(x: x + (width - 20) / 2, y: y + (height - 20) / 2, width: 20, height: 20)
    }

    private func configureSegment(in surface: UIVisualEffectView, key: String, spec: [String: Any]) {
        guard let kind = spec["segment"] as? String else { return }
        let titles = kind == "category" ? ["原版微信", "LiquidUI"]
            : (kind == "appearance" ? ["跟随系统", "浅色", "深色"] : kind == "search" ? ["关闭", "合并", "分开"] : ["液态玻璃", "原生磨砂"])
        let segment: UISegmentedControl
        if let existing = nativeSegments[key] {
            segment = existing
        } else {
            segment = UISegmentedControl(items: titles)
            // WebKit retains the transparent hit targets, file import handlers,
            // accessibility labels and scrolling gestures. UIKit draws the control.
            segment.isUserInteractionEnabled = false
            segment.selectedSegmentTintColor = .secondarySystemGroupedBackground
            let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            segment.setTitleTextAttributes([.font: font, .foregroundColor: UIColor.label], for: .normal)
            segment.setTitleTextAttributes([.font: font, .foregroundColor: UIColor.label], for: .selected)
            let pill = UIView()
            pill.isUserInteractionEnabled = false
            pill.accessibilityElementsHidden = true
            surface.contentView.addSubview(pill)
            nativeSelectedPills[key] = pill
            surface.contentView.addSubview(segment)
            nativeSegments[key] = segment
        }
        segment.backgroundColor = .clear
        // All three pickers share one translucent track and selected capsule.
        // Clear the built-in background so UIKit doesn't stack a darker pill.
        if nativeSegmentStyles[key] != traitCollection.userInterfaceStyle {
            let clear = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
            segment.setBackgroundImage(clear, for: .normal, barMetrics: .default)
            segment.setBackgroundImage(clear, for: .selected, barMetrics: .default)
            segment.setBackgroundImage(clear, for: [.selected, .highlighted], barMetrics: .default)
            segment.setDividerImage(clear, forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)
            nativeSegmentStyles[key] = traitCollection.userInterfaceStyle
        }
        let selectedColor = UIColor.white
        segment.selectedSegmentTintColor = .clear
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let font = themeFont?.withSize(12) ?? UIFont.systemFont(ofSize: 12, weight: .semibold)
        segment.setTitleTextAttributes([.font: font, .foregroundColor: UIColor.label], for: .normal)
        selectedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let selectedText = red * 0.2126 + green * 0.7152 + blue * 0.0722 > 0.5
            ? UIColor(red: 32.0/255, green: 40.0/255, blue: 50.0/255, alpha: 1)
            : UIColor(red: 242.0/255, green: 242.0/255, blue: 247.0/255, alpha: 1)
        segment.setTitleTextAttributes([.font: font, .foregroundColor: selectedText], for: .selected)
        segment.frame = surface.bounds
        segment.layer.cornerRadius = surface.bounds.height / 2
        segment.clipsToBounds = true
        let selected = (spec["selected"] as? NSNumber)?.intValue ?? 0
        if segment.selectedSegmentIndex != selected {
            segment.selectedSegmentIndex = selected
        }
        if let pill = nativeSelectedPills[key], surface.bounds.width > 4, surface.bounds.height > 4 {
            let track = surface.bounds.insetBy(dx: 2, dy: 2)
            let width = track.width / CGFloat(segment.numberOfSegments)
            UIView.performWithoutAnimation {
                pill.frame = CGRect(x: track.minX + CGFloat(selected) * width, y: track.minY, width: width, height: track.height)
                pill.backgroundColor = selectedColor
                pill.layer.cornerRadius = track.height / 2
                pill.layer.cornerCurve = .continuous
                pill.layer.borderWidth = 0
                pill.layer.shadowColor = UIColor.black.cgColor
                pill.layer.shadowOpacity = kind == "category" ? 0.065 : 0
                pill.layer.shadowRadius = 1
                pill.layer.shadowOffset = CGSize(width: 0, height: 0.5)
            }
        }
    }

    private func renderVisibleNativeMaterials() {
        guard let webView else { return }
        let scroll = webView.scrollView
        // This observer only manages visibility. It NEVER moves a card with an
        // asynchronously sampled scroll offset.
        glassContainer.frame = CGRect(origin: .zero, size: CGSize(
            width: max(scroll.contentSize.width, scroll.bounds.width),
            height: max(scroll.contentSize.height, scroll.bounds.height)
        ))
        let visible = scroll.bounds.insetBy(dx: 0, dy: -scroll.bounds.height)
        UIView.performWithoutAnimation {
            for key in cardOrder {
                guard let frame = cardDocumentFrames[key], let spec = cardSpecs[key] else { continue }
                let clip = CGRect(
                    x: (spec["clipX"] as? NSNumber)?.doubleValue ?? Double(frame.minX),
                    y: (spec["clipY"] as? NSNumber)?.doubleValue ?? Double(frame.minY),
                    width: (spec["clipWidth"] as? NSNumber)?.doubleValue ?? Double(frame.width),
                    height: (spec["clipHeight"] as? NSNumber)?.doubleValue ?? Double(frame.height)
                ).intersection(frame)
                guard !clip.isNull, clip.width > 0, clip.height > 0, clip.intersects(visible) else {
                    cardMaterialHosts[key]?.isHidden = true
                    continue
                }
                let surface: UIVisualEffectView
                if let existing = cardMaterialViews[key] {
                    surface = existing
                } else {
                    surface = UIVisualEffectView(effect: effect(for: spec))
                    surface.isUserInteractionEnabled = false
                    surface.clipsToBounds = true
                    let host = UIView()
                    host.isUserInteractionEnabled = false
                    host.clipsToBounds = true
                    glassContainer.addSubview(host)
                    host.addSubview(surface)
                    cardMaterialHosts[key] = host
                    cardMaterialViews[key] = surface
                }
                cardMaterialHosts[key]?.isHidden = false
                cardMaterialHosts[key]?.frame = clip
                // Clip only animated fold overflow; let UIKit render the glass edge.
                let cropped = clip.minX > frame.minX + 0.5 || clip.minY > frame.minY + 0.5
                    || clip.maxX < frame.maxX - 0.5 || clip.maxY < frame.maxY - 0.5
                surface.frame = CGRect(x: frame.minX - clip.minX, y: frame.minY - clip.minY, width: frame.width, height: frame.height)
                let requested = CGFloat((spec["radius"] as? NSNumber)?.doubleValue ?? 24)
                // CSS uses 999px for pills; CALayer needs the actual finite radius.
                surface.layer.cornerRadius = min(max(0, requested), min(frame.width, frame.height) / 2)
                if #available(iOS 26.0, *), surface.effect is UIGlassEffect {
                    surface.cornerConfiguration = .uniformCorners(radius: .fixed(Double(surface.layer.cornerRadius)))
                    surface.clipsToBounds = false
                } else { surface.clipsToBounds = true }
                cardMaterialHosts[key]?.clipsToBounds = cropped
                cardMaterialHosts[key]?.layer.cornerRadius = 0
                applyTint(to: surface, spec: spec)
                configureSymbol(in: surface, key: key, spec: spec)
                if spec["ruleSurface"] as? Bool == true, let host = cardMaterialHosts[key] {
                    host.layer.cornerRadius = cropped ? 0 : surface.layer.cornerRadius
                    host.clipsToBounds = true
                }
                if spec["licenseButton"] as? Bool == true {
                    let button = nativeLicenseButtons[key] ?? UIButton(type: .system)
                    if nativeLicenseButtons[key] == nil {
                        button.isUserInteractionEnabled = false
                        button.accessibilityElementsHidden = true
                        surface.contentView.addSubview(button)
                        nativeLicenseButtons[key] = button
                    }
                    var configuration: UIButton.Configuration
                    if #available(iOS 26.0, *), cardMaterialMode == .liquid { configuration = .prominentGlass() }
                    else {
                        configuration = .plain()
                        configuration.background.visualEffect = UIBlurEffect(style: .systemMaterial)
                    }
                    configuration.title = spec["licenseTitle"] as? String ?? "激活"
                    configuration.baseBackgroundColor = UIColor(nativeHex: "#6968E8")
                    configuration.baseForegroundColor = .white
                    configuration.cornerStyle = .capsule
                    let font = themeFont?.withSize(13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
                    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                        var result = attributes; result.font = font; return result
                    }
                    button.configuration = configuration
                    button.tintColor = UIColor(nativeHex: "#6968E8")
                    button.frame = surface.bounds
                    surface.effect = nil
                    surface.contentView.backgroundColor = .clear
                    surface.clipsToBounds = false
                }
                removeExtraLayerShadows(surface.layer)
                if let host = cardMaterialHosts[key] { removeExtraLayerShadows(host.layer) }
                configureSegment(in: surface, key: key, spec: spec)
            }
        }
    }

    private func updateNativeCardRects(_ rects: [[String: Any]]) {
        var frames: [String: CGRect] = [:]
        var specs: [String: [String: Any]] = [:]
        var order: [String] = []
        for (index, item) in rects.enumerated() {
            let key = (item["key"] as? String) ?? "legacy:\(index)"
            let x = (item["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (item["y"] as? NSNumber)?.doubleValue ?? 0
            let width = (item["width"] as? NSNumber)?.doubleValue ?? 0
            let height = (item["height"] as? NSNumber)?.doubleValue ?? 0
            guard x.isFinite, y.isFinite, width.isFinite, height.isFinite, width > 0, height > 0 else { continue }
            // Incoming coordinates are DOCUMENT coordinates, never viewport ones.
            frames[key] = CGRect(x: x, y: y, width: width, height: height)
            specs[key] = item
            order.append(key)
        }
        for key in Array(cardMaterialViews.keys) where frames[key] == nil {
            cardMaterialViews.removeValue(forKey: key)?.removeFromSuperview()
            cardMaterialHosts.removeValue(forKey: key)?.removeFromSuperview()
            nativeSymbols.removeValue(forKey: key)?.removeFromSuperview()
            nativeSegments.removeValue(forKey: key)
            nativeLicenseButtons.removeValue(forKey: key)?.removeFromSuperview()
            nativeSelectedPills.removeValue(forKey: key)?.removeFromSuperview()
            nativeSegmentStyles.removeValue(forKey: key)
        }
        cardDocumentFrames = frames
        cardSpecs = specs
        cardOrder = order
        renderVisibleNativeMaterials()
    }

    private func attachNativeHome(to parent: UIViewController, host: UIView) {
        let visible = nativePageName == "home" && (activeSearchPageController == nil || activeSearchPage == "home")
        // Keep WebKit attached and rendering so its processing/input state stays live.
        // An opaque native home covers it; other tabs have no SwiftUI overlay.
        if !suppressWebViewReveal { webView.isHidden = false }
        webView.isUserInteractionEnabled = !visible
        webView.accessibilityElementsHidden = visible
        // The homepage stays attached to its own tab, including while hidden.
        // Switching rules/settings only moves WebKit, never the SwiftUI tree.
        guard visible else {
            nativeHomeHost?.view.isHidden = true
            nativeHomeHost?.view.accessibilityElementsHidden = true
            return
        }
        if nativeHomeHost == nil {
            let controller = UIHostingController(rootView: LUIYoNativeHome(model: nativeHomeModel))
            controller.view.backgroundColor = backgroundImageView.image == nil ? view.backgroundColor : .clear
            nativeHomeHost = controller
        }
        guard let controller = nativeHomeHost else { return }
        if controller.parent == nil {
            parent.addChild(controller)
            host.addSubview(controller.view)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            nativeHomeConstraints = [controller.view.topAnchor.constraint(equalTo: host.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                controller.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: host.trailingAnchor)]
            NSLayoutConstraint.activate(nativeHomeConstraints)
            controller.didMove(toParent: parent)
        }
        controller.view.isHidden = !visible
        controller.view.accessibilityElementsHidden = !visible
    }

    private func nativeHomeCommand(_ action: String, _ values: [String: Any]) {
        guard isAuthorized else { showAuthorizationRequired(); return }
        guard nativeHomeReady else { return }
        if ["upload", "batch", "fillImage"].contains(action) {
            nativeUploadKind = action == "fillImage" ? "fillImage" : action
            nativeUploadIndex = values["id"] as? Int
            if action == "batch" { presentNativeFiles(); return }
            let alert = UIAlertController(title: "选择图片", message: nil, preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "照片", style: .default) { [weak self] _ in self?.presentNativePhotos() })
            alert.addAction(UIAlertAction(title: "文件", style: .default) { [weak self] _ in self?.presentNativeFiles() })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.popoverPresentationController?.sourceView = view
            alert.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            present(alert, animated: true)
            return
        }
        if action == "clear" {
            let alert = UIAlertController(title: "清空上传图片？", message: "将移除本次上传与补全图片。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in self?.runNativeEngine("clear", [:]) })
            present(alert, animated: true); return
        }
        runNativeEngine(action, values)
    }

    private func runNativeEngine(_ action: String, _ values: [String: Any]) {
        // Gate every mutation again after the picker/asynchronous provider returns.
        guard ["state", "category", "search"].contains(action) || isAuthorized else { showAuthorizationRequired(); return }
        guard let data = try? JSONSerialization.data(withJSONObject: [action, values]),
              let arguments = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("Promise.resolve(window.__nativeHomeCommand?.(..." + arguments + ")).catch(error => alert(error.message)); undefined;") { [weak self] _, error in
            guard let self, let error else { return }
            let alert = UIAlertController(title: "操作失败", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            if self.presentedViewController == nil { self.present(alert, animated: true) }
        }
    }

    private var heroAvatarURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SettingsAvatar.png")
    }

    private func editHeroAvatar() {
        guard presentedViewController == nil else { return }
        nativeUploadKind = "heroAvatar"
        presentNativePhotos()
    }

    private func editHeroName() {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "修改名字", message: nil, preferredStyle: .alert)
        alert.addTextField { field in field.text = UserDefaults.standard.string(forKey: "youyou.hero.name") ?? "LUIYo"; field.placeholder = "输入名字" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self, let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
            UserDefaults.standard.set(String(name.prefix(32)), forKey: "youyou.hero.name")
            if let hero = self.settingsHero { LUIYoRefreshSettingsHero(hero); LUIYoSetSettingsHeroFont(hero, self.themeFont) }
        })
        present(alert, animated: true)
    }

    private func saveHeroAvatar(_ data: Data) {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { showErrorAlert("无法读取所选头像。"); return }
        let scale = min(1, 512 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let png = normalized.pngData() else { showErrorAlert("无法保存头像。"); return }
        do {
            try FileManager.default.createDirectory(at: heroAvatarURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: heroAvatarURL, options: .atomic)
            if let hero = settingsHero { LUIYoRefreshSettingsHero(hero); LUIYoSetSettingsHeroFont(hero, themeFont) }
        } catch { showErrorAlert("头像保存失败，请重试。") }
    }

    private func presentNativeFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
        picker.allowsMultipleSelection = nativeUploadKind == "batch"
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentNativePhotos() {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let kind = nativeUploadKind, index = nativeUploadIndex
        var files: [[String: String]] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let file = nativeImageFile(data, name: url.lastPathComponent) { files.append(file) }
        }
        guard !files.isEmpty else { showErrorAlert("无法读取所选图片，请重新选择。"); return }
        receiveNativeFiles(files, kind: kind, index: index)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        let kind = nativeUploadKind, index = nativeUploadIndex
        let imageType = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier
        provider.loadDataRepresentation(forTypeIdentifier: imageType) { [weak self] data, error in
            guard let self else { return }
            let file = data.flatMap { self.nativeImageFile($0, name: provider.suggestedName ?? "图片.png") }
            DispatchQueue.main.async {
                if kind == "heroAvatar" {
                    guard let data else { self.showErrorAlert("无法读取头像，请换一张图片。"); return }
                    self.saveHeroAvatar(data)
                    return
                }
                guard let file else { self.showErrorAlert("无法读取照片，请使用文件选择或换一张图片。"); return }
                self.receiveNativeFiles([file], kind: kind, index: index)
            }
        }
    }

    private func nativeImageFile(_ data: Data, name: String) -> [String: String]? {
        guard let image = UIImage(data: data), let png = image.pngData() else { return nil }
        return ["name": name, "type": "image/png", "base64": png.base64EncodedString()]
    }

    private func receiveNativeFiles(_ files: [[String: String]], kind: String, index: Int?) {
        var payload: [String: Any] = ["files": files, "kind": kind]
        if let index { payload["id"] = index }
        runNativeEngine("files", payload)
    }

    private func showErrorAlert(_ text: String) {
        let alert = UIAlertController(title: "提示", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func showAuthorizationRequired() {
        let alert = UIAlertController(title: "尚未激活", message: "当前可以浏览页面。前往设置输入卡密，激活后才可使用功能。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
        alert.addAction(UIAlertAction(title: "前往设置", style: .default) { [weak self] _ in
            self?.selectNativePage(2)
            self?.navigateFromNativeTab(2)
        })
        present(alert, animated: true)
    }

    private func showError(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textAlignment = .center
        label.numberOfLines = 0
        label.frame = view.bounds.insetBy(dx: 24, dy: 24)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(label)
    }

    private func writeNativeHomeDiagnostics() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["LUI_SNAPSHOT"] == "preview-native-theme" else { return }
        let theme = nativeHomeModel.theme
        func alphas(_ view: UIView) -> [Double] {
            (view is UIVisualEffectView ? [Double(view.alpha)] : []) + view.subviews.flatMap(alphas)
        }
        let values: [String: Any] = ["background":theme.background,"card":theme.card,"button":theme.button,
            "rootBackground":view.backgroundColor?.resolvedColor(with: traitCollection).nativeHex ?? "",
            "toolbarOpacity":theme.toolbarOpacity,"materialBlur":nativeHomeModel.useBlur,
            "font":nativeHomeModel.fontName ?? "", "bottomSearchEnabled":theme.bottomSearchEnabled,
            "minimizeEnabled":scrollMinimizeEnabled,"scrollLinked":nativeHomeScrollView != nil && selectedViewController?.contentScrollView(for: .bottom) === nativeHomeScrollView,
            "scrollOffset":Double(nativeHomeScrollView?.contentOffset.y ?? 0),
            "nativeMaterialAlphas":nativeHomeHost.map { alphas($0.view) } ?? [],"uploadedCount":nativeHomeModel.uploadedCount]
        if let data = try? JSONSerialization.data(withJSONObject: values) {
            let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("native-home-diagnostics.json")
            try? data.write(to: file, options: .atomic)
        }
        #endif
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        if message.name == "nativeHomeState" {
            if let payload = message.body as? [String: Any] {
                nativeHomeModel.apply(payload)
                DispatchQueue.main.async { [weak self] in self?.writeNativeHomeDiagnostics() }
            }
            return
        }
        if message.name == "activationSubmit" {
            guard !isAuthorized, let payload = message.body as? [String: Any], let code = payload["code"] as? String else { return }
            onLicenseSubmitted?(code)
            return
        }
        if message.name == "activationOpen" {
            onActivationRequested?()
            return
        }
        if message.name == "settingsHeroFrame" {
            guard let payload = message.body as? [String: Any] else { return }
            if settingsHero == nil {
                let hero = LUIYoCreateSettingsHero({ [weak self] in self?.openHeroSection(".guideInline") }, { [weak self] in self?.openHeroSection(".changelogInline") }, { [weak self] in self?.editHeroAvatar() }, { [weak self] in self?.editHeroName() })
                hero.accessibilityIdentifier = "settingsBrandHero"
                webView.scrollView.addSubview(hero)
                settingsHero = hero
            }
            guard let hero = settingsHero else { return }
            hero.isHidden = !(payload["visible"] as? Bool ?? false)
            hero.frame = CGRect(x: (payload["x"] as? NSNumber)?.doubleValue ?? 0, y: (payload["y"] as? NSNumber)?.doubleValue ?? 0, width: (payload["width"] as? NSNumber)?.doubleValue ?? 0, height: 116)
            hero.setNeedsLayout()
            hero.layoutIfNeeded()
            return
        }
        if message.name == "pageState" {
            if let payload = message.body as? [String: Any] {
                let page = payload["page"] as? String ?? "home"
                if !switchingNativePage { updatePageScroll(page) }
                if ["home", "rules", "settings"].contains(page) { onPageChanged?(page) }
            }
            return
        }
        if message.name == "minimizeBottomBar" {
            if let payload = message.body as? [String: Any] { setScrollMinimize(payload["enabled"] as? Bool ?? false) }
            return
        }
        if message.name == "zipName" {
            if let payload = message.body as? [String: Any] { presentZipName(payload["name"] as? String ?? "优优LUI图标包") }
            return
        }
        if message.name == "backgroundImage" {
            // Feature removed: always clear any stored custom background image.
            backgroundImageView.image = nil
            try? FileManager.default.removeItem(at: nativeBackgroundURL)
            nativeHomeModel.backgroundImage = nil
            applyStoredPalette()
            nativeHomeHost?.view.backgroundColor = view.backgroundColor
            return
        }
        if message.name == "bottomSearch" {
            guard let payload = message.body as? [String: Any] else { return }
            let enabled = payload["enabled"] as? Bool ?? bottomSearchEnabled
            let separate = (payload["layout"] as? String).map { $0 == "separate" } ?? separateSearch
            if enabled != bottomSearchEnabled || separate != separateSearch {
                bottomSearchEnabled = enabled
                separateSearch = separate
                UserDefaults.standard.set(enabled, forKey: "youyou.bottomSearchEnabled")
                UserDefaults.standard.set(separate ? "separate" : "merged", forKey: "youyou.bottomSearchLayout")
                UIView.performWithoutAnimation { refreshSearchTabItems() }
            }
            if payload["open"] as? Bool == true { presentBottomSearch() }
            return
        }
        if message.name == "luiyoBlocked" {
            if let body = message.body as? String, body == "confirm" {
                // User confirmed the blocked popup - exit the app.
                exit(0)
            }
            return
        }
        if message.name == "themeFont" {
            guard let payload = message.body as? [String: Any] else { return }
            if payload["reset"] as? Bool == true {
                themeFont = nil; themeFontData = nil
                if let font = registeredThemeGraphicsFont { CTFontManagerUnregisterGraphicsFont(font, nil) }
                registeredThemeGraphicsFont = nil
                nativeHomeModel.fontName = nil
                nativeHomeModel.importedFont = nil
                try? FileManager.default.removeItem(at: nativeFontURL)
                applyTabFont()
            } else if let base64 = payload["data"] as? String,
                      let data = Data(base64Encoded: base64), setNativeFont(data) {
                try? FileManager.default.createDirectory(at: nativeFontURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: nativeFontURL, options: .atomic)
            }
            return
        }
        if message.name == "appearanceMode" {
            let payload = message.body as? [String: Any]
            applyAppearance(payload?["mode"] as? String ?? "system")
            return
        }

        if message.name == "nativeToggleRects" {
            guard let rows = message.body as? [[String: Any]] else { return }
            var visible = Set<String>()
            for row in rows {
                guard let id = row["id"] as? String, row["visible"] as? Bool == true else { continue }
                visible.insert(id)
                let control: UIControl
                if let existing = nativeThemeSwitches[id] { control = existing }
                else {
                    control = LUIYoCreateThemeSwitch(row["on"] as? Bool ?? false) { [weak self] enabled in
                        guard let data = try? JSONSerialization.data(withJSONObject: [id, enabled]), let args = String(data: data, encoding: .utf8) else { return }
                        self?.webView.evaluateJavaScript("window.__setBrandSwitch?.(..." + args + ")")
                    }
                    nativeThemeSwitches[id] = control
                    webView.scrollView.addSubview(control)
                }
                control.isHidden = false
                control.isEnabled = !(row["disabled"] as? Bool ?? false)
                control.accessibilityLabel = id == "minimizeBottomBar" ? "滚动时缩小底栏" : "启用自定义颜色"
                control.frame = CGRect(x: (row["x"] as? NSNumber)?.doubleValue ?? 0, y: (row["y"] as? NSNumber)?.doubleValue ?? 0, width: 44, height: 26)
                LUIYoSetThemeSwitch(control, row["on"] as? Bool ?? false)
            }
            for (id, control) in nativeThemeSwitches where !visible.contains(id) { control.isHidden = true }
            return
        }

        if message.name == "themeBackground" || message.name == "cardColor" || message.name == "buttonColor" {
            if let payload = message.body as? [String: Any],
               let hex = payload["color"] as? String, color(fromHex: hex) != nil {
                let appearance = payload["appearance"] as? String == "dark" ? "dark" : "light"
                let kind = message.name == "themeBackground" ? "background" : (message.name == "buttonColor" ? "buttonColor" : "heroCardColor")
                UserDefaults.standard.set(hex, forKey: "youyou.\(kind).\(appearance)")
                applyStoredPalette()
            }
            return
        }

        if message.name == "materialMode" {
            let payload = message.body as? [String: Any]
            let mode = (payload?["mode"] as? String) ?? "liquid"
            setCardMaterialMode(mode)
            return
        }

        if message.name == "cardGlassRects" {
            guard let rects = message.body as? [[String: Any]] else { return }
            updateNativeCardRects(rects)
            return
        }

        if message.name == "infoPage" {
            let payload = message.body as? [String: Any]
            let isOpen = (payload?["open"] as? Bool) ?? false
            tabBar.isHidden = isOpen
            return
        }

        guard message.name == "shareZip",
              let payload = message.body as? [String: Any],
              let base64 = payload["base64"] as? String,
              let data = Data(base64Encoded: base64) else { return }

        let rawName = (payload["fileName"] as? String) ?? "优优LUI图标包.zip"
        let safeName = rawName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let fileName = safeName.lowercased().hasSuffix(".zip") ? safeName : safeName + ".zip"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: url, options: .atomic)
            presentShareSheet(fileURL: url)
        } catch {
            let alert = UIAlertController(title: "分享失败", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    private func presentShareSheet(fileURL: URL) {
        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        activity.view.accessibilityIdentifier = "zipShareSheet"
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 40, width: 1, height: 1)
        }
        present(activity, animated: true)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if url.isFileURL || url.scheme == "about" {
            decisionHandler(.allow)
            return
        }

        if let scheme = url.scheme?.lowercased(), ["http", "https", "mqq", "weixin"].contains(scheme) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, !url.isFileURL {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        return nil
    }
}



/// Search keeps the current WebKit page visible and follows the keyboard.
private final class NativeSearchOverlayView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let target = super.hitTest(point, with: event)
        return target === self ? nil : target
    }
}

private final class LUIYoSearchViewController: UIViewController, UITextFieldDelegate {
    var query = ""
    var placeholder = "搜索"
    var themeFont: UIFont? { didSet { if isViewLoaded { searchField.font = themeFont?.withSize(16) ?? .systemFont(ofSize: 16) } } }
    var onSearch: ((String) -> Void)?
    var onClose: (() -> Void)?
    var onLayout: (() -> Void)?
    var backgroundImage: UIImage?
    let searchField = UITextField()

    override func loadView() { view = NativeSearchOverlayView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) { effect = UIGlassEffect() }
        else { effect = UIBlurEffect(style: .systemMaterial) }
        let inputSurface = UIVisualEffectView(effect: effect)
        if #available(iOS 26.0, *) {
            inputSurface.cornerConfiguration = .uniformCorners(radius: .fixed(22))
        } else {
            inputSurface.layer.cornerRadius = 22
            inputSurface.clipsToBounds = true
        }
        searchField.placeholder = placeholder
        searchField.text = query
        searchField.font = themeFont?.withSize(16) ?? .systemFont(ofSize: 16)
        searchField.delegate = self
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.backgroundColor = .clear
        searchField.borderStyle = .none
        searchField.accessibilityIdentifier = "bottomSearchField"
        searchField.enablesReturnKeyAutomatically = false
        searchField.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = .label
        icon.contentMode = .scaleAspectFit
        icon.isAccessibilityElement = false
        let close = UIButton(type: .system)
        let symbol = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        if #available(iOS 26.0, *) {
            var configuration = UIButton.Configuration.glass()
            configuration.image = nil
            configuration.cornerStyle = .capsule
            close.configuration = configuration
        } else {
            close.setImage(nil, for: .normal)
            close.backgroundColor = .tertiarySystemFill
            close.layer.cornerRadius = 22
        }
        let closeIcon = UIImageView(image: UIImage(systemName: "xmark", withConfiguration: symbol))
        closeIcon.contentMode = .scaleAspectFit
        closeIcon.tintColor = .label
        closeIcon.isUserInteractionEnabled = false
        closeIcon.isAccessibilityElement = false
        closeIcon.translatesAutoresizingMaskIntoConstraints = false
        close.addSubview(closeIcon)
        close.tintColor = .label
        close.accessibilityIdentifier = "bottomSearchClose"
        close.accessibilityLabel = "关闭搜索"
        close.addAction(UIAction { [weak self] _ in self?.closeSearch() }, for: .touchUpInside)
        for control in [inputSurface, close] {
            control.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(control)
        }
        for control in [icon, searchField] {
            control.translatesAutoresizingMaskIntoConstraints = false
            inputSurface.contentView.addSubview(control)
        }
        let keyboardBottom = inputSurface.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        keyboardBottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            keyboardBottom,
            inputSurface.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -90),
            inputSurface.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            inputSurface.heightAnchor.constraint(equalToConstant: 44),
            close.leadingAnchor.constraint(equalTo: inputSurface.trailingAnchor, constant: 10),
            close.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            close.centerYAnchor.constraint(equalTo: inputSurface.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            closeIcon.widthAnchor.constraint(equalToConstant: 20),
            closeIcon.heightAnchor.constraint(equalToConstant: 20),
            closeIcon.centerXAnchor.constraint(equalTo: close.centerXAnchor),
            closeIcon.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            icon.leadingAnchor.constraint(equalTo: inputSurface.contentView.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: inputSurface.contentView.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            searchField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: inputSurface.contentView.trailingAnchor, constant: -16),
            searchField.topAnchor.constraint(equalTo: inputSurface.contentView.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: inputSurface.contentView.bottomAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchField.becomeFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed { closeSearch() }
    }

    private func closeSearch() {
        searchField.resignFirstResponder()
        let completion = onClose
        onClose = nil
        completion?()
    }

    @objc private func queryChanged() { onSearch?(searchField.text ?? "") }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onSearch?(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }
}
