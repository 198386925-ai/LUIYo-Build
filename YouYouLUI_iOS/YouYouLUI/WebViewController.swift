import UIKit
import WebKit
import CoreText

/// Native material shell.
/// iOS 26+ uses UIKit Liquid Glass; older systems use UIKit systemMaterial blur.
/// HTML is content-only and never draws blur/glass itself.
final class WebViewController: UITabBarController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UITabBarControllerDelegate {
    private var webView: WKWebView!
    private var isAuthorized = false
    var onActivationRequested: (() -> Void)?
    var onLicenseSubmitted: ((String) -> Void)?
    var onDeviceIdentificationRequested: (() -> Void)?
    var onPageChanged: ((String) -> Void)?
    private var deviceStatusMessage = "正在登记设备…"

    func setDeviceInfo(_ message: String) {
        deviceStatusMessage = message
        syncDeviceInfo()
    }

    private func syncDeviceInfo() {
        guard isViewLoaded, let webView, let data = try? JSONSerialization.data(withJSONObject: [deviceStatusMessage]),
              let args = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__luiyoSetDeviceInfo?.(..." + args + ")")
    }
    private var authorizationMessage = "未激活 · 仅可浏览"
    private var authorizationBusy = false

    func setAuthorization(_ allowed: Bool, message: String? = nil, busy: Bool = false) {
        isAuthorized = allowed
        authorizationMessage = message ?? (allowed ? "已激活 · 全部功能可用" : "未激活 · 仅可浏览")
        authorizationBusy = busy
        syncAuthorization()
    }

    private func syncAuthorization() {
        guard isViewLoaded, let webView else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: [isAuthorized, authorizationMessage, authorizationBusy]),
              let args = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__luiyoSetAuthorized?.(..." + args + ")")
        syncDeviceInfo()
    }
    private var pageItems: [UITabBarItem] = []
    private var pageControllers: [UIViewController] = []
    private let searchController = UIViewController()
    private var bottomSearchEnabled = false
    private var activePageTag = 0
    private var separateSearch = false
    private weak var activeSearchPageController: LUIYoSearchViewController?
    private var webHostConstraints: [NSLayoutConstraint] = []
    private let backgroundImageView = UIImageView()
    private var scrollMinimizeEnabled = false
    private var nativePageName = "home"
    private var openingSearch = false
    private var activeSearchPage = "home"
    private var themeFont: UIFont?
    private var themeFontData: Data?
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
    private var nativeSegmentStyles: [String: UIUserInterfaceStyle] = [:]
    private var nativeSelectedCapsules: [String: UIView] = [:]
    private var scrollOffsetObservation: NSKeyValueObservation?
    private enum CardMaterialMode { case liquid, blur }
    private var cardMaterialMode: CardMaterialMode = .liquid
    private var cardTintColor: UIColor = .secondarySystemGroupedBackground
    static let adaptiveBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 18.0/255.0, green: 18.0/255.0, blue: 20.0/255.0, alpha: 1)
            : UIColor(red: 244.0/255.0, green: 242.0/255.0, blue: 238.0/255.0, alpha: 1)
    }

    private static let activationPreviewScript = #"""
    (() => {
      let authorized = false;
      const css = document.createElement('style');
      css.textContent = `.luiyoActivationEntry{margin:0 0 14px;padding:17px 18px;border:0;border-radius:28px;background:var(--card-color,#fff)}
        body.native-card-glass .luiyoActivationEntry{background:transparent!important;box-shadow:none!important}
        .luiyoActivationEntry strong{display:block;font-size:15px}.luiyoActivationEntry small{display:block;margin-top:5px;color:var(--muted,#8b8f98);font-size:12px}
        .luiyoActivationForm{display:flex;gap:8px;margin-top:14px;align-items:center}.luiyoActivationForm[hidden]{display:none!important}
        #luiyoLicenseCode{flex:1;min-width:0;height:44px;box-sizing:border-box;padding:0 12px;border:1px solid rgba(130,130,140,.25);border-radius:14px;background:transparent;color:inherit;font-size:14px}
        .luiyoDeviceInfo{margin-top:15px;padding-top:12px;border-top:1px solid rgba(130,130,140,.18)}.luiyoDeviceInfo p{font-size:11px;line-height:1.5;color:var(--muted,#8b8f98);margin:6px 0}.luiyoDeviceInfo button{font-size:12px;padding:8px 12px;border:1px solid rgba(130,130,140,.25);border-radius:12px;background:transparent;color:inherit}#luiyoDeviceState{word-break:break-all}
        #luiyoLicenseSubmit{height:44px;border:0;border-radius:14px;padding:0 14px;background:#6968e8;color:white;font-weight:600;white-space:nowrap}`;
      document.head.appendChild(css);
      const settings = document.getElementById('settingsTarget');
      if (settings) {
        const box = document.createElement('section');
        box.className = 'luiyoActivationEntry';box.id='luiyoActivationCard';
        box.innerHTML = '<strong>激活授权</strong><small id="luiyoAuthState">未激活 · 仅可浏览</small><form class="luiyoActivationForm" id="luiyoActivationForm"><input id="luiyoLicenseCode" aria-label="卡密" placeholder="输入卡密" autocomplete="one-time-code" autocapitalize="characters" spellcheck="false"><button id="luiyoLicenseSubmit" type="submit">激活</button></form><div class="luiyoDeviceInfo"><small id="luiyoDeviceState">正在登记设备…</small><p>打开 App 时会登记设备编号、系统版本和在线状态，不包含照片和卡密内容。UDID 优先读取签名文件中的唯一设备号码；无法确定时可选手动获取，和授权状态分开。</p><button type="button" id="luiyoGetUDID">获取设备 UDID</button></div>';
        settings.querySelector('.settingsHead')?.insertAdjacentElement('afterend', box);
        box.querySelector('#luiyoGetUDID').addEventListener('click',()=>window.webkit?.messageHandlers?.deviceIdentification?.postMessage({}));
        box.querySelector('form').addEventListener('submit', e => {
          e.preventDefault();const code=box.querySelector('input').value.trim();
          if(code)window.webkit?.messageHandlers?.activationSubmit?.postMessage({code});
        });
      }
      window.__luiyoSetDeviceInfo = message => {const state=document.getElementById('luiyoDeviceState');if(state)state.textContent=message};
      window.__luiyoSetAuthorized = (enabled,message,busy=false) => {
        authorized = !!enabled;
        document.documentElement.dataset.luiyoAuthorized = authorized ? 'yes' : 'no';
        const state=document.getElementById('luiyoAuthState'), form=document.getElementById('luiyoActivationForm');
        if(state)state.textContent=message||(authorized?'已激活 · 全部功能可用':'未激活 · 仅可浏览');
        if(form){form.hidden=authorized;const field=form.querySelector('input'),button=form.querySelector('button');field.disabled=busy;button.disabled=busy;button.textContent=busy?'验证中…':'激活';if(authorized){field.blur();field.value=''}}
        window.__syncNativeCardGlass?.();
      };
      function allowedTarget(t) {
        if (!(t instanceof Element)) return false;
        return !!t.closest('#luiyoActivationCard, .appBottomNav, summary, .categorytabs, .nativeInfoHeader');
      }
      function protect(e) {
        if (authorized || allowedTarget(e.target)) return;
        const t = e.target;
        const interactive = t instanceof Element && t.closest('button,input,textarea,select,label,a,[contenteditable],[role="button"]');
        if (!interactive) return;
        e.preventDefault();e.stopImmediatePropagation();
      }
      ['click','change','input','submit','keydown','drop','paste'].forEach(t => document.addEventListener(t, protect, true));
      window.__luiyoSetAuthorized(false);
    })();
    """#

    override func loadView() {
        super.loadView()
        let rootView = view!
        // Global default app background: #F4F2EE on every page.
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
        backgroundImageView.image = UIImage(contentsOfFile: nativeBackgroundURL.path)
        glassContainer.backgroundColor = .clear
        glassContainer.isUserInteractionEnabled = false
        glassContainer.accessibilityElementsHidden = true

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(self, name: "shareZip")
        configuration.userContentController.add(self, name: "infoPage")
        configuration.userContentController.add(self, name: "materialMode")
        configuration.userContentController.add(self, name: "cardGlassRects")
        configuration.userContentController.add(self, name: "themeBackground")
        configuration.userContentController.add(self, name: "cardColor")
        configuration.userContentController.add(self, name: "buttonColor")
        configuration.userContentController.add(self, name: "appearanceMode")
        configuration.userContentController.add(self, name: "themeFont")
        configuration.userContentController.add(self, name: "zipName")
        configuration.userContentController.add(self, name: "backgroundImage")
        configuration.userContentController.add(self, name: "minimizeBottomBar")
        configuration.userContentController.add(self, name: "pageState")
        configuration.userContentController.add(self, name: "bottomSearch")
        configuration.userContentController.add(self, name: "activationOpen")
        configuration.userContentController.add(self, name: "activationSubmit")
        configuration.userContentController.add(self, name: "deviceIdentification")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.activationPreviewScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true))

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
        scrollOffsetObservation?.invalidate()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "shareZip")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "infoPage")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "materialMode")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "cardGlassRects")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "themeBackground")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "cardColor")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "buttonColor")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "appearanceMode")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "themeFont")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "zipName")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "backgroundImage")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "minimizeBottomBar")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "pageState")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "bottomSearch")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "activationOpen")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "activationSubmit")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "deviceIdentification")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncAuthorization()
        updateLayoutMetrics(force: true)
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
                if rawScenario == "preview-inline-auth" {
                    self.webView.evaluateJavaScript("fillFile=new File([Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAFklEQVR4nGNUqPj1nwEPYMInOXwUAACm9AKhD318TgAAAABJRU5ErkJggg=='),c=>c.charCodeAt(0))],'test.png',{type:'image/png'})")
                }
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
            if ('\(page)' === 'home') document.querySelectorAll('.categorytabs button')[1].click();
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
                result["selectedCapsuleAlphas"] = self.nativeSelectedCapsules.values.map { Double($0.backgroundColor?.cgColor.alpha ?? 1) }
                result["pickerStyles"] = self.nativeSegments.map { key, segment -> [String: Any] in
                    let attributes = segment.titleTextAttributes(for: .selected) ?? [:]
                    let text = attributes[.foregroundColor] as? UIColor
                    return ["kind": self.cardSpecs[key]?["segment"] as? String ?? "", "selected": segment.selectedSegmentIndex,
                        "track": segment.superview?.backgroundColor?.cgColor.components?.map { Double($0) } ?? [],
                        "capsule": self.nativeSelectedCapsules[key]?.backgroundColor?.cgColor.components?.map { Double($0) } ?? [],
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
                let controller = UIViewController()
                controller.view.backgroundColor = .clear
                return UITab(title: item.title ?? "", image: item.image,
                             identifier: "page.\(index)") { _ in controller }
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
            tabs = nativeTabs
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
        guard let webView, isViewLoaded else { return }
        let host: UIView
        if let search = activeSearchPageController {
            search.loadViewIfNeeded()
            host = search.contentHost
        } else if let selectedHost = selectedViewController?.view {
            host = selectedHost
        } else { return }
        // UIKit inserts selected tab content above UITabBarController.view's
        // custom subviews. Hosting WKWebView on the controller root therefore
        // covers the native floating bar and steals all its touches.
        // Place WebKit inside the selected tab's content view instead.
        if webView.superview !== host {
            NSLayoutConstraint.deactivate(webHostConstraints)
            webView.removeFromSuperview()
            host.addSubview(webView)
            webView.translatesAutoresizingMaskIntoConstraints = false
            webHostConstraints = [
                webView.topAnchor.constraint(equalTo: host.topAnchor),
                webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
            ]
            NSLayoutConstraint.activate(webHostConstraints)
            if activeSearchPageController == nil, #available(iOS 15.0, *) { selectedViewController?.setContentScrollView(webView.scrollView, for: .bottom) }
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
        return true
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        if tab is UISearchTab || tab.identifier == "action.search" {
            // Both native entries open the same full-screen search page.
            // Keep the content tab selected so closing search restores it.
            presentBottomSearch()
            return false
        }
        return true
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        guard let tag = Int(selectedTab.identifier.replacingOccurrences(of: "page.", with: "")) else { return }
        navigateFromNativeTab(tag)
    }

    private func presentBottomSearch() {
        guard isAuthorized else {
            showAuthorizationRequired()
            return
        }
        guard bottomSearchEnabled, !openingSearch, presentedViewController == nil else { return }
        openingSearch = true
        webView.evaluateJavaScript("window.__bottomSearchState?.()") { [weak self] value, _ in
            guard let self else { return }
            self.openingSearch = false
            guard self.presentedViewController == nil else { return }
            let state = value as? [String: Any] ?? [:]
            self.activeSearchPage = state["page"] as? String ?? "home"
            let page = LUIYoSearchViewController()
            page.query = state["query"] as? String ?? ""
            page.backgroundImage = self.backgroundImageView.image
            page.placeholder = state["placeholder"] as? String ?? "搜索"
            page.onSearch = { [weak self] query in self?.applyBottomSearch(query) }
            page.onClose = { [weak self] in
                guard let self else { return }
                self.webView.evaluateJavaScript("window.__clearBottomSearch?.()")
                self.activeSearchPageController = nil
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
            page.modalPresentationStyle = .fullScreen
            self.activeSearchPageController = page
            self.keepContentBelowNativeBar()
            self.present(page, animated: false)
        }
    }

    private func applyBottomSearch(_ query: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: [query, activeSearchPage]),
              let arguments = String(data: data, encoding: .utf8) else { return }
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

    private func navigateFromNativeTab(_ tag: Int) {
        activePageTag = tag
        keepContentBelowNativeBar()
        let page: String
        switch tag {
        case 1: page = "rules"
        case 2: page = "settings"
        default: page = "home"
        }
        webView.evaluateJavaScript("appNavTo(\'" + page + "\')")
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
        view.backgroundColor = storedColor("background", lightDefault: "#F4F2EE", darkDefault: "#121214")
        cardTintColor = storedColor("cardColor", lightDefault: "#FFFFFF", darkDefault: "#1C1C1E")
        updateNativeCardTint()
        renderVisibleNativeMaterials()
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
                return UIGlassEffect()
            }
            return UIBlurEffect(style: .systemMaterial)
        case .blur:
            return UIBlurEffect(style: .systemMaterial)
        }
    }

    private func setCardMaterialMode(_ rawMode: String) {
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
        cardTintColor = color
        updateNativeCardTint()
    }

    private func effect(for spec: [String: Any]) -> UIVisualEffect {
        if (spec["forceLiquid"] as? Bool) == true, #available(iOS 26.0, *) {
            return UIGlassEffect()
        }
        return nativeCardEffect()
    }

    private func applyTint(to surface: UIVisualEffectView, spec: [String: Any]) {
        let isSegment = (spec["segment"] as? String) != nil
        let isAction = (spec["homeControl"] as? Bool) == true
        let alpha: CGFloat = isAction ? (cardMaterialMode == .blur ? 0.70 : 0.22)
            : (cardMaterialMode == .blur ? 0.24 : 0.10)
        surface.contentView.backgroundColor = isSegment ? .clear : cardTintColor.withAlphaComponent(alpha)
    }

    private func updateNativeCardTint() {
        for (key, surface) in cardMaterialViews {
            applyTint(to: surface, spec: cardSpecs[key] ?? [:])
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Remove extra layer shadows without replacing native system glass.
        tabBar.layer.shadowOpacity = 0
        tabBar.layer.shadowRadius = 0
        tabBar.layer.shadowColor = UIColor.clear.cgColor
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

    private func updatePageScroll(_ page: String) {
        nativePageName = page
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
        if themeFontData == data { return true }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return false }
        themeFont = CTFontCreateWithFontDescriptor(descriptor, 10, nil) as UIFont
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
        renderVisibleNativeMaterials()
    }

    private func configureSegment(in surface: UIVisualEffectView, key: String, spec: [String: Any]) {
        guard let kind = spec["segment"] as? String else { return }
        let titles = kind == "category" ? ["LiquidUI", "原版微信"]
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
            surface.contentView.addSubview(segment)
            nativeSegments[key] = segment
        }
        // The track follows the card tint with a slight tonal adjustment so
        // the selected capsule remains distinct even when both colors are white.
        segment.backgroundColor = .clear
        let dark = traitCollection.userInterfaceStyle == .dark
        let card = storedColor("cardColor", lightDefault: "#FFFFFF", darkDefault: "#1C1C1E").resolvedColor(with: traitCollection)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        card.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let tone: CGFloat = dark ? 1.4 : 0.9
        surface.contentView.backgroundColor = UIColor(red: min(1, red * tone), green: min(1, green * tone), blue: min(1, blue * tone), alpha: 0.6)
        // All three pickers share one translucent track and selected capsule.
        // Clear the built-in background so UIKit doesn't stack a darker pill.
        if nativeSegmentStyles[key] != traitCollection.userInterfaceStyle {
            let clear = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
            segment.setBackgroundImage(clear, for: .normal, barMetrics: .default)
            segment.setBackgroundImage(clear, for: .selected, barMetrics: .default)
            segment.setDividerImage(clear, forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)
            nativeSegmentStyles[key] = traitCollection.userInterfaceStyle
        }
        if nativeSelectedCapsules[key] == nil {
            let capsule = UIView()
            capsule.isUserInteractionEnabled = false
            surface.contentView.insertSubview(capsule, belowSubview: segment)
            nativeSelectedCapsules[key] = capsule
        }
        let selectedColor = storedColor("buttonColor", lightDefault: "#FFFFFF", darkDefault: "#FFFFFF").resolvedColor(with: traitCollection)
        nativeSelectedCapsules[key]?.backgroundColor = selectedColor
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
        if let capsule = nativeSelectedCapsules[key] {
            let width = surface.bounds.width / CGFloat(segment.numberOfSegments)
            capsule.frame = CGRect(x: CGFloat(selected) * width + 2, y: 2,
                width: width - 4, height: surface.bounds.height - 4)
            capsule.layer.cornerRadius = capsule.bounds.height / 2
            capsule.clipsToBounds = true
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
                    host.clipsToBounds = false
                    glassContainer.addSubview(host)
                    host.addSubview(surface)
                    cardMaterialHosts[key] = host
                    cardMaterialViews[key] = surface
                }
                cardMaterialHosts[key]?.isHidden = false
                cardMaterialHosts[key]?.frame = clip
                // Full-size glass must keep an unclipped ancestor for native refraction.
                // Clip only while an expanding fold actually crops its child.
                cardMaterialHosts[key]?.clipsToBounds = clip.minX > frame.minX + 0.5 || clip.minY > frame.minY + 0.5
                    || clip.maxX < frame.maxX - 0.5 || clip.maxY < frame.maxY - 0.5
                surface.frame = CGRect(x: frame.minX - clip.minX, y: frame.minY - clip.minY, width: frame.width, height: frame.height)
                let requested = CGFloat((spec["radius"] as? NSNumber)?.doubleValue ?? 24)
                // CSS uses 999px for pills; CALayer needs the actual finite radius.
                surface.layer.cornerRadius = min(max(0, requested), min(frame.width, frame.height) / 2)
                applyTint(to: surface, spec: spec)
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
            nativeSegments.removeValue(forKey: key)
            nativeSegmentStyles.removeValue(forKey: key)
            nativeSelectedCapsules.removeValue(forKey: key)?.removeFromSuperview()
        }
        cardDocumentFrames = frames
        cardSpecs = specs
        cardOrder = order
        renderVisibleNativeMaterials()
    }

    private func showAuthorizationRequired() {
        let alert = UIAlertController(title: "尚未激活", message: "当前可以浏览页面。前往设置输入卡密，激活后才可使用功能。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
        alert.addAction(UIAlertAction(title: "前往设置", style: .default) { [weak self] _ in
            self?.selectNativePage(2)
            self?.webView.evaluateJavaScript("appNavTo('settings')")
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

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        if message.name == "deviceIdentification" {
            onDeviceIdentificationRequested?()
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
        if !isAuthorized && !["pageState", "infoPage", "cardGlassRects"].contains(message.name) { return }
        if message.name == "pageState" {
            if let payload = message.body as? [String: Any] {
                let page = payload["page"] as? String ?? "home"
                updatePageScroll(page)
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
            guard let payload = message.body as? [String: Any] else { return }
            if payload["reset"] as? Bool == true {
                backgroundImageView.image = nil
                try? FileManager.default.removeItem(at: nativeBackgroundURL)
            } else if let base64 = payload["data"] as? String, let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
                backgroundImageView.image = image
                try? FileManager.default.createDirectory(at: nativeBackgroundURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: nativeBackgroundURL, options: .atomic)
            }
            return
        }
        if message.name == "bottomSearch" {
            guard let payload = message.body as? [String: Any] else { return }
            if let layout = payload["layout"] as? String { setBottomSearchLayout(layout) }
            if let enabled = payload["enabled"] as? Bool { setBottomSearchEnabled(enabled) }
            if payload["open"] as? Bool == true { presentBottomSearch() }
            return
        }
        if message.name == "themeFont" {
            guard let payload = message.body as? [String: Any] else { return }
            if payload["reset"] as? Bool == true {
                themeFont = nil; themeFontData = nil
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

        if message.name == "themeBackground" || message.name == "cardColor" || message.name == "buttonColor" {
            if let payload = message.body as? [String: Any],
               let hex = payload["color"] as? String, color(fromHex: hex) != nil {
                let appearance = payload["appearance"] as? String == "dark" ? "dark" : "light"
                let kind = message.name == "themeBackground" ? "background" : (message.name == "buttonColor" ? "buttonColor" : "cardColor")
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
private final class LUIYoSearchViewController: UIViewController, UITextFieldDelegate {
    var query = ""
    var placeholder = "搜索"
    var onSearch: ((String) -> Void)?
    var onClose: (() -> Void)?
    var onLayout: (() -> Void)?
    var backgroundImage: UIImage?
    let contentHost = UIView()
    let searchField = UITextField()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        if let backgroundImage {
            let imageView = UIImageView(image: backgroundImage)
            imageView.frame = view.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.isUserInteractionEnabled = false
            view.addSubview(imageView)
        }
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) { effect = UIGlassEffect() }
        else { effect = UIBlurEffect(style: .systemMaterial) }
        let inputSurface = UIVisualEffectView(effect: effect)
        inputSurface.layer.cornerRadius = 22
        inputSurface.clipsToBounds = true
        searchField.placeholder = placeholder
        searchField.text = query
        searchField.font = .systemFont(ofSize: 16)
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
        close.addAction(UIAction { [weak self] _ in self?.searchField.resignFirstResponder(); self?.dismiss(animated: false) }, for: .touchUpInside)
        for control in [contentHost, inputSurface, close] {
            control.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(control)
        }
        for control in [icon, searchField] {
            control.translatesAutoresizingMaskIntoConstraints = false
            inputSurface.contentView.addSubview(control)
        }
        NSLayoutConstraint.activate([
            contentHost.topAnchor.constraint(equalTo: view.topAnchor),
            contentHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            inputSurface.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            inputSurface.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
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
        if isBeingDismissed || presentingViewController == nil { onClose?() }
    }

    @objc private func queryChanged() { onSearch?(searchField.text ?? "") }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onSearch?(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }
}
