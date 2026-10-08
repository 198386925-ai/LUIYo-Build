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
    }
}
