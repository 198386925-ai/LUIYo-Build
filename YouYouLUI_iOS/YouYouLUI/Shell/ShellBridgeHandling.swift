import WebKit

extension MainShellViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        guard let name = BridgeMessage(rawValue: message.name) else { return }
        switch name {
        case .nativeHomeState:
            if let payload = message.body as? [String: Any] {
                homeModel.apply(payload)
                DispatchQueue.main.async { [weak self] in self?.writeNativeHomeDiagnostics() }
            }
        case .activationSubmit:
            guard !isAuthorized, let payload = message.body as? [String: Any],
                  let code = payload["code"] as? String else { return }
            onLicenseSubmitted?(code)
        case .activationOpen:
            onActivationRequested?()
        case .settingsHeroFrame:
            guard let payload = message.body as? [String: Any] else { return }
            updateSettingsHero(payload)
        case .pageState:
            guard let payload = message.body as? [String: Any] else { return }
            let pageName = payload["page"] as? String ?? "home"
            if !switchingPage, let page = ShellPage(name: pageName) { updatePageScroll(page) }
            if ["home", "rules", "settings"].contains(pageName) { onPageChanged?(pageName) }
        case .minimizeBottomBar:
            if let payload = message.body as? [String: Any] {
                setScrollMinimize(payload["enabled"] as? Bool ?? false)
            }
        case .zipName:
            if let payload = message.body as? [String: Any] {
                zipExport.askFileName(default: payload["name"] as? String ?? ZipExportCoordinator.defaultFileName)
            }
        case .backgroundImage:
            // Feature removed: always clear any stored custom background image.
            backgroundImageView.image = nil
            try? FileManager.default.removeItem(at: AppPaths.legacyBackgroundImage)
            homeModel.backgroundImage = nil
            applyStoredPalette()
            nativeHomeHost?.view.backgroundColor = view.backgroundColor
        case .bottomSearch:
            handleBottomSearch(message.body as? [String: Any])
        case .luiyoBlocked:
            if let body = message.body as? String, body == "confirm" { exit(0) }
        case .themeFont:
            handleThemeFont(message.body as? [String: Any])
        case .appearanceMode:
            let payload = message.body as? [String: Any]
            applyAppearance(payload?["mode"] as? String ?? "system")
        case .nativeToggleRects:
            guard let rows = message.body as? [[String: Any]] else { return }
            materialLayer.updateToggles(rows)
        case .themeBackground, .cardColor, .buttonColor:
            handleThemeColor(message)
        case .materialMode:
            let payload = message.body as? [String: Any]
            setCardMaterialMode((payload?["mode"] as? String) ?? "liquid")
        case .cardGlassRects:
            guard let rects = message.body as? [[String: Any]] else { return }
            materialLayer.updateRects(rects)
        case .infoPage:
            let payload = message.body as? [String: Any]
            tabBar.isHidden = (payload?["open"] as? Bool) ?? false
        case .shareZip:
            guard let payload = message.body as? [String: Any],
                  let base64 = payload["base64"] as? String,
                  let data = Data(base64Encoded: base64) else { return }
            zipExport.share(data: data, fileName: payload["fileName"] as? String ?? ZipExportCoordinator.defaultFileName + ".zip")
        case .blockedPopup:
            break
        }
    }

    // MARK: - Individual payloads

    private func updateSettingsHero(_ payload: [String: Any]) {
        if settingsHero == nil {
            let hero = LUIYoCreateSettingsHero({ [weak self] in self?.openHeroSection(".guideInline") },
                                               { [weak self] in self?.openHeroSection(".changelogInline") },
                                               { [weak self] in self?.editHeroAvatar() },
                                               { [weak self] in self?.editHeroName() })
            hero.accessibilityIdentifier = "settingsBrandHero"
            webView.scrollView.addSubview(hero)
            settingsHero = hero
        }
        guard let hero = settingsHero else { return }
        hero.isHidden = !(payload["visible"] as? Bool ?? false)
        hero.frame = CGRect(x: (payload["x"] as? NSNumber)?.doubleValue ?? 0,
                            y: (payload["y"] as? NSNumber)?.doubleValue ?? 0,
                            width: (payload["width"] as? NSNumber)?.doubleValue ?? 0,
                            height: 116)
        hero.setNeedsLayout()
        hero.layoutIfNeeded()
    }

    private func handleBottomSearch(_ payload: [String: Any]?) {
        guard let payload else { return }
        let enabled = payload["enabled"] as? Bool ?? bottomSearchEnabled
        let separate = (payload["layout"] as? String).map { $0 == "separate" } ?? separateSearch
        if enabled != bottomSearchEnabled || separate != separateSearch {
            bottomSearchEnabled = enabled
            separateSearch = separate
            preferences.bottomSearchEnabled = enabled
            preferences.isSeparateSearch = separate
            UIView.performWithoutAnimation { refreshTabItems() }
        }
        if payload["open"] as? Bool == true { presentBottomSearch() }
    }

    private func handleThemeFont(_ payload: [String: Any]?) {
        guard let payload else { return }
        if payload["reset"] as? Bool == true {
            fontController.reset()
            homeModel.fontName = nil
            homeModel.importedFont = nil
        } else if let base64 = payload["data"] as? String,
                  let data = Data(base64Encoded: base64) {
            fontController.apply(data)
            homeModel.fontName = fontController.font?.fontName
            homeModel.importedFont = fontController.font
        }
    }

    private func handleThemeColor(_ message: WKScriptMessage) {
        guard let payload = message.body as? [String: Any],
              let hex = payload["color"] as? String, ColorHex.parse(hex) != nil else { return }
        let appearance = payload["appearance"] as? String == "dark" ? "dark" : "light"
        let kind: ThemeColorKind
        switch message.name {
        case BridgeMessage.themeBackground.name: kind = .background
        case BridgeMessage.buttonColor.name: kind = .buttonColor
        default: kind = .heroCardColor
        }
        preferences.setColorHex(hex, kind: kind, appearance: appearance)
        applyStoredPalette()
    }
}
