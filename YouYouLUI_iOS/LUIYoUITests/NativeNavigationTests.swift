import XCTest

final class NativeNavigationTests: XCTestCase {
    private func searchButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'Search' OR label == '搜索'")).firstMatch
    }

    private func openSearch(_ app: XCUIApplication) -> XCUIElement {
        let button = searchButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        XCTAssertTrue(button.isHittable)
        button.tap()
        let field = app.textFields["bottomSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        XCTAssertTrue(field.isHittable)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["bottomSearchClose"].isHittable)
        return field
    }

    func testInlineActivationAndFullExport() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LUI_SNAPSHOT"] = "preview-inline-auth"
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["点击左图上传"].firstMatch.waitForExistence(timeout: 120))
        app.tabBars.buttons["设置"].tap()
        let code = app.webViews.textFields["卡密"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        code.tap()
        if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
        code.typeText("UI-TEST")
        app.webViews.buttons["激活"].tap()
        XCTAssertTrue(code.waitForNonExistence(timeout: 10))
        app.tabBars.buttons["首页"].tap()
        app.webViews.buttons["双分类补全"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
        app.alerts.buttons["好"].tap()
        app.webViews.buttons["导出 ZIP"].tap()
        let rename = app.alerts["导出 ZIP"]
        XCTAssertTrue(rename.waitForExistence(timeout: 60), app.debugDescription)
        XCTAssertTrue(rename.textFields["zipExportName"].exists)
        rename.buttons["分享"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["zipShareSheet"].waitForExistence(timeout: 15), app.debugDescription)
    }

    func testDetachedSearchWorksOnEveryPage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LUI_SNAPSHOT"] = "preview-home"
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["微信图标生成器"].waitForExistence(timeout: 120))
        // The snapshot scenario sets saved layout after WebKit finishes loading.
        XCTAssertTrue(searchButton(app).waitForExistence(timeout: 20))
        for page in ["首页", "规则", "设置"] {
            if page != "首页" { app.tabBars.buttons[page].tap() }
            let field = openSearch(app)
            let title = page == "首页" ? "微信图标生成器" : (page == "规则" ? "规则" : "设置")
            XCTAssertTrue(app.webViews.staticTexts[title].exists, "Search must keep the current page visible")
            XCTAssertEqual(field.frame.height, 44, accuracy: 0.5)
            XCTAssertEqual(app.buttons["bottomSearchClose"].frame.height, 44, accuracy: 0.5)
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "detached-search-" + page
            image.lifetime = .keepAlways
            add(image)
            app.buttons["bottomSearchClose"].tap()
            XCTAssertTrue(field.waitForNonExistence(timeout: 10))
            XCTAssertTrue(app.tabBars.buttons[page].isSelected)
        }
    }

    func testMergedSearchSubmitsAndReturns() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LUI_SNAPSHOT"] = "preview-home"
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["微信图标生成器"].waitForExistence(timeout: 120))
        let field = openSearch(app)
        field.typeText("no-matching-item-xyz\n")
        XCTAssertTrue(field.exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        app.buttons["bottomSearchClose"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["首页"].isSelected)
        let reopened = openSearch(app)
        XCTAssertFalse((reopened.value as? String ?? "").contains("no-matching-item-xyz"), "Closing search must clear the previous query")
        XCTAssertFalse(app.webViews.staticTexts["没有匹配的规则"].exists)
        app.buttons["bottomSearchClose"].tap()
    }

    func testAThemePersistenceAndNativeZipName() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LUI_SNAPSHOT"] = "preview-settings"
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["设置"].waitForExistence(timeout: 120))
        let theme = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "主题")).firstMatch
        XCTAssertTrue(theme.waitForExistence(timeout: 15), app.debugDescription)
        theme.tap()
        let slider = app.webViews.sliders["工具栏卡片透明度"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        for _ in 0..<4 { if slider.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(slider.isHittable)
        let original = slider.value as? String
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        let saved = slider.value as? String
        XCTAssertNotEqual(saved, original, "Dragging must change toolbar transparency")
        app.terminate()
        app.launch()
        XCTAssertTrue(theme.waitForExistence(timeout: 15), app.debugDescription)
        theme.tap()
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        for _ in 0..<4 { if slider.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(slider.isHittable)
        XCTAssertEqual(slider.value as? String, saved)
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: -0.1, dy: 0.5)))
        XCTAssertTrue(app.webViews.buttons["选择图片"].exists)
        XCTAssertTrue(app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "滚动时缩小底栏")).firstMatch.exists)
        app.terminate()
        app.launchEnvironment["LUI_SNAPSHOT"] = "preview-zip-name"
        app.launch()
        let alert = app.alerts["导出 ZIP"]
        XCTAssertTrue(alert.waitForExistence(timeout: 120))
        XCTAssertTrue(alert.textFields["zipExportName"].exists)
        XCTAssertTrue(alert.buttons["分享"].exists)
        alert.textFields["zipExportName"].tap()
        if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
        alert.textFields["zipExportName"].typeText(" Test")
        alert.buttons["分享"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["zipShareSheet"].waitForExistence(timeout: 15), "Renaming must continue to the native share sheet")
    }
}
