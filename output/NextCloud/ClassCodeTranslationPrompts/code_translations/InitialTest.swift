
import XCTest
import UIKit

class InitialTest: XCTestCase {
    private let OWNCLOUD_APP_PACKAGE = "com.owncloud.android"
    private let ANDROID_SETTINGS_PACKAGE = "com.android.settings"
    private let SETTINGS_DATA_USAGE_OPTION = "Data usage"
    private let LAUNCH_TIMEOUT: TimeInterval = 5.0

    var mDevice: XCUIApplication!

    override func setUp() {
        super.setUp()
        // Initialize XCUIApplication instance
        mDevice = XCUIApplication()
    }

    func checkPreconditions() {
        XCTAssertNotNil(mDevice)
    }

    func startAppFromHomeScreen() {
        // Perform a short press on the HOME button
        XCUIDevice.shared.press(.home)

        // Wait for launcher
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: LAUNCH_TIMEOUT))

        // Launch the app
        let app = XCUIApplication(bundleIdentifier: OWNCLOUD_APP_PACKAGE)
        app.launch()

        // Wait for the app to appear
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: LAUNCH_TIMEOUT))
    }

    func startSettingsFromHomeScreen() throws {
        XCUIDevice.shared.press(.home)

        // Wait for launcher
        let launcherPackage = getLauncherPackageName()
        XCTAssertNotNil(launcherPackage)
        let exists = mDevice.otherElements[launcherPackage!].waitForExistence(timeout: LAUNCH_TIMEOUT)
        XCTAssertTrue(exists)

        // Launch the app
        let settingsApp = XCUIApplication(bundleIdentifier: ANDROID_SETTINGS_PACKAGE)
        settingsApp.launchArguments.append("--reset")
        settingsApp.launch()

        try clickByText(SETTINGS_DATA_USAGE_OPTION)
    }

    private func getLauncherPackageName() -> String? {
        // Implement logic to get the launcher package name
        return nil
    }

    private func clickByText(_ text: String) throws {
        let element = mDevice.staticTexts[text]
        if element.exists {
            element.tap()
        } else {
            throw NSError(domain: "UiObjectNotFoundException", code: 0, userInfo: nil)
        }
    }
}
