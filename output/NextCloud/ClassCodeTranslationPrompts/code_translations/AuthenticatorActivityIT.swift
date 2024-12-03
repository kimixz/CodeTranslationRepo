
import XCTest
import SwiftUI

class AuthenticatorActivityIT: XCTestCase {
    private let testClassName = "com.nextcloud.client.AuthenticatorActivityIT"
    private static let URL = "cloud.nextcloud.com"

    func login() {
        let scenario = ActivityScenario.launch(AuthenticatorActivity.self)
        scenario.onActivity { sut in
            onIdleSync {
                if let hostUrlInput = sut.viewWithTag(R.id.host_url_input) as? UITextField {
                    hostUrlInput.text = AuthenticatorActivityIT.URL
                    DispatchQueue.main.async {
                        sut.getAccountSetupBinding().hostUrlInput.resignFirstResponder()
                    }
                    let screenShotName = createName(testClassName + "_" + "login", "")
                    screenshotViaName(sut, screenShotName)
                }
            }
        }
    }
}
