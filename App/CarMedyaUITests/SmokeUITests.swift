import XCTest

/// Launches the real app in the iOS Simulator and screenshots the 0.7.1 screens
/// (Home toolbar browser, browser sheet, Settings > "Araç ekranında video").
/// Runs in CI (.github/workflows/app.yml, job "ui-smoke"); screenshots are kept in the .xcresult.
/// No network is needed: nothing is submitted in the browser and no source is added.
final class SmokeUITests: XCTestCase {
    /// CI simulators are slow; generous waits keep the smoke test from flaking.
    private let timeout: TimeInterval = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// XCUIApplication is main-actor isolated, so launching (and every test) runs on the main actor,
    /// as in Xcode's UI test template.
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            // NSArgumentDomain overrides @AppStorage("onboardingCompleted") so the onboarding cover is skipped.
            "-onboardingCompleted", "YES",
            "-showSamples", "YES",
            // Turkish is the source language; force it so the labels below match.
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        app.launch()
        skipOnboardingIfShown(app)
        return app
    }

    /// Fallback in case the launch argument does not reach @AppStorage: tap through the onboarding
    /// cover ("Devam" ×2, then "Başla"; OnboardingView.swift). Does nothing when the cover is not shown.
    @MainActor
    private func skipOnboardingIfShown(_ app: XCUIApplication) {
        let next = app.buttons["Devam"]
        let start = app.buttons["Başla"]
        guard next.waitForExistence(timeout: 3) || start.exists else { return }
        for _ in 0..<4 {
            if start.exists {
                start.tap()
                break
            }
            if next.exists { next.tap() }
            _ = start.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(app.buttons["home.browser"].waitForExistence(timeout: timeout), "Karşılama ekranı geçilemedi")
    }

    // Test methods run in alphabetical order; the numbers keep the screenshots in story order.

    @MainActor
    func test1_HomeShowsBrowserButton() throws {
        let app = launchApp()
        let browser = app.buttons["home.browser"]
        XCTAssertTrue(browser.waitForExistence(timeout: timeout), "Ana Sayfa'da 'Tarayıcı' düğmesi yok")
        XCTAssertEqual(browser.label, "Tarayıcı")
        snapshot("01-home")
    }

    @MainActor
    func test2_BrowserSheetOpens() throws {
        let app = launchApp()
        let browser = app.buttons["home.browser"]
        XCTAssertTrue(browser.waitForExistence(timeout: timeout))
        browser.tap()

        let address = app.textFields["browser.address"]
        XCTAssertTrue(address.waitForExistence(timeout: timeout), "Tarayıcı sayfasında adres alanı yok")
        let footer = app.staticTexts[
            "Sayfalar telefonda Safari görünümünde açılır. CarPlay ekranında web sayfası gösterilmez."
        ]
        XCTAssertTrue(footer.waitForExistence(timeout: timeout), "Tarayıcı alt bilgisi yok")
        XCTAssertTrue(app.buttons["Kapat"].exists, "Tarayıcı 'Kapat' düğmesi yok")
        // Nothing is typed or submitted: opening a page would need the network.
        snapshot("02-browser")
    }

    @MainActor
    func test3_SettingsCarVideoSection() throws {
        let app = launchApp()
        openSettingsTab(app)

        let toggle = app.switches["settings.carVideo.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: timeout), "'Park halinde araç ekranında video' anahtarı yok")
        scrollUntilHittable(toggle, in: app)
        XCTAssertEqual(toggle.label, "Park halinde araç ekranında video")
        XCTAssertEqual(toggle.value as? String, "0", "Araç ekranında video varsayılan olarak kapalı olmalı")

        let diagnosis = app.descendants(matching: .any)["settings.carVideo.diagnosis"].firstMatch
        XCTAssertTrue(diagnosis.waitForExistence(timeout: timeout), "Tanı satırı (settings.carVideo.diagnosis) yok")
        XCTAssertTrue(
            diagnosis.label.contains("Henüz CarPlay bağlantısı görülmedi"),
            "Tanı başlığı beklenen gibi değil: \(diagnosis.label)"
        )
        let header = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ==[c] %@", "Araç ekranında video"))
            .firstMatch
        XCTAssertTrue(header.exists, "'Araç ekranında video' bölüm başlığı yok")
        snapshot("03-settings-car-video")

        setSwitch(toggle, on: true)
        XCTAssertEqual(toggle.value as? String, "1", "Anahtar açılamadı")
        snapshot("04-toggle-on")

        // Leave the simulator as found so a second run on the same simulator starts from "0" again.
        setSwitch(toggle, on: false)
        XCTAssertEqual(toggle.value as? String, "0", "Anahtar geri kapatılamadı")
    }

    // MARK: - Helpers

    @MainActor
    private func openSettingsTab(_ app: XCUIApplication) {
        let tabBarButton = app.tabBars.buttons["Ayarlar"]
        if tabBarButton.waitForExistence(timeout: timeout) {
            tabBarButton.tap()
        } else {
            // Fallback if the tab bar is not exposed as a UITabBar on this iOS version.
            let button = app.buttons["Ayarlar"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: timeout), "'Ayarlar' sekmesi yok")
            button.tap()
        }
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: timeout), "Ayarlar açılmadı")
    }

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) ekranda görünür değil")
    }

    /// SwiftUI toggles in a Form: tapping the row centre does not always flip the switch, so tap the
    /// inner UISwitch first and fall back to the right edge of the row.
    @MainActor
    private func setSwitch(_ toggle: XCUIElement, on: Bool) {
        let target = on ? "1" : "0"
        if toggle.value as? String == target { return }
        let inner = toggle.switches.firstMatch
        if inner.exists && inner.isHittable {
            inner.tap()
        } else {
            toggle.tap()
        }
        if !waitForValue(toggle, target) {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            _ = waitForValue(toggle, target)
        }
    }

    @MainActor
    private func waitForValue(_ element: XCUIElement, _ value: String) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
