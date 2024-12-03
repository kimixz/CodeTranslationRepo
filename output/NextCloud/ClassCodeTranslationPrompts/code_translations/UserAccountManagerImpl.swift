
import Foundation

class UserAccountManagerImpl: UserAccountManager {
    
    private static let TAG = String(describing: UserAccountManagerImpl.self)
    private static let PREF_SELECT_OC_ACCOUNT = "select_oc_account"
    
    private var context: Context
    private let accountManager: AccountManager
    
    static func fromContext(context: Context) -> UserAccountManagerImpl {
        let am = context.getSystemService(Context.ACCOUNT_SERVICE) as! AccountManager
        return UserAccountManagerImpl(context: context, accountManager: am)
    }
    
    init(context: Context, accountManager: AccountManager) {
        self.context = context
        self.accountManager = accountManager
    }
    
    func removeAllAccounts() {
        for account in getAccounts() {
            accountManager.removeAccount(account, completion: nil)
        }
    }
    
    func removeUser(user: User) -> Bool {
        do {
            let result = try accountManager.removeAccount(user.toPlatformAccount(), null, null)
            return result.getResult()
        } catch {
            return false
        }
    }
    
    func getAccounts() -> [Account] {
        return accountManager.getAccountsByType(getAccountType())
    }
    
    func getAllUsers() -> [User] {
        let accounts = getAccounts()
        var users: [User] = []
        for account in accounts {
            if let user = createUserFromAccount(account) {
                users.append(user)
            }
        }
        return users
    }
    
    func exists(account: Account?) -> Bool {
        let nextcloudAccounts = getAccounts()
        
        if let account = account, let accountName = account.name {
            let lastAtPos = accountName.lastIndex(of: "@") ?? accountName.endIndex
            let hostAndPort = String(accountName[accountName.index(after: lastAtPos)...])
            let username = String(accountName[..<lastAtPos])
            
            for otherAccount in nextcloudAccounts {
                if let otherAccountName = otherAccount.name {
                    let otherLastAtPos = otherAccountName.lastIndex(of: "@") ?? otherAccountName.endIndex
                    let otherHostAndPort = String(otherAccountName[otherAccountName.index(after: otherLastAtPos)...])
                    let otherUsername = String(otherAccountName[..<otherLastAtPos])
                    
                    if otherHostAndPort == hostAndPort && otherUsername.caseInsensitiveCompare(username) == .orderedSame {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    func getCurrentAccount() -> Account {
        let ocAccounts = getAccounts()
        
        let arbitraryDataProvider = ArbitraryDataProviderImpl(context: context)
        let appPreferences = UserDefaults.standard
        let accountName = appPreferences.string(forKey: UserAccountManagerImpl.PREF_SELECT_OC_ACCOUNT)
        
        var defaultAccount = ocAccounts.first { $0.name == accountName }
        
        if defaultAccount == nil {
            defaultAccount = ocAccounts.first { !arbitraryDataProvider.getBooleanValue(forKey: $0.name, PENDING_FOR_REMOVAL) }
        }
        
        if defaultAccount == nil {
            if !ocAccounts.isEmpty {
                defaultAccount = ocAccounts[0]
            } else {
                defaultAccount = getAnonymousAccount()
            }
        }
        
        return defaultAccount!
    }
    
    private func getAnonymousAccount() -> Account {
        return Account(name: "Anonymous", type: context.getString(R.string.anonymous_account_type))
    }
    
    private func createUserFromAccount(account: Account) -> User? {
        let safeContext = context ?? MainApp.getAppContext()
        if safeContext == nil {
            Log_OC.e(UserAccountManagerImpl.TAG, "Unable to obtain a valid context")
            return nil
        }
        
        if AccountExtensionsKt.isAnonymous(account, safeContext) {
            return nil
        }
        
        var ownCloudAccount: OwnCloudAccount
        do {
            ownCloudAccount = try OwnCloudAccount(account: account, context: safeContext)
        } catch {
            return nil
        }
        
        let serverVersionStr = accountManager.getUserData(account, forKey: AccountUtils.Constants.KEY_OC_VERSION)
        let serverVersion: OwnCloudVersion
        if let serverVersionStr = serverVersionStr {
            serverVersion = OwnCloudVersion(versionString: serverVersionStr)
        } else {
            serverVersion = MainApp.MINIMUM_SUPPORTED_SERVER_VERSION
        }
        
        let serverAddressStr = accountManager.getUserData(account, forKey: AccountUtils.Constants.KEY_OC_BASE_URL)
        if serverAddressStr == nil || serverAddressStr!.isEmpty {
            return AnonymousUser.fromContext(safeContext)
        }
        let serverUri = URI(string: serverAddressStr!) // TODO: validate
        
        return RegisteredUser(
            account: account,
            ownCloudAccount: ownCloudAccount,
            server: Server(uri: serverUri, version: serverVersion)
        )
    }
    
    func getUser() -> User {
        let account = getCurrentAccount()
        if let user = createUserFromAccount(account) {
            return user
        } else {
            return AnonymousUser.fromContext(context)
        }
    }
    
    func getUser(accountName: String) -> User? {
        let account = getAccountByName(accountName)
        let user = createUserFromAccount(account)
        return user
    }
    
    func getAnonymousUser() -> User {
        return AnonymousUser.fromContext(context)
    }
    
    func getCurrentOwnCloudAccount() -> OwnCloudAccount? {
        do {
            let currentPlatformAccount = try getCurrentAccount()
            return OwnCloudAccount(account: currentPlatformAccount, context: context)
        } catch {
            return nil
        }
    }
    
    func getAccountByName(name: String) -> Account {
        for account in getAccounts() {
            if account.name == name {
                return account
            }
        }
        return getAnonymousAccount()
    }
    
    func setCurrentOwnCloudAccount(accountName: String?) -> Bool {
        var result = false
        if let accountName = accountName {
            for account in getAccounts() {
                if accountName == account.name {
                    let appPrefs = UserDefaults.standard
                    appPrefs.set(accountName, forKey: UserAccountManagerImpl.PREF_SELECT_OC_ACCOUNT)
                    result = true
                    break
                }
            }
        }
        return result
    }
    
    func setCurrentOwnCloudAccount(hashCode: Int) -> Bool {
        var result = false
        if hashCode != 0 {
            for user in getAllUsers() {
                if hashCode == user.hashValue {
                    let appPrefs = UserDefaults.standard
                    appPrefs.set(user.getAccountName(), forKey: UserAccountManagerImpl.PREF_SELECT_OC_ACCOUNT)
                    result = true
                    break
                }
            }
        }
        return result
    }
    
    @available(*, deprecated)
    func getServerVersion(account: Account?) -> OwnCloudVersion {
        var serverVersion = MainApp.minimumSupportedServerVersion
        
        if let account = account {
            let accountMgr = AccountManager(mainAppContext: MainApp.getAppContext())
            if let serverVersionStr = accountMgr.getUserData(account: account, key: com.owncloud.android.lib.common.accounts.AccountUtils.Constants.KEY_OC_VERSION) {
                serverVersion = OwnCloudVersion(versionString: serverVersionStr)
            }
        }
        
        return serverVersion
    }
    
    func resetOwnCloudAccount() {
        let appPrefs = UserDefaults.standard
        appPrefs.set(nil, forKey: UserAccountManagerImpl.PREF_SELECT_OC_ACCOUNT)
    }
    
    func accountOwnsFile(file: OCFile, account: Account) -> Bool {
        let ownerId = file.getOwnerId()
        return ownerId.isEmpty || account.name.split(separator: "@")[0].caseInsensitiveCompare(ownerId) == .orderedSame
    }
    
    func userOwnsFile(file: OCFile, user: User) -> Bool {
        return accountOwnsFile(file: file, account: user.toPlatformAccount())
    }
    
    func migrateUserId() -> Bool {
        let ocAccounts = accountManager.accounts(withAccountType: MainApp.getAccountType(context))
        var failed = 0
        let remoteUserNameOperation = GetUserInfoRemoteOperation()
        
        for account in ocAccounts {
            let storedUserId = accountManager.userData(for: account, key: com.owncloud.android.lib.common.accounts.AccountUtils.Constants.KEY_USER_ID)
            
            if !storedUserId.isEmpty {
                continue
            }
            
            do {
                let ocAccount = try OwnCloudAccount(account: account, context: context)
                let nextcloudClient = OwnCloudClientManagerFactory.getDefaultSingleton().getNextcloudClient(for: ocAccount, context: context)
                
                let result = remoteUserNameOperation.execute(nextcloudClient)
                
                if result.isSuccess {
                    let userInfo = result.resultData
                    let userId = userInfo.id
                    let displayName = userInfo.displayName
                    
                    accountManager.setUserData(for: account, key: com.owncloud.android.lib.common.accounts.AccountUtils.Constants.KEY_DISPLAY_NAME, value: displayName)
                    accountManager.setUserData(for: account, key: com.owncloud.android.lib.common.accounts.AccountUtils.Constants.KEY_USER_ID, value: userId)
                } else {
                    print("Error while getting username for account: \(account.name)")
                    failed += 1
                    continue
                }
            } catch {
                print("Error while getting username: \(error.localizedDescription)")
                failed += 1
                continue
            }
        }
        
        return failed == 0
    }
    
    private func getAccountType() -> String {
        return NSLocalizedString("account_type", comment: "")
    }
    
    func startAccountCreation(activity: Activity) {
        if activity is LauncherActivity || activity is FirstRunActivity {
            return
        }
        
        let intent = Intent(context: context, AuthenticatorActivity.self)
        intent.flags = .newTask
        context.startActivity(intent)
    }
}
