import UIKit

/// CI snapshot scenarios.
///
/// Driven by the `LUI_SNAPSHOT` environment variable. These paths are what the
/// `scripts/check-native*.sh` workflows assert on, so their output shape is a
/// contract: `ui-layout-verification.json` and `native-home-diagnostics.json`.
extension MainShellViewController {
    /// Called once the bundled page has finished loading.
    func runSnapshotScenarioIfNeeded() {
        guard let rawScenario = ProcessInfo.processInfo.environment["LUI_SNAPSHOT"] else { return }
        if rawScenario.hasPrefix("preview-") {
            runPreviewScenario(rawScenario)
        } else {
            runLayoutScenario(rawScenario)
        }
    }

    // MARK: - UI-test previews

    private func runPreviewScenario(_ rawScenario: String) {
        let page: ShellPage = rawScenario.contains("rules") ? .rules
            : (rawScenario.contains("settings") ? .settings : .home)
        webView.evaluateJavaScript(
            "document.querySelector('[data-appearance-mode=light]').click();"
                + "window.__setBottomSearchMode('separate');appNavTo('\(page.name)');"
                + "window.__applyBottomSearch('','\(page.name)')"
        )
        selectPage(page)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            if rawScenario.contains("search") { self.presentBottomSearch() }
            var previewNeedsFillImage = rawScenario == "preview-inline-auth"
            #if DEBUG
            previewNeedsFillImage = previewNeedsFillImage || rawScenario == "preview-native-theme"
            #endif
            if previewNeedsFillImage {
                self.webView.evaluateJavaScript(
                    "fillFile=new File([Uint8Array.from(atob("
                        + "'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAFklEQVR4nGNUqPj1nwEPYMInOXwUAACm9AKhD318TgAAAABJRU5ErkJggg=='"
                        + "),c=>c.charCodeAt(0))],'test.png',{type:'image/png'})"
                )
            }
            #if DEBUG
            if rawScenario == "preview-native-theme" {
                self.homeModel.fontName = "Courier"
                self.homeModel.importedFont = UIFont(name: "Courier", size: 10)
                self.webView.evaluateJavaScript(
                    "for(const [id,value] of Object.entries({appBackgroundColor:'#dce7f2',"
                        + "appCardColor:'#f3e8dc',appButtonColor:'#385170'})){const input=document.getElementById(id);"
                        + "input.value=value;input.dispatchEvent(new Event('input',{bubbles:true}))}"
                        + "document.querySelector('[data-material=blur]').click();"
                        + "window.__applyToolbarTransparency(35);window.__setBottomSearchMode('off');"
                        + "window.__setMinimizeBottomBar(true);"
                )
            }
            #endif
            if rawScenario.contains("zip-name") {
                self.webView.evaluateJavaScript(
                    "const zip=new JSZip();zip.file('check.txt','ok');"
                        + "zip.generateAsync({type:'blob'}).then(blob=>{preparedZipBlob=blob;openShareModal()})"
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let marker = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("preview-ready.txt")
                try? Data("ready".utf8).write(to: marker)
            }
        }
    }

    // MARK: - Layout verification

    private func runLayoutScenario(_ rawScenario: String) {
        var scenario = rawScenario.hasPrefix("dark-") ? String(rawScenario.dropFirst(5)) : rawScenario
        let appearance = scenario.contains("forced-dark-") ? "dark"
            : (scenario.contains("forced-light-") ? "light" : "system")
        scenario = scenario.replacingOccurrences(of: "forced-dark-", with: "")
            .replacingOccurrences(of: "forced-light-", with: "")
        let mode = scenario.contains("blur") ? "blur" : "liquid"
        let page: ShellPage = scenario.contains("settings") ? .settings
            : (scenario.contains("rules") ? .rules : .home)
        let log = scenario.contains("log")
        let folded = scenario.contains("folded")
        let foldSelector = log ? ".changelogInline" : ".themeBody"
        var fontTestJS = ""
        if rawScenario.contains("font-") && !rawScenario.contains("restored") && !rawScenario.contains("reset"),
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = try? Data(contentsOf: documents.appendingPathComponent("ThemeFontTest.ttf")) {
            fontTestJS = "setTimeout(()=>window.__importThemeFontForTest(Uint8Array.from(atob('"
                + data.base64EncodedString() + "'),c=>c.charCodeAt(0)).buffer,'Arial.ttf'),300);"
        } else if rawScenario.contains("font-reset") {
            fontTestJS = "setTimeout(()=>document.getElementById('resetCustomFont').click(),300);"
        }
        let js = """
        \(fontTestJS)
        document.querySelector('[data-appearance-mode="\(appearance)"]').click();
        document.querySelector('[data-material="\(mode)"]').click();
        appNavTo('\(page.name)');
        if (!\(rawScenario.contains("restored"))) window.__setBottomSearchMode('off');
        if ('\(page.name)' === 'settings') {
            document.querySelector('\(foldSelector)').closest('details').querySelector('summary').click();
        }
        if (\(folded)) setTimeout(function(){document.querySelector('.themeFold summary').click();},500);
        if (\(rawScenario.contains("custom"))) {
            const bg=document.getElementById('appBackgroundColor');bg.value='#325A70';bg.dispatchEvent(new Event('input'));
            const card=document.getElementById('appCardColor');card.value=\(rawScenario.hasPrefix("dark-") ? "'#503B48'" : "'#F2C9B0'");card.dispatchEvent(new Event('input'));
            const color=document.getElementById('appButtonColor');color.value=\(rawScenario.hasPrefix("dark-") ? "'#446078'" : "'#C58C48'");color.dispatchEvent(new Event('input'));
            if ('\(page.name)' === 'home') document.getElementById('tabWechat').click();
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
                window.__applyBottomSearch('\(page == .settings ? "更新日志" : "底栏微信")');
                if (\(rawScenario.contains("bottom-off-"))) {
                    window.__applyBottomSearch('');setSearch('off');
                }
            },350);
        }
        setTimeout(function(){window.__syncNativeCardGlass();},800);
        if (\(rawScenario.contains("bottom-dialog"))) setTimeout(()=>window.__openBottomSearch(),1400);
        """
        webView.evaluateJavaScript(js)
        selectPage(page)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.collectLayoutVerification(scenario: rawScenario, page: page,
                                            appearance: appearance, folded: folded, log: log)
        }
    }

    // swiftlint:disable function_body_length
    private func collectLayoutVerification(scenario rawScenario: String, page: ShellPage,
                                           appearance: String, folded: Bool, log: Bool) {
        let dark = traitCollection.userInterfaceStyle == .dark
        let expectedDark = appearance == "dark" || (appearance == "system" && rawScenario.hasPrefix("dark-"))
        let hasPicker = materialLayer.spec(forKey: "id:materialModePicker") != nil
        let styleJS = """
        (()=>{
          const rect=id=>document.getElementById(id).getBoundingClientRect();
          const credits=document.getElementById('settingsCredits'), c=rect('settingsCredits');
          const folds=[...document.querySelectorAll('.settingsFold:not([hidden])')];
          const last=folds.at(-1).getBoundingClientRect();
          return {pageTitleSizes:[...document.querySelectorAll('.pageHead h1,.settingsHead h1')].map(el=>parseFloat(getComputedStyle(el).fontSize)),neutralToolBorders:[...document.querySelectorAll('#homeTools .fillpick,#homeTools .colorfold')].map(el=>parseFloat(getComputedStyle(el).borderTopWidth)),bottomSearchEnabled:document.body.classList.contains('bottom-search-enabled'),homeSearchHidden:getComputedStyle(document.getElementById('searchInput')).display==='none',ruleSearchHidden:getComputedStyle(document.getElementById('ruleSearch')).display==='none',searchState:window.__bottomSearchState(),resultCount:document.querySelectorAll(document.body.classList.contains('nav-rules')?'.ruleCard':'.card').length,settingsSearchCount:folds.filter(f=>!f.classList.contains('search-hidden')).length,documentHeight:document.documentElement.scrollHeight,viewportHeight:innerHeight,toolsFill:getComputedStyle(document.getElementById('homeTools')).backgroundColor,toolsShadow:getComputedStyle(document.getElementById('homeTools')).boxShadow,actionShadows:[...document.querySelectorAll('#homeTools .batch,#homeTools .fillpick,#homeTools .fill,#homeTools .colorfold,#homeTools .clear,#homeTools .zip')].map(el=>getComputedStyle(el).boxShadow),creditFontSize:parseFloat(getComputedStyle(credits).fontSize),actionHeights:[...document.querySelectorAll('#homeTools .batch,#homeTools .fillpick,#homeTools .fill,#homeTools .colorfold,#homeTools .clear,#homeTools .zip')].map(el=>el.getBoundingClientRect().height),actions:[...document.querySelectorAll('#homeTools .batch,#homeTools .fillpick,#homeTools .fill,#homeTools .colorfold,#homeTools .clear,#homeTools .zip')].map(el=>getComputedStyle(el).color),category:[...document.querySelectorAll('.categorytabs button')].map(el=>getComputedStyle(el).color),dark:document.documentElement.dataset.appearance==='dark',mode:localStorage.getItem('youyou.theme.appearance'),categoryHeight:document.querySelector('.categorytabs').getBoundingClientRect().height,materialHeight:rect('materialModePicker').height,appearanceHeight:rect('appearanceModePicker').height,creditVisible:c.width>0&&c.height>0,creditTop:c.top,creditBottom:c.bottom,logBottom:last.bottom,cardHeights:folds.filter(d=>!d.open).map(d=>d.getBoundingClientRect().height),cardBorders:folds.map(d=>getComputedStyle(d).borderTopWidth),surfaceBackgrounds:[...document.querySelectorAll(".inlineVersion,.card,.ruleCard,.settingsFold,.categorytabs,#materialModePicker,#appearanceModePicker")].map(el=>getComputedStyle(el).backgroundColor),searchBelowFeedback:(()=>{const q=rect('searchInput'),f=document.querySelector('.homeFeedback').getBoundingClientRect(),t=rect('homeTools');return q.top>=f.bottom&&q.bottom<t.top&&document.getElementById('searchInput').parentElement.id==='homeTarget'})(),actionFills:[...document.querySelectorAll('#homeTools .batch,#homeTools .fillpick,#homeTools .fill,#homeTools .colorfold,#homeTools .clear,#homeTools .zip')].map(el=>getComputedStyle(el).backgroundColor),motion:window.__foldMotionChecks||[]};
        })()
        """
        webView.evaluateJavaScript(styleJS) { [weak self] value, _ in
            guard let self else { return }
            let styles = value as? [String: Any] ?? [:]
            let actionColors = styles["actions"] as? [String] ?? []
            let categoryColors = styles["category"] as? [String] ?? []
            let home = page == .home
            let expectedText = rawScenario.contains("custom") && dark ? "rgb(242, 242, 247)" : "rgb(32, 40, 50)"
            let defaultText = ["rgb(242, 242, 247)", "rgb(32, 40, 50)", "rgb(32, 40, 50)",
                               "rgb(32, 40, 50)", "rgb(255, 255, 255)", "rgb(255, 255, 255)"]
            let expectedTexts = rawScenario.contains("custom")
                ? [expectedText, expectedText, expectedText, expectedText, "rgb(255, 255, 255)", "rgb(255, 255, 255)"]
                : defaultText
            let readable = !home || actionColors == expectedTexts
            let nativeTitlesOnly = !home || (categoryColors.count == 2 && categoryColors.allSatisfy { $0 == "rgba(0, 0, 0, 0)" })
            let compactCategory = home ? abs((styles["categoryHeight"] as? Double ?? 0) - 32) < 0.5
                : (styles["categoryHeight"] as? Double ?? 999) < 0.5
            let compactMaterial = page != .settings || folded || log || rawScenario.contains("bottom-")
                || (abs((styles["materialHeight"] as? Double ?? 0) - 32) < 0.5
                    && abs((styles["appearanceHeight"] as? Double ?? 0) - 32) < 0.5)
            let creditCorrect = (styles["creditVisible"] as? Bool) == (page == .settings)
                && (!log || (styles["creditTop"] as? Double ?? 0) >= (styles["logBottom"] as? Double ?? 0))
            let checks = styles["motion"] as? [[String: Any]] ?? []
            let surfaceColors = styles["surfaceBackgrounds"] as? [String] ?? []
            let nativeSurfacesVisible = !surfaceColors.isEmpty && surfaceColors.allSatisfy { $0 == "rgba(0, 0, 0, 0)" }
            let fills = styles["actionFills"] as? [String] ?? []
            let expectedFill = rawScenario.contains("custom") ? (dark ? "rgb(68, 96, 120)" : "rgb(197, 140, 72)")
                : "rgb(255, 255, 255)"
            let expectedFills = rawScenario.contains("custom")
                ? Array(repeating: expectedFill, count: 4) + ["rgb(0, 122, 254)", "rgb(70, 216, 106)"]
                : ["rgb(0, 122, 254)", "rgb(255, 255, 255)", "rgb(70, 216, 106)",
                   "rgb(255, 255, 255)", "rgb(0, 122, 254)", "rgb(70, 216, 106)"]
            // Four accent controls retain their configured solid fills.
            // The two neutral controls intentionally add a subtle tint.
            let neutralBorders = styles["neutralToolBorders"] as? [Double] ?? []
            let solidActions = fills.count == 6 && [0, 2, 4, 5].allSatisfy { fills[$0] == expectedFills[$0] }
                && [1, 3].allSatisfy { fills[$0] != "rgba(0, 0, 0, 0)" }
                && neutralBorders.count == 2 && neutralBorders.allSatisfy { $0 >= 1 }
            let searchSurface = self.materialLayer.surface(forKey: "id:searchInput")
            let searchPresent = self.materialLayer.spec(forKey: "id:searchInput") != nil
            var searchLiquid = false
            if #available(iOS 26.0, *) { searchLiquid = searchSurface?.effect is UIGlassEffect }
            let searchBlur = searchSurface?.effect is UIBlurEffect
            let noNativeActions = !self.materialLayer.containsHomeControl
            let bottomEnabled = rawScenario.contains("bottom-") && !rawScenario.contains("bottom-off-")
            let searchCorrect = !home
                || (bottomEnabled
                    ? (!searchPresent && (styles["homeSearchHidden"] as? Bool) == true)
                    : (searchPresent && (self.materialLayer.materialMode == .blur ? searchBlur : searchLiquid)
                        && (styles["searchBelowFeedback"] as? Bool) == true))
            let toolsExpected = rawScenario.contains("custom")
                ? (dark ? "rgb(80, 59, 72)" : "rgb(242, 201, 176)")
                : (dark ? "rgb(28, 28, 30)" : "rgb(255, 255, 255)")
            let solidToolCard = self.materialLayer.spec(forKey: "id:homeTools") == nil
                && (styles["toolsFill"] as? String) == toolsExpected
                && (styles["toolsShadow"] as? String) == "none"
            let bottomCorrect = self.bottomSearchEnabled == bottomEnabled
                && (self.tabBar.items?.count ?? 0) == (bottomEnabled ? 4 : 3)
                && (styles["bottomSearchEnabled"] as? Bool) == bottomEnabled
            let searchDialogCorrect = !rawScenario.contains("bottom-dialog")
                || (self.activeSearchController?.presentingViewController != nil && self.tabBar.selectedItem?.tag == 0)
            let titleSizes = styles["pageTitleSizes"] as? [Double] ?? []
            let titlesMatch = titleSizes.count == 2 && titleSizes.allSatisfy { abs($0 - 25) < 0.1 }
            let categorySegment = self.materialLayer.allSegments.first {
                self.materialLayer.spec(forKey: $0.key)?["segment"] as? String == "category"
            }?.value
            let track = categorySegment?.superview?.backgroundColor?.resolvedColor(with: self.traitCollection).cgColor.components ?? []
            let smooth = checks.allSatisfy { ($0["jump"] as? Double ?? 999) < 0.5 && ($0["monotonic"] as? Bool) == true }
            let bg = self.view.backgroundColor?.resolvedColor(with: self.traitCollection).cgColor.components ?? []
            var result = styles
            result["scenario"] = rawScenario
            result["settingsScrollIndicator"] = self.webView.scrollView.showsVerticalScrollIndicator
            result["pageTitlesMatch"] = titlesMatch
            result["webContentInSelectedPage"] = self.webView.superview === self.selectedViewController?.view
            result["passed"] = (!folded || !hasPicker) && titlesMatch && readable && nativeTitlesOnly
                && compactCategory && compactMaterial && creditCorrect && smooth && nativeSurfacesVisible
                && solidActions && solidToolCard && bottomCorrect && searchDialogCorrect && noNativeActions
                && searchCorrect && dark == expectedDark && (styles["dark"] as? Bool) == dark
            result["selectedCapsuleAlphas"] = self.materialLayer.allSelectedPills.values.map {
                Double($0.backgroundColor?.cgColor.alpha ?? 1)
            }
            result["pickerStyles"] = self.materialLayer.allSegments.map { key, segment -> [String: Any] in
                let attributes = segment.titleTextAttributes(for: .selected) ?? [:]
                let text = attributes[.foregroundColor] as? UIColor
                return ["kind": self.materialLayer.spec(forKey: key)?["segment"] as? String ?? "",
                        "selected": segment.selectedSegmentIndex,
                        "track": segment.superview?.backgroundColor?.cgColor.components?.map { Double($0) } ?? [],
                        "capsule": self.materialLayer.allSelectedPills[key]?.backgroundColor?.cgColor.components?.map { Double($0) } ?? [],
                        "selectedText": text?.resolvedColor(with: self.traitCollection).cgColor.components?.map { Double($0) } ?? []]
            }
            result["nativeFontRestoredOnLoad"] = self.restoredNativeFont
            result["nativeTabFonts"] = (self.tabBar.items ?? []).map {
                ($0.titleTextAttributes(for: .normal)?[.font] as? UIFont)?.fontName ?? "system"
            }
            result["nativeSelectedTabFonts"] = (self.tabBar.items ?? []).map {
                ($0.titleTextAttributes(for: .selected)?[.font] as? UIFont)?.fontName ?? "system"
            }
            result["appName"] = AppConfiguration.displayName
            result["appVersion"] = AppConfiguration.marketingVersion
            result["appBuild"] = AppConfiguration.buildNumber
            if #available(iOS 18.0, *) {
                result["nativeSeparateSearch"] = self.tabs.contains { $0 is UISearchTab }
            }
            result["categoryTrack"] = track.map { Double($0) }
            result["nativeSearchEnabled"] = self.bottomSearchEnabled
            result["nativeSearchDialogVisible"] = self.activeSearchController?.presentingViewController != nil
            result["nativeSearchDialogQuery"] = self.activeSearchController?.searchField.text ?? ""
            result["nativeSelectedTab"] = self.tabBar.selectedItem?.tag ?? -1
            result["nativeToolsPresent"] = self.materialLayer.spec(forKey: "id:homeTools") != nil
            result["searchLiquid"] = searchLiquid
            result["searchBlur"] = searchBlur
            result["nativeCardColor"] = UserDefaults.standard.string(
                forKey: PreferenceKey.diagnosticsColor("cardColor", appearance: dark ? "dark" : "light")) ?? ""
            result["nativeButtonColor"] = UserDefaults.standard.string(
                forKey: PreferenceKey.diagnosticsColor("buttonColor", appearance: dark ? "dark" : "light")) ?? ""
            result["logNativeCards"] = self.materialLayer.nodeSpecCount
            result["nativeActionCount"] = self.materialLayer.homeControlCount
            result["materialPickerPresent"] = hasPicker
            result["nativeDark"] = dark
            result["background"] = bg.map { Double($0) }
            result["nativeTabTop"] = Double(self.tabBar.frame.minY)
            result["nativeMode"] = self.preferences.appearanceMode
            guard let data = try? JSONSerialization.data(withJSONObject: result),
                  let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            try? data.write(to: documents.appendingPathComponent("ui-layout-verification.json"), options: .atomic)
        }
    }
    // swiftlint:enable function_body_length

    /// Debug-only diagnostics consumed by `scripts/check-native-home-ios.sh`.
    func writeNativeHomeDiagnostics() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["LUI_SNAPSHOT"] == "preview-native-theme" else { return }
        let theme = homeModel.theme
        func alphas(_ view: UIView) -> [Double] {
            (view is UIVisualEffectView ? [Double(view.alpha)] : []) + view.subviews.flatMap(alphas)
        }
        var scrollLinked = false
        if #available(iOS 18.0, *) {
            scrollLinked = nativeHomeScrollView != nil
                && selectedViewController?.contentScrollView(for: .bottom) === nativeHomeScrollView
        }
        let values: [String: Any] = [
            "background": theme.background, "card": theme.card, "button": theme.button,
            "rootBackground": view.backgroundColor?.resolvedColor(with: traitCollection).nativeHex ?? "",
            "toolbarOpacity": theme.toolbarOpacity, "materialBlur": homeModel.useBlur,
            "font": homeModel.fontName ?? "", "bottomSearchEnabled": theme.bottomSearchEnabled,
            "minimizeEnabled": scrollMinimizeEnabled, "scrollLinked": scrollLinked,
            "scrollOffset": Double(nativeHomeScrollView?.contentOffset.y ?? 0),
            "nativeMaterialAlphas": nativeHomeHost.map { alphas($0.view) } ?? [],
            "uploadedCount": homeModel.uploadedCount
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: values) else { return }
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("native-home-diagnostics.json")
        try? data.write(to: file, options: .atomic)
        #endif
    }
}
