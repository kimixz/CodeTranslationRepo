
import Foundation
import UIKit

class SyncFolderHandler: Handler {
    
    private static let TAG = String(describing: SyncFolderHandler.self)
    
    private var mService: OperationsService
    
    private var mPendingOperations = IndexedForest<SynchronizeFolderOperation>()
    
    private var mCurrentAccount: Account?
    private var mCurrentSyncOperation: SynchronizeFolderOperation?
    
    init(looper: Looper, service: OperationsService) {
        guard service != nil else {
            fatalError("Received invalid NULL in parameter 'service'")
        }
        self.mService = service
        super.init(looper: looper)
    }
    
    func isSynchronizing(user: User?, remotePath: String?) -> Bool {
        guard let user = user, let remotePath = remotePath else {
            return false
        }
        return mPendingOperations.contains(user.getAccountName(), remotePath)
    }
    
    override func handleMessage(_ msg: Message) {
        if let itemSyncKey = msg.obj as? (Account, String) {
            doOperation(account: itemSyncKey.0, remotePath: itemSyncKey.1)
            Log_OC.d(SyncFolderHandler.TAG, "Stopping after command with id \(msg.arg1)")
            mService.stopSelf(msg.arg1)
        }
    }
    
    private func doOperation(account: Account, remotePath: String) {
        mCurrentSyncOperation = mPendingOperations.get(account.name, remotePath)
        
        if let currentSyncOperation = mCurrentSyncOperation {
            var result: RemoteOperationResult
            
            do {
                if mCurrentAccount == nil || mCurrentAccount != account {
                    mCurrentAccount = account
                }
                
                let ocAccount = OwnCloudAccount(account: account, service: mService)
                let mOwnCloudClient = OwnCloudClientManagerFactory.getDefaultSingleton().getClientFor(ocAccount, service: mService)
                
                result = currentSyncOperation.execute(mOwnCloudClient)
                sendBroadcastFinishedSyncFolder(account: account, remotePath: remotePath, success: result.isSuccess())
                mService.dispatchResultToOperationListeners(currentSyncOperation, result: result)
                
            } catch let error as AccountsException {
                sendBroadcastFinishedSyncFolder(account: account, remotePath: remotePath, success: false)
                mService.dispatchResultToOperationListeners(currentSyncOperation, result: RemoteOperationResult(error: error))
                
                Log_OC.e(SyncFolderHandler.TAG, "Error while trying to get authorization", error)
            } catch let error as IOException {
                sendBroadcastFinishedSyncFolder(account: account, remotePath: remotePath, success: false)
                mService.dispatchResultToOperationListeners(currentSyncOperation, result: RemoteOperationResult(error: error))
                
                Log_OC.e(SyncFolderHandler.TAG, "Error while trying to get authorization", error)
            } finally {
                mPendingOperations.removePayload(account.name, remotePath)
            }
        }
    }
    
    func add(account: Account, remotePath: String, syncFolderOperation: SynchronizeFolderOperation) {
        let putResult = mPendingOperations.putIfAbsent(account.name, remotePath, syncFolderOperation)
        if putResult != nil {
            sendBroadcastNewSyncFolder(account: account, remotePath: remotePath)
        }
    }
    
    func cancel(account: Account?, file: OCFile?) {
        if account == nil || file == nil {
            Log_OC.e(SyncFolderHandler.TAG, "Cannot cancel with NULL parameters")
            return
        }
        let removeResult = mPendingOperations.remove(account!.name, file!.getRemotePath())
        let synchronization = removeResult?.first
        if synchronization != nil {
            synchronization?.cancel()
        } else {
            if mCurrentSyncOperation != nil && mCurrentAccount != nil &&
                mCurrentSyncOperation!.getRemotePath().hasPrefix(file!.getRemotePath()) &&
                account!.name == mCurrentAccount!.name {
                mCurrentSyncOperation?.cancel()
            }
        }
    }
    
    private func sendBroadcastNewSyncFolder(account: Account, remotePath: String) {
        let added = Intent(FileDownloadWorker.Companion.getDownloadAddedMessage())
        added.putExtra(FileDownloadWorker.EXTRA_ACCOUNT_NAME, account.name)
        added.putExtra(FileDownloadWorker.EXTRA_REMOTE_PATH, remotePath)
        added.setPackage(mService.packageName)
        LocalBroadcastManager.getInstance(mService.applicationContext).sendBroadcast(added)
    }
    
    private func sendBroadcastFinishedSyncFolder(account: Account, remotePath: String, success: Bool) {
        let finished = Intent(FileDownloadWorker.Companion.getDownloadFinishMessage())
        finished.putExtra(FileDownloadWorker.EXTRA_ACCOUNT_NAME, account.name)
        finished.putExtra(FileDownloadWorker.EXTRA_REMOTE_PATH, remotePath)
        finished.putExtra(FileDownloadWorker.EXTRA_DOWNLOAD_RESULT, success)
        finished.setPackage(mService.packageName)
        LocalBroadcastManager.getInstance(mService.applicationContext).sendBroadcast(finished)
    }
}
