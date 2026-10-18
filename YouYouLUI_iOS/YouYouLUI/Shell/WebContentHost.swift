import WebKit

/// Weak bridge target: WKUserContentController retains its handlers, so the
/// shell must not be retained by the web view it owns.
/// Shared store for the font scheme handler
final class FontSchemeHandlerStore {
    static let shared = FontSchemeHandlerStore()
    var handler: FontSchemeHandler?
    private init() {}
}

/// Serves the saved custom font to the web view via font://custom
final class FontSchemeHandler: NSObject, WKURLSchemeHandler {
    var fontData: Data?
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let data = fontData, let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "FontScheme", code: 404, userInfo: nil))
            return
        }
        let response = URLResponse(url: url, mimeType: "font/ttf",
                                   expectedContentLength: data.count, textEncodingName: nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: (WKScriptMessageHandler & AnyObject)?

    init(forwarding target: WKScriptMessageHandler & AnyObject) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Owns the single WKWebView: configuration, injected scripts, handler
/// registration and the bundled page load.
final class WebContentHost {
    let webView: WKWebView

    init(messageHandler: WKScriptMessageHandler & AnyObject) {
        let configuration = WKWebViewConfiguration()
        let fontHandler = FontSchemeHandler()
        configuration.setURLSchemeHandler(fontHandler, forURLScheme: "font")
        // Store for later updates (MainShellViewController will set fontData)
        FontSchemeHandlerStore.shared.handler = fontHandler
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(
            WKUserScript(source: BridgeScripts.bottomSearchBootstrap,
                         injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        for message in BridgeMessage.allCases where message != .blockedPopup {
            configuration.userContentController.add(WeakScriptHandler(forwarding: messageHandler),
                                                    name: message.name)
        }
        configuration.userContentController.addUserScript(
            WKUserScript(source: BridgeScripts.activationPreviewScript,
                         injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        if let bridge = BridgeScripts.bundled(named: "native-home-bridge", extension: "js") {
            configuration.userContentController.addUserScript(
                WKUserScript(source: bridge, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            )
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.translatesAutoresizingMaskIntoConstraints = false
        self.webView = webView
    }

    /// Loads the bundled index.html. Returns false when the resource is missing.
    @discardableResult
    func loadBundledPage() -> Bool {
        guard let webRoot = Bundle.main.url(forResource: "Web", withExtension: nil),
              let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") else {
            return false
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: webRoot)
        return true
    }

    func invalidate() {
        for message in BridgeMessage.allCases where message != .blockedPopup {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: message.name)
        }
    }
}
