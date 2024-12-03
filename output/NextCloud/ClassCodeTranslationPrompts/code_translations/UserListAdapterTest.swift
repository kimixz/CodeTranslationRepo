
import XCTest
import UIKit
import MockitoSwift

class UserListAdapterTest: XCTestCase {
    var userListAdapter: UserListAdapter!
    var manageAccountsActivity: ManageAccountsActivity!

    @Mock
    var viewThemeUtils: ViewThemeUtils!

    override func setUp() {
        super.setUp()
        manageAccountsActivity = mock(ManageAccountsActivity.self, defaultAnswer: .deepStubs)
        when(manageAccountsActivity.resources.getDimension(R.dimen.list_item_avatar_icon_radius))
            .thenReturn(0.1)
    }

    func test_getItemCountEmptyList() {
        userListAdapter = UserListAdapter(manageAccountsActivity: manageAccountsActivity,
                                          someParameter: nil,
                                          userList: [],
                                          anotherParameter: nil,
                                          flag1: true,
                                          flag2: true,
                                          flag3: true,
                                          viewThemeUtils: viewThemeUtils)
        XCTAssertEqual(0, userListAdapter.getItemCount())
    }

    func test_getItemCountNormalCase() {
        var accounts: [UserListItem] = []
        accounts.append(UserListItem())
        accounts.append(UserListItem())

        userListAdapter = UserListAdapter(manageAccountsActivity: manageAccountsActivity,
                                          someParameter: nil,
                                          accounts: accounts,
                                          anotherParameter: nil,
                                          flag1: true,
                                          flag2: true,
                                          flag3: true,
                                          viewThemeUtils: viewThemeUtils)

        XCTAssertEqual(2, userListAdapter.getItemCount())
    }

    func test_getItem() {
        let manageAccountsActivity = mock(ManageAccountsActivity.self, returnsDeepStubs: true)
        when(manageAccountsActivity.resources.getDimension(R.dimen.list_item_avatar_icon_radius)).thenReturn(0.1 as Float)

        var accounts: [UserListItem] = []
        userListAdapter = UserListAdapter(manageAccountsActivity: manageAccountsActivity,
                                          someParameter: nil,
                                          accounts: accounts,
                                          anotherParameter: nil,
                                          flag1: true,
                                          flag2: true,
                                          flag3: true,
                                          viewThemeUtils: viewThemeUtils)

        let userListItem1 = UserListItem()
        let userListItem2 = UserListItem()
        accounts.append(userListItem1)
        accounts.append(userListItem2)

        XCTAssertEqual(userListItem2, userListAdapter.getItem(at: 1))
    }
}
