
import Foundation
import UIKit

class OperationsService: Service {
    private static let TAG = String(describing: OperationsService.self)

    public static let EXTRA_ACCOUNT = "ACCOUNT"
    public static let EXTRA_SERVER_URL = "SERVER_URL"
    public static let EXTRA_REMOTE_PATH = "REMOTE_PATH"
    public static let EXTRA_NEWNAME = "NEWNAME"
    public static let EXTRA_REMOVE_ONLY_LOCAL = "REMOVE_LOCAL_COPY"
    public static let EXTRA_SYNC_FILE_CONTENTS = "SYNC_FILE_CONTENTS"
    public static let EXTRA_NEW_PARENT_PATH = "NEW_PARENT_PATH"
    public static let EXTRA_FILE = "FILE"
    public static let EXTRA_FILE_VERSION = "FILE_VERSION"
    public static let EXTRA_SHARE_PASSWORD = "SHARE_PASSWORD"
    public static let EXTRA_SHARE_TYPE = "SHARE_TYPE"
    public static let EXTRA_SHARE_WITH = "SHARE_WITH"
    public static let EXTRA_SHARE_EXPIRATION_DATE_IN_MILLIS = "SHARE_EXPIRATION_YEAR"
    public static let EXTRA_SHARE_PERMISSIONS = "SHARE_PERMISSIONS"
    public static let EXTRA_SHARE_PUBLIC_LABEL = "SHARE_PUBLIC_LABEL"
    public static let EXTRA_SHARE_HIDE_FILE_DOWNLOAD = "HIDE_FILE_DOWNLOAD"
    public static let EXTRA_SHARE_ID = "SHARE_ID"
    public static let EXTRA_SHARE_NOTE = "SHARE_NOTE"
    public static let EXTRA_IN_BACKGROUND = "IN_BACKGROUND"

    public static let ACTION_CREATE_SHARE_VIA_LINK = "CREATE_SHARE_VIA_LINK"
    public static let ACTION_CREATE_SECURE_FILE_DROP = "CREATE_SECURE_FILE_DROP"
    public static let ACTION_CREATE_SHARE_WITH_SHAREE = "CREATE_SHARE_WITH_SHAREE"
    public static let ACTION_UNSHARE = "UNSHARE"
    public static let ACTION_UPDATE_PUBLIC_SHARE = "UPDATE_PUBLIC_SHARE"
    public static let ACTION_UPDATE_USER_SHARE = "UPDATE_USER_SHARE"
    public static let ACTION_UPDATE_SHARE_NOTE = "UPDATE_SHARE_NOTE"
    public static let ACTION_UPDATE_SHARE_INFO = "UPDATE_SHARE_INFO"
    public static let ACTION_GET_SERVER_INFO = "GET_SERVER_INFO"
    public static let ACTION_GET_USER_NAME = "GET_USER_NAME"
    public static let ACTION_RENAME = "RENAME"
    public static let ACTION_REMOVE = "REMOVE"
    public static let ACTION_CREATE_FOLDER = "CREATE_FOLDER"
    public static let ACTION_SYNC_FILE = "SYNC_FILE"
    public static let ACTION_SYNC_FOLDER = "SYNC_FOLDER"
    public static let ACTION_MOVE_FILE = "MOVE_FILE"
    public static let ACTION_COPY_FILE = "COPY_FILE"
    public static let ACTION_CHECK_CURRENT_CREDENTIALS = "CHECK_CURRENT_CREDENTIALS"
    public static let ACTION_RESTORE_VERSION = "RESTORE_VERSION"

    private var mOperationsHandler: ServiceHandler!
    private var mOperationsBinder: OperationsServiceBinder!

    private var mSyncFolderHandler: SyncFolderHandler!

    private var mUndispatchedFinishedOperations = [Int: (RemoteOperation, RemoteOperationResult)]()

    @Inject var accountManager: UserAccountManager!
    @Inject var arbitraryDataProvider: ArbitraryDataProvider!

    private class Target {
        var mServerUrl: URL?
        var mAccount: Account?

        init(account: Account?, serverUrl: URL?) {
            mAccount = account
            mServerUrl = serverUrl
        }
    }

    override func onCreate() {
        super.onCreate()
        AndroidInjection.inject(self)
        Log_OC.d(OperationsService.TAG, "Creating service")

        let thread = HandlerThread(name: "Operations thread", priority: Process.THREAD_PRIORITY_BACKGROUND)
        thread.start()
        mOperationsHandler = ServiceHandler(looper: thread.looper, service: self)
        mOperationsBinder = OperationsServiceBinder(handler: mOperationsHandler)

        let syncFolderThread = HandlerThread(name: "Syncfolder thread", priority: Process.THREAD_PRIORITY_BACKGROUND)
        syncFolderThread.start()
        mSyncFolderHandler = SyncFolderHandler(looper: syncFolderThread.looper, service: self)
    }

    override func onStartCommand(intent: Intent?, flags: Int, startId: Int) -> Int {
        Log_OC.d(OperationsService.TAG, "Starting command with id \(startId)")

        if let intent = intent, intent.action == OperationsService.ACTION_SYNC_FOLDER {
            if !intent.hasExtra(OperationsService.EXTRA_ACCOUNT) || !intent.hasExtra(OperationsService.EXTRA_REMOTE_PATH) {
                Log_OC.e(OperationsService.TAG, "Not enough information provided in intent")
                return START_NOT_STICKY
            }

            let account: Account? = intent.getParcelableExtra(OperationsService.EXTRA_ACCOUNT)
            let remotePath: String? = intent.getStringExtra(OperationsService.EXTRA_REMOTE_PATH)

            if let account = account, let remotePath = remotePath {
                let itemSyncKey = (account, remotePath)

                if let itemToQueue = newOperation(intent: intent) {
                    mSyncFolderHandler.add(account: account,
                                           remotePath: remotePath,
                                           operation: itemToQueue.1 as! SynchronizeFolderOperation)
                    let msg = mSyncFolderHandler.obtainMessage()
                    msg.arg1 = startId
                    msg.obj = itemSyncKey
                    mSyncFolderHandler.sendMessage(msg)
                }
            }
        } else {
            let msg = mOperationsHandler.obtainMessage()
            msg.arg1 = startId
            mOperationsHandler.sendMessage(msg)
        }

        return START_NOT_STICKY
    }

    override func onDestroy() {
        Log_OC.v(OperationsService.TAG, "Destroying service")
        OwnCloudClientManagerFactory.getDefaultSingleton().saveAllClients(self, MainApp.getAccountType(getApplicationContext()))

        mUndispatchedFinishedOperations.removeAll()

        mOperationsBinder = nil

        mOperationsHandler.looper.quit()
        mOperationsHandler = nil

        mSyncFolderHandler.looper.quit()
        mSyncFolderHandler = nil

        super.onDestroy()
    }

    override func onBind(intent: Intent) -> IBinder? {
        return mOperationsBinder
    }

    override func onUnbind(intent: Intent) -> Bool {
        mOperationsBinder.clearListeners()
        return false
    }

    public class OperationsServiceBinder: Binder {
        private var mBoundListeners = [OnRemoteOperationListener: Handler]()

        private var mServiceHandler: ServiceHandler

        init(handler: ServiceHandler) {
            mServiceHandler = handler
        }

        func cancel(account: Account, file: OCFile) {
            mSyncFolderHandler.cancel(account: account, file: file)
        }

        func clearListeners() {
            mBoundListeners.removeAll()
        }

        func addOperationListener(listener: OnRemoteOperationListener, callbackHandler: Handler) {
            objc_sync_enter(mBoundListeners)
            defer { objc_sync_exit(mBoundListeners) }
            mBoundListeners[listener] = callbackHandler
        }

        func removeOperationListener(listener: OnRemoteOperationListener) {
            objc_sync_enter(mBoundListeners)
            defer { objc_sync_exit(mBoundListeners) }
            mBoundListeners.removeValue(forKey: listener)
        }

        func isPerformingBlockingOperation() -> Bool {
            return !mServiceHandler.mPendingOperations.isEmpty
        }

        func queueNewOperation(operationIntent: Intent) -> Int {
            let itemToQueue = newOperation(operationIntent: operationIntent)
            if let item = itemToQueue {
                mServiceHandler.mPendingOperations.append(item)
                startService(Intent(context: self, service: OperationsService.self))
                return item.1.hashValue
            } else {
                return Int.max
            }
        }

        func dispatchResultIfFinished(operationId: Int, listener: OnRemoteOperationListener) -> Bool {
            if let undispatched = mUndispatchedFinishedOperations.removeValue(forKey: operationId) {
                listener.onRemoteOperationFinish(operation: undispatched.0, result: undispatched.1)
                return true
            } else {
                return !mServiceHandler.mPendingOperations.isEmpty
            }
        }

        func isSynchronizing(user: User, file: OCFile) -> Bool {
            return mSyncFolderHandler.isSynchronizing(user: user, remotePath: file.getRemotePath())
        }
    }

    private class ServiceHandler: Handler {
        private var mService: OperationsService

        private var mPendingOperations = [(Target, RemoteOperation)]()
        private var mCurrentOperation: RemoteOperation?
        private var mLastTarget: Target?
        private var mOwnCloudClient: OwnCloudClient?

        init(looper: Looper, service: OperationsService) {
            mService = service
            super.init(looper: looper)
        }

        override func handleMessage(_ msg: Message) {
            nextOperation()
            Log_OC.d(OperationsService.TAG, "Stopping after command with id \(msg.arg1)")
            mService.stopSelf(msg.arg1)
        }

        private func nextOperation() {
            var next: (Target, RemoteOperation)?
            objc_sync_enter(mPendingOperations)
            next = mPendingOperations.first
            objc_sync_exit(mPendingOperations)

            if let next = next {
                mCurrentOperation = next.1
                var result: RemoteOperationResult
                var ocAccount: OwnCloudAccount?

                do {
                    if mLastTarget == nil || mLastTarget != next.0 {
                        mLastTarget = next.0
                        if let account = mLastTarget?.mAccount {
                            ocAccount = OwnCloudAccount(account, mService)
                        } else {
                            ocAccount = OwnCloudAccount(mLastTarget?.mServerUrl, nil)
                        }
                        mOwnCloudClient = OwnCloudClientManagerFactory.getDefaultSingleton().getClientFor(ocAccount, mService)
                    }

                    do {
                        result = try mCurrentOperation!.execute(mOwnCloudClient)
                    } catch is UnsupportedOperationException {
                        if ocAccount == nil {
                            throw e
                        }
                        let nextcloudClient = OwnCloudClientManagerFactory.getDefaultSingleton().getNextcloudClientFor(ocAccount, mService.getBaseContext())
                        result = mCurrentOperation!.run(nextcloudClient)
                    }
                } catch let e as AccountsException {
                    if mLastTarget?.mAccount == nil {
                        Log_OC.e(OperationsService.TAG, "Error while trying to get authorization for a NULL account", e)
                    } else {
                        Log_OC.e(OperationsService.TAG, "Error while trying to get authorization for \(mLastTarget?.mAccount.name ?? "")", e)
                    }
                    result = RemoteOperationResult(e)
                } catch let e as IOException {
                    if mLastTarget?.mAccount == nil {
                        Log_OC.e(OperationsService.TAG, "Error while trying to get authorization for a NULL account", e)
                    } else {
                        Log_OC.e(OperationsService.TAG, "Error while trying to get authorization for \(mLastTarget?.mAccount.name ?? "")", e)
                    }
                    result = RemoteOperationResult(e)
                } catch {
                    if mLastTarget?.mAccount == nil {
                        Log_OC.e(OperationsService.TAG, "Unexpected error for a NULL account", error)
                    } else {
                        Log_OC.e(OperationsService.TAG, "Unexpected error for \(mLastTarget?.mAccount.name ?? "")", error)
                    }
                    result = RemoteOperationResult(error)
                } finally {
                    objc_sync_enter(mPendingOperations)
                    mPendingOperations.removeFirst()
                    objc_sync_exit(mPendingOperations)
                }

                mService.dispatchResultToOperationListeners(mCurrentOperation!, result)
            }
        }
    }

    private func newOperation(operationIntent: Intent) -> (Target?, RemoteOperation?)? {
        var operation: RemoteOperation? = nil
        var target: Target? = nil
        do {
            if !operationIntent.hasExtra(OperationsService.EXTRA_ACCOUNT) && !operationIntent.hasExtra(OperationsService.EXTRA_SERVER_URL) {
                Log_OC.e(OperationsService.TAG, "Not enough information provided in intent")
            } else {
                let account: Account? = operationIntent.getParcelableArgument(OperationsService.EXTRA_ACCOUNT, Account.self)
                let user = toUser(account)
                let serverUrl = operationIntent.getStringExtra(OperationsService.EXTRA_SERVER_URL)
                target = Target(account: account, serverUrl: serverUrl == nil ? nil : URL(string: serverUrl!))

                let action = operationIntent.getAction()
                var remotePath: String?
                var password: String?
                var shareType: ShareType?
                var newParentPath: String?
                var shareId: Int64

                let fileDataStorageManager = FileDataStorageManager(user: user, contentResolver: getContentResolver())

                switch action {
                case OperationsService.ACTION_CREATE_SHARE_VIA_LINK:
                    remotePath = operationIntent.getStringExtra(OperationsService.EXTRA_REMOTE_PATH)
                    password = operationIntent.getStringExtra(OperationsService.EXTRA_SHARE_PASSWORD)
                    if !remotePath.isEmpty {
                        operation = CreateShareViaLinkOperation(remotePath: remotePath!, password: password, fileDataStorageManager: fileDataStorageManager)
                    }
                    
                case OperationsService.ACTION_CREATE_SECURE_FILE_DROP:
                    remotePath = operationIntent.getStringExtra(OperationsService.EXTRA_REMOTE_PATH)
                    operation = CreateShareViaLinkOperation(remotePath: remotePath!, fileDataStorageManager: fileDataStorageManager, permissionFlag: OCShare.CREATE_PERMISSION_FLAG)
                    
                case OperationsService.ACTION_UPDATE_PUBLIC_SHARE:
                    shareId = operationIntent.getLongExtra(OperationsService.EXTRA_SHARE_ID, defaultValue: -1)
                    if shareId > 0 {
                        let updateLinkOperation = UpdateShareViaLinkOperation(shareId: shareId, fileDataStorageManager: fileDataStorageManager)
                        password = operationIntent.getStringExtra(OperationsService.EXTRA_SHARE_PASSWORD)
                        updateLinkOperation.setPassword(password)
                        let expirationDate = operationIntent.getLongExtra(OperationsService.EXTRA_SHARE_EXPIRATION_DATE_IN_MILLIS, defaultValue: 0)
                        updateLinkOperation.setExpirationDateInMillis(expirationDate)
                        let hideFileDownload = operationIntent.getBooleanExtra(OperationsService.EXTRA_SHARE_HIDE_FILE_DOWNLOAD, defaultValue: false)
                        updateLinkOperation.setHideFileDownload(hideFileDownload)
                        if operationIntent.hasExtra(OperationsService.EXTRA_SHARE_PUBLIC_LABEL) {
                            updateLinkOperation.setLabel(operationIntent.getStringExtra(OperationsService.EXTRA_SHARE_PUBLIC_LABEL))
                        }
                        operation = updateLinkOperation
                    }
                    
                case OperationsService.ACTION_UPDATE_USER_SHARE:
                    shareId = operationIntent.getLongExtra(OperationsService.EXTRA_SHARE_ID, defaultValue: -1)
                    if shareId > 0 {
                        let updateShare = UpdateSharePermissionsOperation(shareId: shareId, fileDataStorageManager: fileDataStorageManager)
                        let permissions = operationIntent.getIntExtra(OperationsService.EXTRA_SHARE_PERMISSIONS, defaultValue: -1)
                        updateShare.setPermissions(permissions)
                        let expirationDateInMillis = operationIntent.getLongExtra(OperationsService.EXTRA_SHARE_EXPIRATION_DATE_IN_MILLIS, defaultValue: 0)
                        updateShare.setExpirationDateInMillis(expirationDateInMillis)
                        password = operationIntent.getStringExtra(OperationsService.EXTRA_SHARE_PASSWORD)
                        updateShare.setPassword(password)
                        operation = updateShare
                    }
                    
                case OperationsService.ACTION_UPDATE_SHARE_NOTE:
                    shareId = operationIntent.getLongExtra(OperationsService.EXTRA_SHARE_ID, defaultValue: -1)
                    let note = operationIntent.getStringExtra(OperationsService.EXTRA_SHARE_NOTE)
                    if shareId > 0 {
                        operation = UpdateNoteForShareOperation(shareId: shareId, note: note, fileDataStorageManager: fileDataStorageManager)
                    }
                    
                case OperationsService.ACTION_CREATE_SHARE_WITH_SHAREE:
                    remotePath = operationIntent.getStringExtra(OperationsService.EXTRA_REMOTE_PATH)
                    let shareeName = operationIntent.getStringExtra(OperationsService.EXTRA_SHARE_WITH)
                    shareType = operationIntent.getSerializableArgument(OperationsService.EXTRA_SHARE_TYPE, ShareType.self)
                    let permissions = operationIntent.getIntExtra(OperationsService.EXTRA_SHARE_PERMISSIONS, defaultValue: -1)
                    let noteMessage = operationIntent.getStringExtra(OperationsService.EXTRA_SHARE_NOTE)
                    let sharePassword = operationIntent.getStringExtra(OperationsService.EXTRA_SHARE_PASSWORD)
                    let expirationDateInMillis = operationIntent.getLongExtra(OperationsService.EXTRA_SHARE_EXPIRATION_DATE_IN_MILLIS, defaultValue: 0)
                    let hideFileDownload = operationIntent.getBooleanExtra(OperationsService.EXTRA_SHARE_HIDE_FILE_DOWNLOAD, defaultValue: false)
                    if !remotePath.isEmpty {
                        let createShareWithShareeOperation = CreateShareWithShareeOperation(remotePath: remotePath!, shareeName: shareeName, shareType: shareType, permissions: permissions, noteMessage: noteMessage, sharePassword: sharePassword, expirationDateInMillis: expirationDateInMillis, hideFileDownload: hideFileDownload, fileDataStorageManager: fileDataStorageManager, applicationContext: getApplicationContext(), user: user, arbitraryDataProvider: arbitraryDataProvider)
                        if operationIntent.hasExtra(OperationsService.EXTRA_SHARE_PUBLIC_LABEL) {
                            createShareWithShareeOperation.setLabel(operationIntent.getStringExtra(OperationsService.EXTRA_SHARE_PUBLIC_LABEL))
                        }
                        operation = createShareWithShareeOperation
                    }
                    
                case OperationsService.ACTION_UPDATE_SHARE_INFO:
                    shareId = operationIntent.getLongExtra(OperationsService.EXTRA_SHARE_ID, defaultValue: -1)
                    if shareId > 0 {
                        let updateShare = UpdateShareInfoOperation(shareId: shareId, fileDataStorageManager: fileDataStorageManager)
                        let permissionsToChange = operationIntent.getIntExtra(OperationsService.EXTRA_SHARE_PERMISSIONS, defaultValue: -1)
                        updateShare.setPermissions(permissionsToChange)
                        let expirationDateInMills = operationIntent.getLongExtra(OperationsService.EXTRA_SHARE_EXPIRATION_DATE_IN_MILLIS, defaultValue: 0)
                        updateShare.setExpirationDateInMillis(expirationDateInMills)
                        password = operationIntent.getStringExtra(OperationsService.EXTRA_SHARE_PASSWORD)
                        updateShare.setPassword(password)
                        let fileDownloadHide = operationIntent.getBooleanExtra(OperationsService.EXTRA_SHARE_HIDE_FILE_DOWNLOAD, defaultValue: false)
                        updateShare.setHideFileDownload(fileDownloadHide)
                        if operationIntent.hasExtra(OperationsService.EXTRA_SHARE_PUBLIC_LABEL) {
                            updateShare.setLabel(operationIntent.getStringExtra(OperationsService.EXTRA_SHARE_PUBLIC_LABEL))
                        }
                        operation = updateShare
                    }
                    
                case OperationsService.ACTION_UNSHARE:
                    remotePath = operationIntent.getStringExtra(OperationsService.EXTRA_REMOTE_PATH)
                    shareId = operationIntent.getLongExtra(OperationsService.EXTRA_SHARE_ID, defaultValue: -1)
                    if shareId > 0 {
                        operation = UnshareOperation(remotePath: remotePath!, shareId: shareId, fileDataStorageManager: fileDataStorageManager, user: user, applicationContext: getApplicationContext())
                    }
                    
                case OperationsService.ACTION_GET_SERVER_INFO:
                    operation = GetServerInfoOperation(serverUrl: serverUrl, context: self)
                    
                case OperationsService.ACTION_GET_USER_NAME:
                    operation = GetUserInfoRemoteOperation()
                    
                case OperationsService.ACTION_RENAME:
                    remotePath = operationIntent.getStringExtra(OperationsService.EXTRA_REMOTE_PATH)
                    let newName = operationIntent.getStringExtra(OperationsService.EXTRA_NEWNAME)
                    operation = RenameFileOperation(remotePath: remotePath!, newName: newName, fileDataStorageManager: fileDataStorageManager)
                    
                case OperationsService.ACTION_REMOVE:
                    let file: OCFile? = operationIntent.getParcelableArgument(OperationsService.EXTRA_FILE, OCFile.self)
                    let onlyLocalCopy = operationIntent.getBooleanExtra(OperationsService.EXTRA_REMOVE_ONLY_LOCAL, defaultValue: false)
                    let inBackground = operationIntent.getBooleanExtra(OperationsService.EXTRA_IN_BACKGROUND, defaultValue: false)
                    operation = RemoveFileOperation(file: file, onlyLocalCopy: onlyLocalCopy, user: user, inBackground: inBackground, applicationContext: getApplicationContext(), fileDataStorageManager: fileDataStorageManager)
                    
                case OperationsService.ACTION_CREATE_FOLDER:
                    remotePath = operationIntent.getStringExtra(OperationsService.EXTRA_REMOTE_PATH)
                    operation = CreateFolderOperation(remotePath: remotePath!, user: user, applicationContext: getApplicationContext(), fileDataStorageManager: fileDataStorageManager)
                    
                case OperationsService.ACTION_SYNC_FILE:
                    remotePath = operationIntent.getStringExtra(OperationsService.EXTRA_REMOTE_PATH)
                    let syncFileContents = operationIntent.getBooleanExtra(OperationsService.EXTRA_SYNC_FILE_CONTENTS, defaultValue: true)
                    operation = SynchronizeFileOperation(remotePath: remotePath!, user: user, syncFileContents: syncFileContents, applicationContext: getApplicationContext(), fileDataStorageManager: fileDataStorageManager, isFolder: false)
                    
                case OperationsService.ACTION_SYNC_FOLDER:
                    remotePath = operationIntent.getStringExtra(OperationsService.EXTRA_REMOTE_PATH)
                    operation = SynchronizeFolderOperation(context: self, remotePath: remotePath!, user: user, fileDataStorageManager: fileDataStorageManager, isFolder: false)
                    
                case OperationsService.ACTION_MOVE_FILE:
                    remotePath = operationIntent.getStringExtra(OperationsService.EXTRA_REMOTE_PATH)
                    newParentPath = operationIntent.getStringExtra(OperationsService.EXTRA_NEW_PARENT_PATH)
                    operation = MoveFileOperation(remotePath: remotePath!, newParentPath: newParentPath!, fileDataStorageManager: fileDataStorageManager)
                    
                case OperationsService.ACTION_COPY_FILE:
                    remotePath = operationIntent.getStringExtra(OperationsService.EXTRA_REMOTE_PATH)
                    newParentPath = operationIntent.getStringExtra(OperationsService.EXTRA_NEW_PARENT_PATH)
                    operation = CopyFileOperation(remotePath: remotePath!, newParentPath: newParentPath!, fileDataStorageManager: fileDataStorageManager)
                    
                case OperationsService.ACTION_CHECK_CURRENT_CREDENTIALS:
                    operation = CheckCurrentCredentialsOperation(user: user, fileDataStorageManager: fileDataStorageManager)
                    
                case OperationsService.ACTION_RESTORE_VERSION:
                    let fileVersion: FileVersion? = operationIntent.getParcelableArgument(OperationsService.EXTRA_FILE_VERSION, FileVersion.self)
                    operation = RestoreFileVersionRemoteOperation(localId: fileVersion?.localId, fileName: fileVersion?.fileName)
                    
                default:
                    break
                }
            }
        } catch {
            Log_OC.e(OperationsService.TAG, "Bad information provided in intent: \(error.localizedDescription)")
            operation = nil
        }

        if let operation = operation {
            return (target, operation)
        } else {
            return nil
        }
    }

    private func toUser(account: Account?) -> User {
        let accountName = account?.name ?? ""
        if let user = accountManager.getUser(accountName) {
            return user
        } else {
            return accountManager.getAnonymousUser()
        }
    }

    func dispatchResultToOperationListeners(operation: RemoteOperation, result: RemoteOperationResult) {
        var count = 0

        if let operationsBinder = mOperationsBinder {
            for (listener, handler) in operationsBinder.mBoundListeners {
                handler?.post {
                    listener.onRemoteOperationFinish(operation: operation, result: result)
                }
                count += 1
            }
        }

        if count == 0 {
            let undispatched = (operation, result)
            mUndispatchedFinishedOperations[operation.hashValue] = undispatched
        }

        Log_OC.d(OperationsService.TAG, "Called \(count) listeners")
    }
}
