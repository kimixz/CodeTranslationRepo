
import Foundation
import XCTest

class DrawerActivityIT: XCTestCase {
    static var account1: Account?
    static var user1: User?
    static var account2: Account?
    static var account2Name: String?
    static var account2DisplayName: String?

    @BeforeClass
    static func beforeClass() {
        let arguments = ProcessInfo.processInfo.environment
        guard let baseUrlString = arguments["TEST_SERVER_URL"], let baseUrl = URL(string: baseUrlString) else {
            return
        }

        let platformAccountManager = AccountManager.shared
        let userAccountManager = UserAccountManagerImpl.fromContext(targetContext)

        for account in platformAccountManager.accounts {
            platformAccountManager.removeAccountExplicitly(account)
        }

        var loginName = "user1"
        var password = "user1"

        var temp = Account(username: "\(loginName)@\(baseUrl)", accountType: MainApp.getAccountType(targetContext))
        platformAccountManager.addAccountExplicitly(temp, password: password, userData: nil)
        platformAccountManager.setUserData(temp, key: AccountUtils.Constants.KEY_OC_ACCOUNT_VERSION, value: String(UserAccountManager.ACCOUNT_VERSION))
        platformAccountManager.setUserData(temp, key: AccountUtils.Constants.KEY_OC_VERSION, value: "14.0.0.0")
        platformAccountManager.setUserData(temp, key: AccountUtils.Constants.KEY_OC_BASE_URL, value: baseUrl.absoluteString)
        platformAccountManager.setUserData(temp, key: AccountUtils.Constants.KEY_USER_ID, value: loginName)

        account1 = userAccountManager.getAccountByName("\(loginName)@\(baseUrl)")
        user1 = userAccountManager.getUser(account1!.name)

        loginName = "user2"
        password = "user2"

        temp = Account(username: "\(loginName)@\(baseUrl)", accountType: MainApp.getAccountType(targetContext))
        platformAccountManager.addAccountExplicitly(temp, password: password, userData: nil)
        platformAccountManager.setUserData(temp, key: AccountUtils.Constants.KEY_OC_ACCOUNT_VERSION, value: String(UserAccountManager.ACCOUNT_VERSION))
        platformAccountManager.setUserData(temp, key: AccountUtils.Constants.KEY_OC_VERSION, value: "14.0.0.0")
        platformAccountManager.setUserData(temp, key: AccountUtils.Constants.KEY_OC_BASE_URL, value: baseUrl.absoluteString)
        platformAccountManager.setUserData(temp, key: AccountUtils.Constants.KEY_USER_ID, value: loginName)

        account2 = userAccountManager.getAccountByName("\(loginName)@\(baseUrl)")
        account2Name = "\(loginName)@\(baseUrl)"
        account2DisplayName = "User Two@\(baseUrl)"
    }

    func switchAccountViaAccountList() {
        let sut = activityRule.launchActivity(nil)

        sut.setUser(user1)

        XCTAssertEqual(account1, sut.getUser().get().toPlatformAccount())

        onView(withId: R.id.switch_account_button).perform(click())

        onView(anyOf(withText: account2Name, withText: account2DisplayName)).perform(click())

        waitForIdleSync()

        XCTAssertEqual(account2, sut.getUser().get().toPlatformAccount())

        onView(withId: R.id.switch_account_button).perform(click())
        onView(withText: account1.name).perform(click())
    }
}
