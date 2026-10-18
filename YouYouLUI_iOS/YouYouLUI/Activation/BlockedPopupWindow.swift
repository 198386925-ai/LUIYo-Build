import UIKit
import WebKit

/// Full-screen, non-dismissable popup for banned devices and disabled builds.
/// It lives in its own window so it covers the home page and the tab bar, and
/// uses the shipped HTML design so it picks up the custom theme font.
/// Confirming exits the process — the user cannot stay in the app.
final class BlockedPopupWindow: NSObject, WKScriptMessageHandler {
    private var window: UIWindow?
    private static var current: BlockedPopupWindow?

    static func show(title: String,
                     description: String,
                     reasonLabel: String,
                     reason: String,
                     fontName: String?) {
        // Keep a strong reference for the lifetime of the popup.
        let popup = BlockedPopupWindow()
        current = popup
        popup.present(title: title, description: description, reasonLabel: reasonLabel,
                      reason: reason, fontName: fontName)
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func present(title: String, description: String, reasonLabel: String, reason: String, fontName: String?) {
        let safeTitle = escaped(title)
        let safeDescription = escaped(description)
        let safeLabel = escaped(reasonLabel)
        let safeReason = escaped(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : reason)
        let fontCSS: String = {
            guard let name = fontName, !name.isEmpty else { return "" }
            let safe = name.replacingOccurrences(of: "'", with: "")
            return "font-family:'" + safe + "',-apple-system,'PingFang SC',sans-serif;"
        }()
        let html = """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
        <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;min-height:100vh;padding:24px;\(fontCSS)}
        #card{width:320px;max-width:100%;background:#fff;border-radius:24px;padding:20px 20px 18px;box-shadow:0 12px 40px rgba(0,0,0,.18);text-align:center;\(fontCSS)}
        .icon{width:60px;height:60px;margin:0 auto 10px;border-radius:18px;background:#FFF0E6;display:flex;align-items:center;justify-content:center}
        .title{font-size:19px;font-weight:700;color:#1A1A1A;margin-bottom:4px}
        .desc{font-size:14px;line-height:1.5;color:#999;margin-bottom:10px}
        .reasonbox{text-align:left;background:#FAFAFA;border-radius:12px;padding:10px 12px;margin-bottom:12px}
        .rlabel{font-size:12px;color:#BBB;margin-bottom:2px}
        .rvalue{font-size:14px;color:#333;font-weight:500}
        #confirm{width:100%;border:none;border-radius:14px;background:#FF7A00;color:#fff;font-size:16px;font-weight:600;padding:12px 0;\(fontCSS)}
        </style></head>
        <body>
        <div id="card">
        <div class="icon"><svg viewBox="0 0 24 24" width="32" height="32" xmlns="http://www.w3.org/2000/svg"><path d="M12 2 4 5v6c0 5 3.4 8.5 8 11 4.6-2.5 8-6 8-11V5l-8-3z" fill="#FF7A00"/><path d="M9.5 12l1.8 1.8L15 10" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/></svg></div>
        <div class="title">\(safeTitle)</div>
        <div class="desc">\(safeDescription)</div>
        <div class="reasonbox"><div class="rlabel">\(safeLabel)</div><div class="rvalue">\(safeReason)</div></div>
        <button id="confirm">立即确认</button>
        </div>
        <script>
        (function(){
          var card=document.getElementById('card');
          try{card.animate([{transform:'translateY(90px) scale(.96)',opacity:0},{transform:'translateY(0) scale(1)',opacity:1}],{duration:420,easing:'cubic-bezier(.2,.85,.3,1.1)'});}catch(e){}
          document.getElementById('confirm').addEventListener('click',function(){
            try{window.webkit.messageHandlers.blockedPopup.postMessage('confirm');}catch(e){}
          });
        })();
        </script>
        </body></html>
        """

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: BridgeMessage.blockedPopup.name)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.loadHTMLString(html, baseURL: nil)

        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: host.view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.view.trailingAnchor)
        ])
        window.windowLevel = UIWindow.Level.alert + 1
        window.makeKeyAndVisible()
        self.window = window
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == BridgeMessage.blockedPopup.name,
              let body = message.body as? String, body == "confirm" else { return }
        exit(0)
    }
}
