
import Foundation
import XCTest

class AbstractIT: XCTestCase {
    static var targetContext: Context!
    static var account: Account!
    static var user: User!
    static var client: OwnCloudClient!
    static var nextcloudClient: NextcloudClient!
    static var COLOR: String = ""
    static var DARK_MODE: String = ""

    @Rule
    public let permissionRule = GrantStoragePermissionRule.grant()

    var currentActivity: Activity?

    var fileDataStorageManager: FileDataStorageManager {
        return FileDataStorageManager(user: user, contentResolver: targetContext.contentResolver)
    }

    var arbitraryDataProvider: ArbitraryDataProvider {
        return ArbitraryDataProviderImpl(targetContext)
    }

    static func beforeAll() {
        do {
            // clean up
            targetContext = InstrumentationRegistry.getInstrumentation().targetContext
            let platformAccountManager = AccountManager.get(targetContext)

            for account in platformAccountManager.accounts {
                if account.type.caseInsensitiveCompare("nextcloud") == .orderedSame {
                    platformAccountManager.removeAccountExplicitly(account)
                }
            }

            account = createAccount("test@https://nextcloud.localhost")
            user = getUser(account)

            client = OwnCloudClientFactory.createOwnCloudClient(account, targetContext)
            nextcloudClient = OwnCloudClientFactory.createNextcloudClient(user, targetContext)
        } catch {
            fatalError("Error setting up clients: \(error)")
        }

        let arguments = InstrumentationRegistry.getArguments()

        // color
        if let colorParameter = arguments["COLOR"], !colorParameter.isEmpty {
            let fileDataStorageManager = FileDataStorageManager(user: user, contentResolver: targetContext.contentResolver)

            var colorHex: String? = nil
            COLOR = colorParameter
            switch colorParameter {
            case "red":
                colorHex = "#7c0000"
            case "green":
                colorHex = "#00ff00"
            case "white":
                colorHex = "#ffffff"
            case "black":
                colorHex = "#000000"
            case "lightgreen":
                colorHex = "#aaff00"
            default:
                break
            }

            let capability = fileDataStorageManager.getCapability(account.name)
            capability.setGroupfolders(.TRUE)

            if let colorHex = colorHex {
                capability.setServerColor(colorHex)
            }

            fileDataStorageManager.saveCapabilities(capability)
        }

        // dark / light
        if let darkModeParameter = arguments["DARKMODE"] {
            if darkModeParameter.caseInsensitiveCompare("dark") == .orderedSame {
                DARK_MODE = "dark"
                AppPreferencesImpl.fromContext(targetContext).setDarkThemeMode(.DARK)
                MainApp.setAppTheme(.DARK)
            } else {
                DARK_MODE = "light"
            }
        }

        if DARK_MODE.caseInsensitiveCompare("light") == .orderedSame && COLOR.caseInsensitiveCompare("blue") == .orderedSame {
            // use already existing names
            DARK_MODE = ""
            COLOR = ""
        }
    }

    func testOnlyOnServer(version: OwnCloudVersion) throws {
        let ocCapability = getCapability()
        guard ocCapability.version.isNewerOrEqual(version) else {
            throw AccountUtils.AccountNotFoundException()
        }
    }

    func getCapability() throws -> OCCapability {
        let client = OwnCloudClientFactory.createNextcloudClient(user: user, targetContext: targetContext)
        
        let ocCapability = try GetCapabilitiesRemoteOperation()
            .execute(client: client)
            .getSingleData() as! OCCapability
        
        return ocCapability
    }

    override func setUp() {
        super.setUp()
        // Assuming a similar accessibility check setup exists in Swift
        // This is a placeholder as XCTest does not have a direct equivalent
        // AccessibilityChecks.enable().setRunChecksFromRootView(true)
    }

    func after() {
        fileDataStorageManager.removeLocalFiles(user: user, fileDataStorageManager: fileDataStorageManager)
        fileDataStorageManager.deleteAllFiles()
    }

    func getStorageManager() -> FileDataStorageManager {
        return fileDataStorageManager
    }

    func getAllAccounts() -> [Account] {
        return AccountManager.get(targetContext).accounts
    }

    static func createDummyFiles() throws {
        let tempPath = FileStorageUtils.getTemporalPath(account.name)
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: tempPath) {
            try fileManager.createDirectory(atPath: tempPath, withIntermediateDirectories: true, attributes: nil)
        }

        assert(fileManager.fileExists(atPath: tempPath))

        try createFile(name: "empty.txt", size: 0)
        try createFile(name: "nonEmpty.txt", size: 100)
        try createFile(name: "chunkedFile.txt", size: 500000)
    }

    static func getDummyFile(name: String) throws -> URL {
        let fileManager = FileManager.default
        let internalPath = FileStorageUtils.getInternalTemporalPath(account.name, targetContext)
        let fileURL = URL(fileURLWithPath: internalPath).appendingPathComponent(name)

        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL
        } else if name.hasSuffix("/") {
            try fileManager.createDirectory(at: fileURL, withIntermediateDirectories: true, attributes: nil)
            return fileURL
        } else {
            switch name {
            case "empty.txt":
                return try createFile(name: "empty.txt", size: 0)

            case "nonEmpty.txt":
                return try createFile(name: "nonEmpty.txt", size: 100)

            case "chunkedFile.txt":
                return try createFile(name: "chunkedFile.txt", size: 500000)

            default:
                return try createFile(name: name, size: 0)
            }
        }
    }

    static func createFile(name: String, size: Int) throws -> URL {
        let fileManager = FileManager.default
        let internalPath = FileStorageUtils.getInternalTemporalPath(account.name, targetContext)
        let fileURL = URL(fileURLWithPath: internalPath).appendingPathComponent(name)

        let data = Data(count: size)
        if fileManager.createFile(atPath: fileURL.path, contents: data, attributes: nil) {
            return fileURL
        } else {
            throw NSError(domain: "FileError", code: 0, userInfo: nil)
        }
    }

    func getFile(filename: String) throws -> URL {
        guard let inputStream = Bundle.main.url(forResource: filename, withExtension: nil) else {
            throw NSError(domain: "FileError", code: 0, userInfo: nil)
        }
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempFileURL = tempDirectory.appendingPathComponent("file")
        try FileManager.default.copyItem(at: inputStream, to: tempFileURL)
        
        return tempFileURL
    }

    func waitForIdleSync() {
        XCUIApplication().wait(for: .idle, timeout: 0)
    }

    func onIdleSync(recipient: @escaping () -> Void) {
        let instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.waitForIdle(recipient)
    }

    func openDrawer(activityRule: XCUIApplication) {
        let sut = activityRule.launch()

        shortSleep()

        let drawerLayout = sut.descendants(matching: .any).matching(identifier: "drawer_layout").element
        drawerLayout.swipeRight()

        waitForIdleSync()

        screenshot(sut)
    }

    func getCurrentActivity() -> Activity? {
        var currentActivity: Activity?
        DispatchQueue.main.sync {
            let resumedActivities = ActivityLifecycleMonitorRegistry.shared.getActivitiesInStage(.resumed)
            if let activity = resumedActivities.first {
                currentActivity = activity
            }
        }
        return currentActivity
    }

    static func shortSleep() {
        do {
            try Thread.sleep(forTimeInterval: 2.0)
        } catch {
            print(error)
        }
    }

    func longSleep() {
        do {
            try Thread.sleep(forTimeInterval: 20.0)
        } catch {
            print(error)
        }
    }

    func sleep(seconds: Int) {
        do {
            try Thread.sleep(forTimeInterval: TimeInterval(seconds))
        } catch {
            print(error)
        }
    }

    func createFolder(remotePath: String) -> OCFile? {
        let check = ExistenceCheckRemoteOperation(remotePath: remotePath, isFolder: false).execute(client: client)

        if !check.isSuccess {
            assert(CreateFolderOperation(remotePath: remotePath, user: user, targetContext: targetContext, storageManager: getStorageManager())
                       .execute(client: client)
                       .isSuccess)
        }

        return getStorageManager().getFileByDecryptedRemotePath(remotePath.hasSuffix("/") ? remotePath : remotePath + "/")
    }

    func uploadFile(file: File, remotePath: String) {
        let ocUpload = OCUpload(file.getAbsolutePath(), remotePath, account.name)
        uploadOCUpload(ocUpload)
    }

    func uploadOCUpload(ocUpload: OCUpload) {
        let connectivityServiceMock = ConnectivityServiceMock()
        let powerManagementServiceMock = PowerManagementServiceMock()
        
        let accountManager = UserAccountManagerImpl.fromContext(targetContext)
        let uploadsStorageManager = UploadsStorageManager(accountManager: accountManager, contentResolver: targetContext.contentResolver)
        
        let newUpload = UploadFileOperation(
            uploadsStorageManager: uploadsStorageManager,
            connectivityService: connectivityServiceMock,
            powerManagementService: powerManagementServiceMock,
            user: user,
            file: nil,
            ocUpload: ocUpload,
            nameCollisionPolicy: .default,
            localBehaviour: .copy,
            context: targetContext,
            isInstantUpload: false,
            isCameraUpload: false,
            storageManager: getStorageManager()
        )
        
        newUpload.addRenameUploadListener {
            // dummy
        }
        
        newUpload.setRemoteFolderToBeCreated()
        
        let result = newUpload.execute(client: client)
        assert(result.isSuccess(), result.logMessage)
    }

    func enableRTL() {
        let locale = Locale(identifier: "ar")
        let resources = Bundle.main
        var config = resources.preferredLocalizations.first
        config = locale.identifier
        UserDefaults.standard.set([locale.identifier], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }

    func resetLocale() {
        let locale = Locale(identifier: "en")
        let resources = Bundle.main
        var config = resources.preferredLocalizations.first
        config = locale.identifier
        UserDefaults.standard.set([locale.identifier], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }

    func screenshot(view: UIView) {
        screenshot(view: view, "")
    }

    func screenshotViaName(activity: Activity, name: String) {
        if #available(iOS 14, *) {
            // iOS 14 equivalent code for taking a screenshot
        } else {
            // Fallback for earlier versions
        }
    }

    func screenshot(view: UIView, prefix: String) {
        if #available(iOS 14, *) {
            // iOS 14 and above specific code
        } else {
            // Assuming a similar functionality to Screenshot.snap(view).setName(createName(prefix)).record()
            // This part would need a custom implementation or third-party library in Swift
        }
    }

    func screenshot(_ sut: Activity) {
        if #available(iOS 14, *) {
            // iOS 14 equivalent code for taking a screenshot
        } else {
            Screenshot.snapActivity(sut).setName(createName()).record()
        }
    }

    func screenshot(dialogFragment: DialogFragment, prefix: String) {
        screenshot(view: dialogFragment.requireDialog().window?.decorView, prefix: prefix)
    }

    private func createName() -> String {
        return createName("")
    }

    func createName(name: String, prefix: String) -> String {
        var name = name
        
        if !prefix.isEmpty {
            name += "_\(prefix)"
        }
        
        if !DARK_MODE.isEmpty {
            name += "_\(DARK_MODE)"
        }
        
        if !COLOR.isEmpty {
            name += "_\(COLOR)"
        }
        
        return name
    }

    private func createName(prefix: String) -> String {
        let name = "\(TestNameDetector.getTestClass())_\(TestNameDetector.getTestName())"
        return createName(name, prefix: prefix)
    }

    static func getUserId(user: User) -> String? {
        return AccountManager.get(targetContext).getUserData(user.toPlatformAccount(), key: KEY_USER_ID)
    }

    func getRandomName() -> String {
        return getRandomName(5)
    }

    func getRandomName(length: Int) -> String {
        return RandomStringGenerator.make(length)
    }

    static func getUser(account: Account) throws -> User {
        let optionalUser = UserAccountManagerImpl.fromContext(targetContext).getUser(account.name)
        guard let user = optionalUser else {
            throw IllegalAccessError()
        }
        return user
    }

    static func createAccount(name: String) throws -> Account {
        let platformAccountManager = AccountManager.get(targetContext)
        
        let temp = Account(name, MainApp.getAccountType(targetContext))
        if let atPos = name.lastIndex(of: "@") {
            platformAccountManager.addAccountExplicitly(temp, "password", nil)
            platformAccountManager.setUserData(temp, AccountUtils.Constants.KEY_OC_BASE_URL, String(name[name.index(after: atPos)...]))
            platformAccountManager.setUserData(temp, KEY_USER_ID, String(name[..<atPos]))
        }
        
        if let account = UserAccountManagerImpl.fromContext(targetContext).getAccountByName(name) {
            return account
        } else {
            throw NSError(domain: "ActivityNotFoundException", code: 0, userInfo: nil)
        }
    }

    static func removeAccount(account: Account) -> Bool {
        return AccountManager.get(targetContext).removeAccountExplicitly(account)
    }
}
