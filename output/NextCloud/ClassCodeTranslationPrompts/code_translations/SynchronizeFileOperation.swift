
import Foundation

class SynchronizeFileOperation: SyncOperation {
    
    private static let TAG = String(describing: SynchronizeFileOperation.self)
    
    private var mLocalFile: OCFile?
    private var mRemotePath: String
    private var mServerFile: OCFile?
    private var mUser: User
    private var mSyncFileContents: Bool
    private var mContext: Context
    private var mTransferWasRequested: Bool = false
    private let syncInBackgroundWorker: Bool
    private var mAllowUploads: Bool
    
    init(remotePath: String, user: User, syncFileContents: Bool, context: Context, storageManager: FileDataStorageManager, syncInBackgroundWorker: Bool) {
        self.mRemotePath = remotePath
        self.mLocalFile = nil
        self.mServerFile = nil
        self.mUser = user
        self.mSyncFileContents = syncFileContents
        self.mContext = context
        self.mAllowUploads = true
        self.syncInBackgroundWorker = syncInBackgroundWorker
        super.init(storageManager: storageManager)
    }
    
    init(localFile: OCFile, serverFile: OCFile?, user: User, syncFileContents: Bool, context: Context, storageManager: FileDataStorageManager, syncInBackgroundWorker: Bool) {
        self.mLocalFile = localFile
        self.mServerFile = serverFile
        if let localFile = mLocalFile {
            self.mRemotePath = localFile.getRemotePath()
            if let serverFile = mServerFile, serverFile.getRemotePath() != mRemotePath {
                fatalError("serverFile and localFile do not correspond to the same OC file")
            }
        } else if let serverFile = mServerFile {
            self.mRemotePath = serverFile.getRemotePath()
        } else {
            fatalError("Both serverFile and localFile are NULL")
        }
        self.mUser = user
        self.mSyncFileContents = syncFileContents
        self.mContext = context
        self.mAllowUploads = true
        self.syncInBackgroundWorker = syncInBackgroundWorker
        super.init(storageManager: storageManager)
    }
    
    init(localFile: OCFile, serverFile: OCFile?, user: User, syncFileContents: Bool, allowUploads: Bool, context: Context, storageManager: FileDataStorageManager, syncInBackgroundWorker: Bool) {
        self.mAllowUploads = allowUploads
        super.init(storageManager: storageManager)
        self.mLocalFile = localFile
        self.mServerFile = serverFile
        if let localFile = mLocalFile {
            self.mRemotePath = localFile.getRemotePath()
            if let serverFile = mServerFile, serverFile.getRemotePath() != mRemotePath {
                fatalError("serverFile and localFile do not correspond to the same OC file")
            }
        } else if let serverFile = mServerFile {
            self.mRemotePath = serverFile.getRemotePath()
        } else {
            fatalError("Both serverFile and localFile are NULL")
        }
        self.mUser = user
        self.mSyncFileContents = syncFileContents
        self.mContext = context
        self.syncInBackgroundWorker = syncInBackgroundWorker
    }
    
    override func run(client: OwnCloudClient) -> RemoteOperationResult {
        var result: RemoteOperationResult? = nil
        mTransferWasRequested = false
        
        if mLocalFile == nil {
            mLocalFile = getStorageManager().getFileByPath(mRemotePath)
        }
        
        if !mLocalFile!.isDown() {
            requestForDownload(file: mLocalFile!)
            result = RemoteOperationResult(resultCode: .ok)
        } else {
            if mServerFile == nil {
                let operation = ReadFileRemoteOperation(remotePath: mRemotePath)
                result = operation.execute(client: client)
                
                if result!.isSuccess() {
                    mServerFile = FileStorageUtils.fillOCFile(remoteFile: result!.getData()[0] as! RemoteFile)
                    mServerFile!.setLastSyncDateForProperties(Date().timeIntervalSince1970)
                } else if result!.getCode() != .fileNotFound {
                    return result!
                }
            }
            
            if let serverFile = mServerFile {
                let serverChanged: Bool
                if mLocalFile!.getEtag().isEmpty {
                    serverChanged = serverFile.getModificationTimestamp() != mLocalFile!.getModificationTimestampAtLastSyncForData()
                } else {
                    serverChanged = serverFile.getEtag() != mLocalFile!.getEtag()
                }
                let localChanged = mLocalFile!.getLocalModificationTimestamp() > mLocalFile!.getLastSyncDateForData()
                
                if localChanged && serverChanged {
                    result = RemoteOperationResult(resultCode: .syncConflict)
                    getStorageManager().saveConflict(mLocalFile!, serverFile.getEtag())
                    
                } else if localChanged {
                    if mSyncFileContents && mAllowUploads {
                        requestForUpload(file: mLocalFile!)
                    } else {
                        Log_OC.d(SynchronizeFileOperation.TAG, "Nothing to do here")
                    }
                    result = RemoteOperationResult(resultCode: .ok)
                    
                } else if serverChanged {
                    mLocalFile!.setRemoteId(serverFile.getRemoteId())
                    
                    if mSyncFileContents {
                        requestForDownload(file: mLocalFile!)
                    } else {
                        serverFile.setFavorite(mLocalFile!.isFavorite())
                        serverFile.setHidden(mLocalFile!.shouldHide())
                        serverFile.setLastSyncDateForData(mLocalFile!.getLastSyncDateForData())
                        serverFile.setStoragePath(mLocalFile!.getStoragePath())
                        serverFile.setParentId(mLocalFile!.getParentId())
                        serverFile.setEtag(mLocalFile!.getEtag())
                        getStorageManager().saveFile(serverFile)
                    }
                    result = RemoteOperationResult(resultCode: .ok)
                    
                } else {
                    result = RemoteOperationResult(resultCode: .ok)
                }
                
                if result!.getCode() != .syncConflict {
                    getStorageManager().saveConflict(mLocalFile!, nil)
                }
            } else {
                let deleteResult = getStorageManager().removeFile(mLocalFile!, true, true)
                
                if deleteResult {
                    result = RemoteOperationResult(resultCode: .fileNotFound)
                } else {
                    Log_OC.e(SynchronizeFileOperation.TAG, "Removal of local copy failed (remote file does not exist any longer).")
                }
            }
        }
        
        Log_OC.i(SynchronizeFileOperation.TAG, "Synchronizing \(mUser.getAccountName()), file \(mLocalFile!.getRemotePath()): \(result!.getLogMessage())")
        
        return result!
    }
    
    private func requestForUpload(file: OCFile) {
        FileUploadHelper.instance().uploadUpdatedFile(
            user: mUser,
            files: [file],
            localBehaviour: .move,
            nameCollisionPolicy: .overwrite
        )
        
        mTransferWasRequested = true
    }
    
    private func requestForDownload(file: OCFile) {
        let fileDownloadHelper = FileDownloadHelper.instance()
        
        if syncInBackgroundWorker {
            Log_OC.d("InternalTwoWaySyncWork", "download file: \(file.getFileName())")
            
            do {
                let operation = DownloadFileOperation(user: mUser, file: file, context: mContext)
                let result = try operation.execute(client: getClient())
                
                mTransferWasRequested = true
                
                if let filename = file.getFileName() {
                    if result.isSuccess() {
                        fileDownloadHelper.saveFile(file: file, operation: operation, storageManager: getStorageManager())
                        Log_OC.d(SynchronizeFileOperation.TAG, "requestForDownload completed for: \(file.getFileName())")
                    } else {
                        Log_OC.d(SynchronizeFileOperation.TAG, "requestForDownload failed for: \(file.getFileName())")
                    }
                }
            } catch {
                Log_OC.d(SynchronizeFileOperation.TAG, "Exception caught at requestForDownload \(error)")
            }
        } else {
            fileDownloadHelper.downloadFile(user: mUser, file: file)
        }
    }
    
    func transferWasRequested() -> Bool {
        return mTransferWasRequested
    }
    
    func getLocalFile() -> OCFile? {
        return mLocalFile
    }
}
