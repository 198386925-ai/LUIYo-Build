import UIKit

extension MainShellViewController {
    /// Persists and applies the bottom-search entry visibility.
    func setBottomSearchEnabled(_ enabled: Bool) {
        preferences.bottomSearchEnabled = enabled
        bottomSearchEnabled = enabled
        refreshTabItems()
    }

    /// Rebuilds the tab bar. Called whenever search visibility or layout changes.
    func refreshTabItems() {
        if #available(iOS 18.0, *) {
            // UIKit owns the complete bar geometry, including the detached
            // search surface. Never shrink the bar or position a glass button
            // using separate width, height or safe-area offsets.
            // A UITab owns its provider's UIViewController. The old implementation
            // returned the SAME pageControllers every time tabs were rebuilt.
            // UIKit asserts inside -[UITab viewController] when an already-owned
            // controller is handed to a newly created UITab (see device .ips).
            // Give each newly-created tab its own, never-before-owned controller.
            var nativeTabs = pageTabs.enumerated().map { index, item -> UITab in
                let identifier = "page.\(index)"
                if let existing = retainedTabs[identifier] as? UITab { return existing }
                let controller = UIViewController()
                controller.view.backgroundColor = .clear
                let tab = UITab(title: item.title ?? "", image: item.image, identifier: identifier) { _ in controller }
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
            setViewControllers(pageControllers + (bottomSearchEnabled ? [searchTabController] : []), animated: false)
        }
        // Keep the shared WebKit document alive while native tabs change.
        selectPage(activePage)
        for (index, item) in (tabBar.items ?? []).enumerated() { item.tag = index }
        applyFont(fontController.font)
        keepContentBelowNativeBar()
        view.setNeedsLayout()
        updateLayoutMetrics(force: true)
    }

    /// Selects a page without triggering navigation (used while rebuilding tabs).
    func selectPage(_ page: ShellPage) {
        activePage = page
        if #available(iOS 18.0, *) {
            selectedTab = tabs.first { $0.identifier == page.tabIdentifier }
        } else if pageControllers.indices.contains(page.rawValue) {
            selectedViewController = pageControllers[page.rawValue]
        }
        keepContentBelowNativeBar()
    }

    /// User tapped a content tab. Returns false when the shell handles the switch itself.
    func preparePageSelection(_ tag: Int) -> Bool {
        let page = ShellPage(clamping: tag)
        guard nativeHomeReady, page != activePage else { return true }
        // Root cause of the tab-switch flash: the old code moved the shared
        // WKWebView into the new tab and revealed it BEFORE the async
        // appNavTo() JS swapped the page, so the old page's DOM showed through
        // the new tab for a few frames. Fix: keep the webView hidden until the
        // new page's DOM is live, then seat it and reveal.
        pageSwitchGeneration += 1
        let generation = pageSwitchGeneration
        switchingPage = true
        suppressWebViewReveal = true
        // Don't hide or fade out at start - keep old content visible.
        // The smooth fade-in at the end will mask the transition.
        UIView.performWithoutAnimation {
            self.selectPage(page)
            self.updatePageScroll(page)
        }
        keepContentBelowNativeBar()
        updateLayoutMetrics(force: true)
        evaluate("appNavTo('" + page.name + "');window.__syncNativeCardGlass?.();") { [weak self] _, _ in
            guard let self, self.pageSwitchGeneration == generation else { return }
            // Wait a tick for render, then reveal.
            DispatchQueue.main.async {
                guard self.pageSwitchGeneration == generation else { return }
                self.revealWebViewAfterSwitch(to: page)
            }
        }
        return false
    }

    private func revealWebViewAfterSwitch(to page: ShellPage) {
        if page == .home {
            // Homepage is native: fade WebView out, keep hidden.
            UIView.animate(withDuration: 0.3, animations: {
                self.webView?.alpha = 0.0
            }, completion: { [weak self] _ in
                self?.webView?.isHidden = true
            })
        } else {
            // Web pages: gradual fade-in for smooth appearance.
            self.webView?.isHidden = false
            self.webView?.alpha = 0.0
            UIView.animate(withDuration: 0.35, delay: 0.05, options: .curveEaseOut, animations: {
                self.webView?.alpha = 1.0
            }, completion: nil)
        }
        switchingPage = false
        suppressWebViewReveal = false
    }

    /// Navigates the shared page after a tab change driven by UIKit.
    func navigateFromNativeTab(_ tag: Int) {
        let page = ShellPage(clamping: tag)
        activePage = page
        updatePageScroll(page)
        guard nativeHomeReady else {
            keepContentBelowNativeBar()
            return
        }
        // Switch content FIRST via JS (instant CSS toggle), then move WebView.
        // This prevents ghosting: the WebView already shows the right page when moved.
        evaluate("appNavTo(\'" + page.name + "\')") { [weak self] _, _ in
            DispatchQueue.main.async { self?.keepContentBelowNativeBar() }
        }
    }

    func setScrollMinimize(_ enabled: Bool) {
        scrollMinimizeEnabled = enabled
        preferences.minimizeBottomBar = enabled
        if #available(iOS 26.0, *) { tabBarMinimizeBehavior = enabled ? .onScrollDown : .never }
    }
}
