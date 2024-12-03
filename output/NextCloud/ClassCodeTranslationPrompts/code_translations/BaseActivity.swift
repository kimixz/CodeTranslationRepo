
import UIKit

class BaseActivity: UIViewController {

    private static let TAG = String(describing: BaseActivity.self)

    private var themeChangePending = false
    private var paused = false
    protected var enableAccountHandling = true

    private var mixinRegistry = MixinRegistry()
    private var sessionMixin: SessionMixin!

    @Inject var accountManager: UserAccountManager!
    @Inject var preferences: AppPreferences!
    @Inject var fileDataStorageManager: FileDataStorageManager!

    private lazy var onPreferencesChanged: AppPreferences.Listener = {
        return AppPreferences.Listener { [weak self] mode in
            self?.onThemeSettingsModeChanged()
        }
    }()

    func getUserAccountManager() -> UserAccountManager {
        return accountManager
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sessionMixin = SessionMixin(self, accountManager: accountManager)
        mixinRegistry.add(sessionMixin)

        if enableAccountHandling {
            mixinRegistry.onCreate(nil)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        preferences.addListener(onPreferencesChanged)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        mixinRegistry.onDestroy()
        preferences.removeListener(onPreferencesChanged)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        mixinRegistry.onPause()
        paused = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if enableAccountHandling {
            mixinRegistry.onResume()
        }
        paused = false

        if themeChangePending {
            recreate()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        mixinRegistry.onNewIntent(nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NSLog("onRestart() start")
        if enableAccountHandling {
            mixinRegistry.onRestart()
        }
    }

    private func onThemeSettingsModeChanged() {
        if paused {
            themeChangePending = true
        } else {
            recreate()
        }
    }

    @available(*, deprecated)
    func setAccount(_ account: Account, savedAccount: Bool) {
        sessionMixin.setAccount(account)
    }

    func setUser(_ user: User) {
        sessionMixin.setUser(user)
    }

    func startAccountCreation() {
        sessionMixin.startAccountCreation()
    }

    func getCapabilities() -> OCCapability {
        return sessionMixin.getCapabilities()
    }

    func getAccount() -> Account {
        return sessionMixin.getCurrentAccount()
    }

    func getUser() -> User? {
        return sessionMixin.getUser()
    }

    func getStorageManager() -> FileDataStorageManager {
        return fileDataStorageManager
    }
}
