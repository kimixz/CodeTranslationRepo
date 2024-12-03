
import XCTest

class ManageAccountsActivityIT: XCTestCase {
    var activityRule: IntentsTestRule<ManageAccountsActivity>!

    override func setUp() {
        super.setUp()
        activityRule = IntentsTestRule<ManageAccountsActivity>(activityClass: ManageAccountsActivity.self, launchActivity: false)
    }

    func open() {
        let sut = activityRule.launchActivity(nil)

        shortSleep()

        screenshot(sut)
    }

    func userInfoDetail() {
        let sut = activityRule.launchActivity(nil)

        let user = sut.accountManager.getUser()

        let userInfo = UserInfo(username: "test",
                                isEnabled: true,
                                displayName: "Test User",
                                email: "test@nextcloud.com",
                                phone: "+49 123 456",
                                address: "Address 123, Berlin",
                                website: "https://www.nextcloud.com",
                                twitter: "https://twitter.com/Nextclouders",
                                quota: Quota(),
                                groups: [])

        sut.showUser(user: user, userInfo: userInfo)

        shortSleep()
        shortSleep()

        screenshot(getCurrentActivity())
    }
}
