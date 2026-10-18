import WebKit

extension MainShellViewController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        nativeHomeReady = true
        syncAuthorization()
        if isAuthorized { runNativeEngine("colors", ["values": homeModel.savedColors]) }
        runNativeEngine("state", [:])
        navigateFromNativeTab(activePage.rawValue)
        keepContentBelowNativeBar()
        updateLayoutMetrics(force: true)
        // Pre-render removed entirely: it caused race conditions where the WebView
        // got stuck showing the wrong page when the user tapped a tab mid-render.
        runSnapshotScenarioIfNeeded()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.isFileURL || url.scheme == "about" {
            decisionHandler(.allow)
            return
        }
        // External links (feedback, QQ, WeChat) open in the system, never inline.
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

// MARK: - Tab bar delegate

extension MainShellViewController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController,
                          shouldSelect viewController: UIViewController) -> Bool {
        if viewController === searchTabController {
            // Action-only item: keep the currently selected page.
            presentBottomSearch()
            return false
        }
        guard let tag = pageControllers.firstIndex(of: viewController) else { return true }
        return preparePageSelection(tag)
    }

    func tabBarController(_ tabBarController: UITabBarController,
                          didSelect viewController: UIViewController) {
        if #available(iOS 18.0, *) { return }
        if viewController === searchTabController {
            selectPage(activePage)
            presentBottomSearch()
            return
        }
        guard let tag = pageControllers.firstIndex(of: viewController) else { return }
        navigateFromNativeTab(tag)
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
        return preparePageSelection(tag)
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController,
                          didSelectTab selectedTab: UITab,
                          previousTab: UITab?) {
        guard let tag = Int(selectedTab.identifier.replacingOccurrences(of: "page.", with: "")) else { return }
        navigateFromNativeTab(tag)
    }
}
