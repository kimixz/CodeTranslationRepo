
import Foundation

class AbstractOwnCloudSyncAdapter {
    private var accountManager: AccountManager
    private var account: Account?
    private var contentProviderClient: ContentProviderClient?
    private var storageManager: FileDataStorageManager?
    private let userAccountManager: UserAccountManager
    private var client: OwnCloudClient?

    init(context: Context, autoInitialize: Bool, userAccountManager: UserAccountManager) {
        self.accountManager = AccountManager.get(context: context)
        self.userAccountManager = userAccountManager
    }

    init(context: Context, autoInitialize: Bool, allowParallelSyncs: Bool, userAccountManager: UserAccountManager) {
        self.accountManager = AccountManager.get(context: context)
        self.userAccountManager = userAccountManager
    }

    func initClientForCurrentAccount() throws {
        let ocAccount = try OwnCloudAccount(account: account, context: getContext())
        client = OwnCloudClientManagerFactory.defaultSingleton().getClientFor(ocAccount, context: getContext())
    }

    func getAccountManager() -> AccountManager {
        return self.accountManager
    }

    func getAccount() -> Account? {
        return self.account
    }

    func getUser() -> User {
        let account = getAccount()
        let accountName = account?.name
        return userAccountManager.getUser(accountName).orElseGet(userAccountManager.getAnonymousUser)
    }

    func getContentProviderClient() -> ContentProviderClient? {
        return self.contentProviderClient
    }

    func getStorageManager() -> FileDataStorageManager? {
        return self.storageManager
    }

    func getClient() -> OwnCloudClient? {
        return self.client
    }

    func setAccountManager(accountManager: AccountManager) {
        self.accountManager = accountManager
    }

    func setAccount(_ account: Account) {
        self.account = account
    }

    func setContentProviderClient(_ contentProviderClient: ContentProviderClient?) {
        self.contentProviderClient = contentProviderClient
    }

    func setStorageManager(storageManager: FileDataStorageManager) {
        self.storageManager = storageManager
    }
}
