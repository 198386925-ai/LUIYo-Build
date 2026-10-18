import SwiftUI
import UIKit

/// Tracks whether home has been shown (skip animation on first launch)
private var hasShownHomeOnce = false

extension MainShellViewController {
    /// Seats the shared web view inside the selected tab and keeps the native
    /// homepage on top of it when it is the active page.
    func keepContentBelowNativeBar() {
        guard isViewLoaded, let webView, let parent = selectedViewController, let host = parent.view else { return }
        // Content belongs to the selected tab. UIKit keeps its native floating
        // bar above this page and propagates the page's safe-area insets.
        if webView.superview !== host {
            UIView.performWithoutAnimation {
                webView.isHidden = true
                NSLayoutConstraint.deactivate(webHostConstraints)
                webView.removeFromSuperview()
                host.insertSubview(webView, at: 0)
                webView.translatesAutoresizingMaskIntoConstraints = false
                webHostConstraints = [
                    webView.topAnchor.constraint(equalTo: host.topAnchor),
                    webView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                    webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                    webView.trailingAnchor.constraint(equalTo: host.trailingAnchor)
                ]
                NSLayoutConstraint.activate(webHostConstraints)
                // Don't force layout here - it can interfere with tab bar layout
                // during switch. The constraints apply on the next natural pass.
                if !suppressWebViewReveal { webView.isHidden = false }
            }
        }
        attachNativeHome(to: parent, host: host)
        let scroll = activePage == .home ? (nativeHomeScrollView ?? webView.scrollView) : webView.scrollView
        if boundScrollViews[ObjectIdentifier(parent)] !== scroll {
            if #available(iOS 18.0, *) { parent.setContentScrollView(scroll, for: .bottom) }
            boundScrollViews[ObjectIdentifier(parent)] = scroll
        }
    }

    /// Publishes the floating bar's top edge to the page (it drives `--native-tab-top`).
    func updateLayoutMetrics(force: Bool = false) {
        guard activeSearchController == nil, let webView, tabBar.frame.minY > 0 else { return }
        let top = tabBar.convert(tabBar.bounds, to: webView).minY
        guard force || abs(top - reportedTabTop) > 0.5 else { return }
        reportedTabTop = top
        evaluate("window.__setNativeTabTop?.(" + String(describing: top) + ")")
    }

    func updatePageScroll(_ page: ShellPage) {
        activePage = page
        keepContentBelowNativeBar()
        webView.scrollView.showsVerticalScrollIndicator = page != .settings
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.alwaysBounceVertical = page != .settings
    }

    /// The homepage is a SwiftUI overlay; other pages show the live WebKit content.
    private func attachNativeHome(to parent: UIViewController, host: UIView) {
        let visible = activePage == .home && (activeSearchController == nil || activeSearchPage == "home")
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
            let controller = UIHostingController(rootView: LUIYoNativeHome(model: homeModel))
            controller.view.backgroundColor = backgroundImageView.image == nil ? view.backgroundColor : .clear
            nativeHomeHost = controller
        }
        guard let controller = nativeHomeHost else { return }
        if controller.parent == nil {
            parent.addChild(controller)
            host.addSubview(controller.view)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            nativeHomeConstraints = [
                controller.view.topAnchor.constraint(equalTo: host.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                controller.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: host.trailingAnchor)
            ]
            NSLayoutConstraint.activate(nativeHomeConstraints)
            controller.didMove(toParent: parent)
        }
        controller.view.isHidden = !visible
        controller.view.accessibilityElementsHidden = !visible
        // Trigger home fade on tab switches (skip initial launch)
        if visible {
            if !hasShownHomeOnce {
                hasShownHomeOnce = true
            } else {
                homeModel.homeAppearCount += 1
            }
        }

    }
}
