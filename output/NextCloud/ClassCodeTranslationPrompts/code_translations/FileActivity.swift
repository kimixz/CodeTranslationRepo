
import UIKit

class FileActivity: DrawerActivity, OnRemoteOperationListener, ComponentsGetter, SslUntrustedCertDialog.OnSslUntrustedCertListener, LoadingVersionNumberTask.VersionDevInterface, FileDetailSharingFragment.OnEditShareListener, NetworkChangeListener {

    static let EXTRA_FILE = "com.owncloud.android.ui.activity.FILE"
    static let EXTRA_LIVE_PHOTO_FILE = "com.owncloud.android.ui.activity.LIVE.PHOTO.FILE"
    static let EXTRA_USER = "com.owncloud.android.ui.activity.USER"
    static let EXTRA_FROM_NOTIFICATION = "com.owncloud.android.ui.activity.FROM_NOTIFICATION"
    static let APP_OPENED_COUNT = "APP_OPENED_COUNT"
    static let EXTRA_SEARCH = "com.owncloud.android.ui.activity.SEARCH"
    static let EXTRA_SEARCH_QUERY = "com.owncloud.android.ui.activity.SEARCH_QUERY"

    static let TAG = String(describing: FileActivity.self)

    private static let DIALOG_WAIT_TAG = "DIALOG_WAIT"

    private static let KEY_WAITING_FOR_OP_ID = "WAITING_FOR_OP_ID"
    private static let KEY_ACTION_BAR_TITLE = "ACTION_BAR_TITLE"

    static let REQUEST_CODE__UPDATE_CREDENTIALS = 0
    static let REQUEST_CODE__LAST_SHARED = REQUEST_CODE__UPDATE_CREDENTIALS

    protected static let DELAY_TO_REQUEST_OPERATIONS_LATER: TimeInterval = 0.2

    /* Dialog tags */
    private static let DIALOG_UNTRUSTED_CERT = "DIALOG_UNTRUSTED_CERT"
    private static let DIALOG_CERT_NOT_SAVED = "DIALOG_CERT_NOT_SAVED"

    /** Main {@link OCFile} handled by the activity.*/
    private var mFile: OCFile?

    /** Flag to signal if the activity is launched by a notification */
    private var mFromNotification: Bool = false

    /** Messages handler associated to the main thread and the life cycle of the activity */
    private var mHandler: Handler?

    private var mFileOperationsHelper: FileOperationsHelper?

    private var mOperationsServiceConnection: ServiceConnection?

    private var mOperationsServiceBinder: OperationsServiceBinder?

    private var mResumed: Bool = false

    protected var fileDownloadProgressListener: FileDownloadWorker.FileDownloadProgressListener?
    protected var fileUploadHelper = FileUploadHelper.Companion.instance()

    @Inject
    var accountManager: UserAccountManager?

    @Inject
    var connectivityService: ConnectivityService?

    @Inject
    var backgroundJobManager: BackgroundJobManager?

    @Inject
    var editorUtils: EditorUtils?

    @Inject
    var usersAndGroupsSearchConfig: UsersAndGroupsSearchConfig?

    @Inject
    var arbitraryDataProvider: ArbitraryDataProvider?

    private var networkChangeReceiver: NetworkChangeReceiver?

    private func registerNetworkChangeReceiver() {
        let filter = NotificationCenter.default
        filter.addObserver(self, selector: #selector(networkChangeReceiver), name: NSNotification.Name.NSReachabilityChanged, object: nil)
    }

    func showFiles(onDeviceOnly: Bool, personalFiles: Bool) {
        // must be specialized in subclasses
        MainApp.showOnlyFilesOnDevice(onDeviceOnly)
        MainApp.showOnlyPersonalFiles(personalFiles)
        if onDeviceOnly {
            setupToolbar()
        } else {
            setupHomeSearchToolbarWithSortAndListButtons()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        networkChangeReceiver = NetworkChangeReceiver(context: self, connectivityService: connectivityService)
        usersAndGroupsSearchConfig?.reset()
        mHandler = Handler()
        mFileOperationsHelper = FileOperationsHelper(context: self, userAccountManager: getUserAccountManager(), connectivityService: connectivityService, editorUtils: editorUtils)
        var user: User?

        if let savedInstanceState = savedInstanceState {
            mFile = savedInstanceState.getParcelableArgument(key: FileActivity.EXTRA_FILE, type: OCFile.self)
            mFromNotification = savedInstanceState.getBoolean(FileActivity.EXTRA_FROM_NOTIFICATION)
            mFileOperationsHelper?.setOpIdWaitingFor(savedInstanceState.getLong(KEY_WAITING_FOR_OP_ID, defaultValue: Long.max))

            if let actionBar = getSupportActionBar(), !(self is PreviewImageActivity) {
                viewThemeUtils.files.themeActionBar(context: self, actionBar: actionBar, title: savedInstanceState.getString(KEY_ACTION_BAR_TITLE))
            }
        } else {
            user = getIntent().getParcelableArgument(key: FileActivity.EXTRA_USER, type: User.self)
            mFile = getIntent().getParcelableArgument(key: FileActivity.EXTRA_FILE, type: OCFile.self)
            mFromNotification = getIntent().getBooleanExtra(FileActivity.EXTRA_FROM_NOTIFICATION, defaultValue: false)

            if let user = user {
                setUser(user)
            }
        }

        mOperationsServiceConnection = OperationsServiceConnection()
        bindService(Intent(context: self, service: OperationsService.self), connection: mOperationsServiceConnection, flags: .autoCreate)
        registerNetworkChangeReceiver()
    }

    func networkAndServerConnectionListener(isNetworkAndServerAvailable: Bool) {
        if isNetworkAndServerAvailable {
            hideInfoBox()
            refreshList()
        } else {
            showInfoBox(message: R.string.offline_mode)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        fetchExternalLinks(false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        mResumed = true
        if mOperationsServiceBinder != nil {
            doOnResumeAndBound()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let operationsServiceBinder = mOperationsServiceBinder {
            operationsServiceBinder.removeOperationListener(self)
        }
        mResumed = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if mOperationsServiceConnection != nil {
            unbindService(mOperationsServiceConnection)
            mOperationsServiceBinder = nil
        }
        
        NotificationCenter.default.removeObserver(networkChangeReceiver)
    }

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        FileExtensions.logFileSize(mFile, tag: TAG)
        coder.encode(mFile, forKey: FileActivity.EXTRA_FILE)
        coder.encode(mFromNotification, forKey: FileActivity.EXTRA_FROM_NOTIFICATION)
        coder.encode(mFileOperationsHelper?.getOpIdWaitingFor(), forKey: KEY_WAITING_FOR_OP_ID)
        if let actionBar = navigationController?.navigationBar, let title = actionBar.topItem?.title {
            coder.encode(title, forKey: KEY_ACTION_BAR_TITLE)
        }
    }

    func getFile() -> OCFile? {
        return mFile
    }

    func setFile(_ file: OCFile) {
        mFile = file
    }

    func fromNotification() -> Bool {
        return mFromNotification
    }

    func getOperationsServiceBinder() -> OperationsServiceBinder? {
        return mOperationsServiceBinder
    }

    func newTransferenceServiceConnection() -> ServiceConnection? {
        return nil
    }

    func getRemoteOperationListener() -> OnRemoteOperationListener {
        return self
    }

    func getHandler() -> Handler {
        return mHandler
    }

    func getFileOperationsHelper() -> FileOperationsHelper {
        return mFileOperationsHelper
    }

    func onRemoteOperationFinish(operation: RemoteOperation?, result: RemoteOperationResult) {
        Log_OC.d(TAG, "Received result of operation in FileActivity - common behaviour for all the FileActivities")

        mFileOperationsHelper?.setOpIdWaitingFor(Long.max)

        dismissLoadingDialog()

        if !result.isSuccess() && (result.code == .unauthorized || (result.isException() && result.exception is AuthenticatorException)) {

            requestCredentialsUpdate(self)

            if result.code == .unauthorized {
                DisplayUtils.showSnackMessage(self, ErrorMessageAdapter.getErrorCauseMessage(result, operation, getResources()))
            }

        } else if !result.isSuccess() && result.code == .sslRecoverablePeerUnverified {

            showUntrustedCertDialog(result)

        } else if operation == nil ||
            operation is CreateShareWithShareeOperation ||
            operation is UnshareOperation ||
            operation is SynchronizeFolderOperation ||
            operation is UpdateShareViaLinkOperation ||
            operation is UpdateSharePermissionsOperation {

            if result.isSuccess() {
                updateFileFromDB()

            } else if result.code != .cancelled {
                DisplayUtils.showSnackMessage(self, ErrorMessageAdapter.getErrorCauseMessage(result, operation, getResources()))
            }

        } else if operation is SynchronizeFileOperation {
            onSynchronizeFileOperationFinish(operation as! SynchronizeFileOperation, result)

        } else if operation is GetSharesForFileOperation {
            if result.isSuccess() || result.code == .shareNotFound {
                updateFileFromDB()

            } else {
                DisplayUtils.showSnackMessage(self, ErrorMessageAdapter.getErrorCauseMessage(result, operation, getResources()))
            }
        }

        if operation is CreateShareViaLinkOperation {
            onCreateShareViaLinkOperationFinish(operation as! CreateShareViaLinkOperation, result)
        } else if operation is CreateShareWithShareeOperation {
            onUpdateShareInformation(result, R.string.sharee_add_failed)
        } else if operation is UpdateShareViaLinkOperation || operation is UpdateShareInfoOperation {
            onUpdateShareInformation(result, R.string.updating_share_failed)
        } else if operation is UpdateSharePermissionsOperation {
            onUpdateShareInformation(result, R.string.updating_share_failed)
        } else if operation is UnshareOperation {
            onUpdateShareInformation(result, R.string.unsharing_failed)
        } else if operation is UpdateNoteForShareOperation {
            onUpdateNoteForShareOperationFinish(result)
        }
    }

    func requestCredentialsUpdate(context: Context) {
        requestCredentialsUpdate(context: context, nil)
    }

    func requestCredentialsUpdate(context: Context, account: Account?) {
        var account = account
        if account == nil {
            account = getAccount()
        }

        let remoteWipeSupported = accountManager?.getServerVersion(account!).isRemoteWipeSupported() ?? false

        if remoteWipeSupported {
            CheckRemoteWipeTask(backgroundJobManager: backgroundJobManager, account: account!, reference: WeakReference(self)).execute()
        } else {
            performCredentialsUpdate(account: account!, context: context)
        }
    }

    func performCredentialsUpdate(account: Account, context: Context) {
        do {
            // step 1 - invalidate credentials of current account
            let ocAccount = OwnCloudAccount(account: account, context: context)
            if let client = OwnCloudClientManagerFactory.getDefaultSingleton().removeClientFor(ocAccount) {
                if let credentials = client.getCredentials() {
                    let accountManager = AccountManager.get(context)
                    if credentials.authTokenExpires() {
                        accountManager.invalidateAuthToken(account.type, credentials.getAuthToken())
                    } else {
                        accountManager.clearPassword(account)
                    }
                }
            }

            // step 2 - request credentials to user
            let updateAccountCredentials = Intent(context: context, AuthenticatorActivity.self)
            updateAccountCredentials.putExtra(AuthenticatorActivity.EXTRA_ACCOUNT, account)
            updateAccountCredentials.putExtra(
                AuthenticatorActivity.EXTRA_ACTION,
                AuthenticatorActivity.ACTION_UPDATE_EXPIRED_TOKEN)
            updateAccountCredentials.addFlags(Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
            startActivityForResult(updateAccountCredentials, REQUEST_CODE__UPDATE_CREDENTIALS)
        } catch com.owncloud.android.lib.common.accounts.AccountUtils.AccountNotFoundException {
            DisplayUtils.showSnackMessage(self, R.string.auth_account_does_not_exist)
        }
    }

    func showUntrustedCertDialog(result: RemoteOperationResult) {
        // Show a dialog with the certificate info
        let fm = self.supportFragmentManager
        var dialog = fm.findFragment(byTag: DIALOG_UNTRUSTED_CERT) as? SslUntrustedCertDialog
        if dialog == nil {
            dialog = SslUntrustedCertDialog.newInstanceForFullSslError(result.exception as! CertificateCombinedException)
            let ft = fm.beginTransaction()
            dialog?.show(ft, tag: DIALOG_UNTRUSTED_CERT)
        }
    }

    private func onSynchronizeFileOperationFinish(operation: SynchronizeFileOperation, result: RemoteOperationResult) {
        let syncedFile = operation.localFile
        if !result.isSuccess {
            if result.code == .syncConflict {
                let intent = ConflictsResolveActivity.createIntent(syncedFile: syncedFile, user: getUser() ?? { fatalError() }(), -1, nil, self)
                startActivity(intent)
            }
        } else {
            if !operation.transferWasRequested {
                DisplayUtils.showSnackMessage(self, ErrorMessageAdapter.getErrorCauseMessage(result: result, operation: operation, resources: getResources()))
            }
            supportInvalidateOptionsMenu()
        }
    }

    func updateFileFromDB() {
        if var file = getFile() {
            file = getStorageManager().getFileByPath(file.remotePath)
            setFile(file)
        }
    }

    func showLoadingDialog(message: String) {
        dismissLoadingDialog()

        DispatchQueue.main.async {
            let fragmentManager = self.supportFragmentManager
            let fragment = fragmentManager.findFragment(byTag: DIALOG_WAIT_TAG)
            if fragment == nil {
                print("\(TAG): show loading dialog")
                let loadingDialogFragment = LoadingDialog.newInstance(message: message)
                let fragmentTransaction = fragmentManager.beginTransaction()
                let isDialogFragmentReady = self.isDialogFragmentReady(fragment: loadingDialogFragment)
                if isDialogFragmentReady {
                    fragmentTransaction.add(loadingDialogFragment, DIALOG_WAIT_TAG)
                    fragmentTransaction.commitNow()
                }
            }
        }
    }

    func dismissLoadingDialog() {
        DispatchQueue.main.async {
            if let fragmentManager = self.navigationController?.viewControllers.last as? UIViewController {
                if let fragment = fragmentManager.children.first(where: { $0.restorationIdentifier == DIALOG_WAIT_TAG }) as? LoadingDialog {
                    print("dismiss loading dialog")
                    if fragment.isDialogFragmentReady() {
                        fragment.dismiss(animated: true, completion: nil)
                    }
                }
            }
        }
    }

    private func doOnResumeAndBound() {
        mOperationsServiceBinder?.addOperationListener(self, mHandler)
        let waitingForOpId = mFileOperationsHelper?.getOpIdWaitingFor() ?? Long.max
        if waitingForOpId <= Int32.max {
            let wait = mOperationsServiceBinder?.dispatchResultIfFinished(Int(waitingForOpId), self) ?? false
            if !wait {
                dismissLoadingDialog()
            }
        }
    }

    override func onServiceConnected(component: ComponentName, service: IBinder) {
        if component == ComponentName(self, OperationsService.self) {
            Log_OC.d(TAG, "Operations service connected")
            mOperationsServiceBinder = service as? OperationsServiceBinder
            /*if !(mOperationsServiceBinder?.isPerformingBlockingOperation() ?? true) {
                dismissLoadingDialog()
            }*/
            if mResumed {
                doOnResumeAndBound()
            }
        } else {
            return
        }
    }

    func onServiceDisconnected(component: ComponentName) {
        if component == ComponentName(FileActivity.self, OperationsService.self) {
            Log_OC.d(TAG, "Operations service disconnected")
            mOperationsServiceBinder = nil
            // TODO whatever could be waiting for the service is unbound
        }
    }

    func getFileDownloadProgressListener() -> FileDownloadWorker.FileDownloadProgressListener {
        return fileDownloadProgressListener
    }

    func getFileUploaderHelper() -> FileUploadHelper {
        return fileUploadHelper
    }

    func getCurrentDir() -> OCFile? {
        if let file = getFile() {
            if file.isFolder() {
                return file
            } else if let storageManager = getStorageManager() {
                let parentPath = file.getParentRemotePath()
                return storageManager.getFileByPath(parentPath)
            }
        }
        return nil
    }

    func onSavedCertificate() {
        // Nothing to do in this context
    }

    func onFailedSavingCertificate() {
        let dialog = ConfirmationDialogFragment.newInstance(
            R.string.ssl_validator_not_saved, arguments: [], requestCode: 0, positiveButtonText: R.string.common_ok, negativeButtonText: -1, neutralButtonText: -1
        )
        dialog.show(getSupportFragmentManager(), tag: DIALOG_CERT_NOT_SAVED)
    }

    func checkForNewDevVersionNecessary(context: Context) {
        if getResources().getBoolean(R.bool.dev_version_direct_download_enabled) {
            let arbitraryDataProvider = ArbitraryDataProviderImpl(self)
            let count = arbitraryDataProvider.getIntegerValue(FilesSyncHelper.GLOBAL, APP_OPENED_COUNT)

            if count > 10 || count == -1 {
                checkForNewDevVersion(self, context: context)
            }
        }
    }

    func returnVersion(latestVersion: Int) {
        showDevSnackbar(self, latestVersion, false, true)
    }

    static func checkForNewDevVersion(callback: LoadingVersionNumberTask.VersionDevInterface, context: Context) {
        let url = context.getString(R.string.dev_latest)
        let loadTask = LoadingVersionNumberTask(callback: callback)
        loadTask.execute(url: url)
    }

    func showDevSnackbar(activity: UIViewController, latestVersion: Int?, openDirectly: Bool, inBackground: Bool) {
        var currentVersion: Int = -1
        if let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            currentVersion = Int(version) ?? -1
        }

        if latestVersion == nil || currentVersion == -1 {
            DisplayUtils.showSnackMessage(activity: activity, message: "No version information available", duration: .long)
        }
        if let latestVersion = latestVersion, latestVersion > currentVersion {
            let devApkLink = "\(activity.getString(forKey: "dev_link"))\(latestVersion).apk"
            if openDirectly {
                DisplayUtils.startLinkIntent(activity: activity, url: devApkLink)
            } else {
                let snackbar = Snackbar.make(view: activity.view, message: "New version available", duration: .long)
                snackbar.setAction(title: activity.getString(forKey: "version_dev_download")) { _ in
                    DisplayUtils.startLinkIntent(activity: activity, url: devApkLink)
                }
                snackbar.show()
            }
        } else {
            if !inBackground {
                DisplayUtils.showSnackMessage(activity: activity, message: "No new version available", duration: .long)
            }
        }
    }

    static func copyAndShareFileLink(activity: FileActivity, file: OCFile, link: String, viewThemeUtils: ViewThemeUtils) {
        if MDMConfig.INSTANCE.shareViaLink(activity) && MDMConfig.INSTANCE.clipBoardSupport(activity) {
            ClipboardUtil.copyToClipboard(activity, link, false)
            let snackbar = Snackbar.make(view: activity.view, text: R.string.clipboard_text_copied, duration: .long)
                .setAction(R.string.share) { _ in
                    showShareLinkDialog(activity: activity, file: file, link: link)
                }
            viewThemeUtils.material.themeSnackbar(snackbar)
            snackbar.show()
        }
    }

    func showShareLinkDialog(activity: FileActivity, file: ServerFileInterface, link: String) {
        // Create dialog to allow the user choose an app to send the link
        let intentToShareLink = UIActivityViewController(activityItems: [link], applicationActivities: nil)
        
        var username: String?
        do {
            let oca = try OwnCloudAccount(account: activity.getAccount(), context: activity)
            if let displayName = oca.getDisplayName(), !displayName.isEmpty {
                username = displayName
            } else {
                username = AccountUtils.getUsernameForAccount(activity.getAccount())
            }
        } catch {
            username = AccountUtils.getUsernameForAccount(activity.getAccount())
        }
        
        if let username = username {
            intentToShareLink.setValue(activity.getString(R.string.subject_user_shared_with_you, username, file.getFileName()), forKey: "subject")
        } else {
            intentToShareLink.setValue(activity.getString(R.string.subject_shared_with_you, file.getFileName()), forKey: "subject")
        }
        
        let packagesToExclude = [activity.getPackageName()]
        let chooserDialog = ShareLinkToDialog.newInstance(intentToShareLink, packagesToExclude)
        chooserDialog.show(activity.getSupportFragmentManager(), FileDisplayActivity.FTAG_CHOOSER_DIALOG)
    }

    private func onUpdateNoteForShareOperationFinish(result: RemoteOperationResult) {
        let sharingFragment = getShareFileFragment()

        if result.isSuccess() {
            sharingFragment?.onUpdateShareInformation(result)
        } else {
            DisplayUtils.showSnackMessage(self, R.string.note_could_not_sent)
        }
    }

    private func onUpdateShareInformation(result: RemoteOperationResult, defaultError: Int) {
        var snackbar: Snackbar?
        let sharingFragment = getShareFileFragment()

        if result.isSuccess() {
            updateFileFromDB()
            sharingFragment?.onUpdateShareInformation(result: result)
        } else if let sharingFragment = sharingFragment, let view = sharingFragment.view {
            if result.message.isEmpty {
                snackbar = Snackbar.make(view, defaultError, Snackbar.LENGTH_LONG)
            } else {
                snackbar = Snackbar.make(view, result.message, Snackbar.LENGTH_LONG)
            }

            viewThemeUtils.material.themeSnackbar(snackbar)
            snackbar?.show()
        }
    }

    func refreshList() {
        if let fragment = self.navigationController?.viewControllers.first(where: { $0 is OCFileListFragment }) as? OCFileListFragment {
            fragment.onRefresh()
        } else if let fragment = self.navigationController?.viewControllers.first(where: { $0 is FileDetailFragment }) as? FileDetailFragment {
            fragment.goBackToOCFileListFragment()
        }
    }

    private func onCreateShareViaLinkOperationFinish(operation: CreateShareViaLinkOperation, result: RemoteOperationResult) {
        let sharingFragment = getShareFileFragment()
        let fileListFragment = getSupportFragmentManager().findFragment(byTag: FileDisplayActivity.TAG_LIST_OF_FILES)

        if result.isSuccess() {
            updateFileFromDB()

            var link = ""
            var file: OCFile? = nil
            for object in result.getData() {
                if let shareLink = object as? OCShare {
                    let shareType = shareLink.getShareType()

                    if shareType != nil && TAG_PUBLIC_LINK.caseInsensitiveCompare(shareType!.name()) == .orderedSame {
                        link = shareLink.getShareLink()
                        file = getStorageManager().getFileByEncryptedRemotePath(shareLink.getPath())
                        break
                    }
                }
            }

            copyAndShareFileLink(self, file, link, viewThemeUtils)

            if let sharingFragment = sharingFragment {
                sharingFragment.onUpdateShareInformation(result, file)
            }

            if let ocFileListFragment = fileListFragment as? OCFileListFragment, let file = file {
                if ocFileListFragment.getAdapterFiles().contains(file) {
                    ocFileListFragment.updateOCFile(file)
                } else {
                    DisplayUtils.showSnackMessage(self, R.string.file_activity_shared_file_cannot_be_updated)
                }
            }
        } else {
            let password = operation.getPassword()
            if result.getCode() == .SHARE_FORBIDDEN && password.isEmpty && getCapabilities().getFilesSharingPublicEnabled().isUnknown() {
                if let sharingFragment = sharingFragment, sharingFragment.isAdded() {
                    sharingFragment.requestPasswordForShareViaLink(true, getCapabilities().getFilesSharingPublicAskForOptionalPassword().isTrue())
                }
            } else {
                if let sharingFragment = sharingFragment {
                    sharingFragment.refreshSharesFromDB()
                }
                let snackbar = Snackbar.make(view: findViewById(android.R.id.content), text: ErrorMessageAdapter.getErrorCauseMessage(result, operation, getResources()), duration: .lengthLong)
                viewThemeUtils.material.themeSnackbar(snackbar)
                snackbar.show()
            }
        }
    }

    @available(*, deprecated)
    func getShareFileFragment() -> FileDetailSharingFragment? {
        var fragment = self.supportFragmentManager.findFragment(byTag: ShareActivity.TAG_SHARE_FRAGMENT)

        if fragment == nil {
            fragment = self.supportFragmentManager.findFragment(byTag: FileDisplayActivity.TAG_LIST_OF_FILES)
        }

        if let fileDetailSharingFragment = fragment as? FileDetailSharingFragment {
            return fileDetailSharingFragment
        } else if let fileDetailFragment = fragment as? FileDetailFragment {
            return fileDetailFragment.getFileDetailSharingFragment()
        } else {
            return nil
        }
    }

    override func onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        if UsersAndGroupsSearchProvider.ACTION_SHARE_WITH == intent.action {
            guard let data = intent.data else { return }
            let dataString = intent.dataString ?? ""
            let shareWith = dataString.substring(from: dataString.lastIndex(of: "/")!.utf16Offset(in: dataString) + 1)

            var existingSharees = [String]()
            for share in getStorageManager().getSharesWithForAFile(getFileFromDetailFragment().remotePath, getAccount().name) {
                existingSharees.append("\(share.shareType)_\(share.shareWith)")
            }

            let dataAuthority = data.authority ?? ""
            let shareType = UsersAndGroupsSearchProvider.getShareType(dataAuthority)

            if !existingSharees.contains("\(shareType)_\(shareWith)") {
                doShareWith(shareWith, shareType)
            } else {
                DisplayUtils.showSnackMessage(self, getString(R.string.sharee_already_added_to_file))
            }
        }
    }

    private func getFileFromDetailFragment() -> OCFile? {
        if let fragment = getFileDetailFragment() {
            return fragment.getFile()
        }
        return getFile()
    }

    func doShareWith(shareeName: String, shareType: ShareType) {
        if let fragment = getFileDetailFragment() {
            fragment.initiateSharingProcess(shareeName: shareeName, shareType: shareType, searchOnlyUsers: usersAndGroupsSearchConfig?.getSearchOnlyUsers() ?? false)
        }
    }

    func editExistingShare(share: OCShare, screenTypePermission: Int, isReshareShown: Bool, isExpiryDateShown: Bool) {
        if let fragment = getFileDetailFragment() {
            fragment.editExistingShare(share: share, screenTypePermission: screenTypePermission, isReshareShown: isReshareShown, isExpiryDateShown: isExpiryDateShown)
        }
    }

    override func onShareProcessClosed() {
        if let fragment = getFileDetailFragment() {
            fragment.showHideFragmentView(false)
        }
    }

    private func getFileDetailFragment() -> FileDetailFragment? {
        if let fragment = self.navigationController?.viewControllers.first(where: { $0 is FileDetailFragment }) as? FileDetailFragment {
            return fragment
        }
        return nil
    }
}
