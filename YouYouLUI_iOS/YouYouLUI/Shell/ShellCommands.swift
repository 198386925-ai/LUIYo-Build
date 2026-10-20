import UIKit

extension MainShellViewController {
    /// Sends a command into the shared web engine. Every mutation is gated on
    /// authorization again, because pickers return asynchronously.
    func runNativeEngine(_ action: String, _ values: [String: Any]) {
        guard ["state", "category", "search"].contains(action) || isAuthorized else {
            showAuthorizationRequired()
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: [action, values]),
              let arguments = String(data: data, encoding: .utf8) else { return }
        let script = "Promise.resolve(window.__nativeHomeCommand?.(..." + arguments
            + ")).catch(error => alert(error.message)); undefined;"
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self, let error else { return }
            let alert = UIAlertController(title: "操作失败", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            if self.presentedViewController == nil { self.present(alert, animated: true) }
        }
    }

    /// Commands raised by the native homepage.
    func handleHomeCommand(_ action: String, _ values: [String: Any]) {
        guard isAuthorized else { showAuthorizationRequired(); return }
        guard nativeHomeReady else { return }
        switch action {
        case "upload", "batch", "fillImage":
            let kind = ImagePickerCoordinator.Kind(rawValue: action) ?? .upload
            imagePicker.chooseImage(kind: kind, index: values["id"] as? Int)
        case "clear":
            AlertPresenter.confirm(title: "清空上传图片？",
                                   message: "将移除本次上传与补全图片。",
                                   confirmTitle: "清空",
                                   destructive: true,
                                   on: self) { [weak self] in
                self?.runNativeEngine("clear", [:])
            }
        case "authorize":
            showAuthorizationRequired()
        default:
            runNativeEngine(action, values)
        }
    }

    func receiveFiles(_ files: [[String: String]], kind: ImagePickerCoordinator.Kind, index: Int?) {
        var payload: [String: Any] = ["files": files, "kind": kind.rawValue]
        if let index { payload["id"] = index }
        runNativeEngine("files", payload)
    }

    func showNotice(_ text: String) {
        AlertPresenter.notice(message: text, on: self)
    }

    func showAuthorizationRequired() {
        let alert = UIAlertController(title: "尚未激活",
                                      message: "当前可以浏览页面。前往设置输入卡密，激活后才可使用功能。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
        alert.addAction(UIAlertAction(title: "前往设置", style: .default) { [weak self] _ in
            guard let self else { return }
            self.selectPage(.settings)
            self.navigateFromNativeTab(ShellPage.settings.rawValue)
        })
        present(alert, animated: true)
    }

    // MARK: - Bottom search

    func presentBottomSearch() {
        guard bottomSearchEnabled, !openingSearch, activeSearchController == nil,
              presentedViewController == nil else { return }
        openingSearch = true
        evaluate("window.__bottomSearchState?.()") { [weak self] value, _ in
            guard let self else { return }
            self.openingSearch = false
            guard self.presentedViewController == nil else { return }
            let state = value as? [String: Any] ?? [:]
            self.activeSearchPage = state["page"] as? String ?? "home"
            self.showSearchOverlay(state: state)
        }
    }

    private func showSearchOverlay(state: [String: Any]) {
        let page = SearchOverlayViewController()
        page.query = state["query"] as? String ?? ""
        page.themeFont = fontController.font
        page.backgroundImage = backgroundImageView.image
        page.placeholder = state["placeholder"] as? String ?? "搜索"
        page.onSearch = { [weak self] query in self?.applyBottomSearch(query) }
        page.onClose = { [weak self] in
            guard let self else { return }
            self.homeModel.query = ""
            self.rulesModel.query = ""
            self.evaluate("window.__clearBottomSearch?.()")
            let overlay = self.activeSearchController
            self.activeSearchController = nil
            overlay?.willMove(toParent: nil)
            overlay?.view.removeFromSuperview()
            overlay?.removeFromParent()
            UIView.performWithoutAnimation {
                self.keepContentBelowNativeBar()
                self.view.layoutIfNeeded()
                self.updateLayoutMetrics(force: true)
            }
        }
        page.onLayout = { [weak self] in
            guard let self, let overlay = self.activeSearchController else { return }
            let top = overlay.searchField.convert(overlay.searchField.bounds, to: self.webView).minY
            self.evaluate("window.__setNativeTabTop?.(" + String(describing: top) + ");window.__syncNativeCardGlass?.()")
        }
        activeSearchController = page
        // A transparent child overlay leaves the live page and tab bar attached.
        addChild(page)
        page.view.frame = view.bounds
        page.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(page.view)
        page.view.layer.zPosition = 3
        page.didMove(toParent: self)
        page.view.layoutIfNeeded()
        page.searchField.becomeFirstResponder()
    }

    func applyBottomSearch(_ query: String) {
        if activeSearchPage == "home" { homeModel.query = query }
        if activeSearchPage == "rules" { rulesModel.query = query }
        evaluate(arguments: [query, activeSearchPage], function: "applyBottomSearch")
    }

    // MARK: - Settings hero

    func openHeroSection(_ selector: String) {
        evaluate("window.__toggleHeroSection?.('" + selector + "')")
    }

    func editHeroAvatar() {
        guard presentedViewController == nil else { return }
        imagePicker.chooseImage(kind: .heroAvatar, index: nil)
    }

    func editHeroName() {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "修改名字", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = self.preferences.heroName
            field.placeholder = "输入名字"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return }
            self.preferences.heroName = String(name.prefix(32))
            self.refreshHero()
        })
        present(alert, animated: true)
    }

    func saveHeroAvatar(_ data: Data) {
        switch AvatarStore.saveAvatar(data: data) {
        case .none:
            refreshHero()
        case .unreadable:
            showNotice("无法读取所选头像。")
        case .encoding:
            showNotice("无法保存头像。")
        case .write:
            showNotice("头像保存失败，请重试。")
        }
    }
}
