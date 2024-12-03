
import Foundation

class SynchronizeFolderOperation: SyncOperation {
    private static let TAG = String(describing: SynchronizeFolderOperation.self)
    
    private var mRemotePath: String
    private var user: User
    private var mContext: Context
    private var mLocalFolder: OCFile?
    private var mConflictsFound: Int = 0
    private var mFailsInFileSyncsFound: Int = 0
    private var mRemoteFolderChanged: Bool = false
    private var mFilesForDirectDownload: [OCFile] = []
    private var mFilesToSyncContents: [SyncOperation] = []
    private var mCancellationRequested: AtomicBoolean = AtomicBoolean(false)
    private var syncInBackgroundWorker: Bool
    
    init(context: Context, remotePath: String, user: User, storageManager: FileDataStorageManager, syncInBackgroundWorker: Bool) {
        self.mRemotePath = remotePath
        self.user = user
        self.mContext = context
        self.syncInBackgroundWorker = syncInBackgroundWorker
        super.init(storageManager: storageManager)
    }
    
    override func run(client: OwnCloudClient) -> RemoteOperationResult {
        var result: RemoteOperationResult
        mFailsInFileSyncsFound = 0
        mConflictsFound = 0
        
        do {
            mLocalFolder = getStorageManager().getFileByPath(mRemotePath)
            result = try checkForChanges(client: client)
            
            if result.isSuccess {
                if mRemoteFolderChanged {
                    result = try fetchAndSyncRemoteFolder(client: client)
                } else {
                    try prepareOpsFromLocalKnowledge()
                }
                
                if result.isSuccess {
                    try syncContents(client: client)
                }
            }
            
            if mCancellationRequested.get() {
                throw OperationCancelledException()
            }
            
        } catch let e as OperationCancelledException {
            result = RemoteOperationResult(e)
        } catch {
            result = RemoteOperationResult(error)
        }
        
        return result
    }
    
    private func checkForChanges(client: OwnCloudClient) throws -> RemoteOperationResult {
        Log_OC.d(SynchronizeFolderOperation.TAG, "Checking changes in \(user.accountName)\(mRemotePath)")
        
        mRemoteFolderChanged = true
        
        if mCancellationRequested.get() {
            throw OperationCancelledException()
        }
        
        let operation = ReadFileRemoteOperation(remotePath: mRemotePath)
        var result = operation.execute(client: client)
        if result.isSuccess() {
            if let remoteFile = result.getData().first as? RemoteFile {
                let remoteFolder = FileStorageUtils.fillOCFile(remoteFile)
                
                mRemoteFolderChanged = !(remoteFolder.etag.caseInsensitiveCompare(mLocalFolder?.etag ?? "") == .orderedSame)
                
                result = RemoteOperationResult(code: .OK)
                
                Log_OC.i(SynchronizeFolderOperation.TAG, "Checked \(user.accountName)\(mRemotePath) : " +
                        (mRemoteFolderChanged ? "changed" : "not changed"))
            }
        } else {
            if result.getCode() == .FILE_NOT_FOUND {
                removeLocalFolder()
            }
            if result.isException() {
                Log_OC.e(SynchronizeFolderOperation.TAG, "Checked \(user.accountName)\(mRemotePath) : " +
                        result.getLogMessage(), result.getException())
            } else {
                Log_OC.e(SynchronizeFolderOperation.TAG, "Checked \(user.accountName)\(mRemotePath) : " +
                        result.getLogMessage())
            }
        }
        
        return result
    }
    
    private func fetchAndSyncRemoteFolder(client: OwnCloudClient) throws -> RemoteOperationResult {
        if mCancellationRequested.get() {
            throw OperationCancelledException()
        }
        
        let operation = ReadFolderRemoteOperation(mRemotePath)
        var result = operation.execute(client)
        Log_OC.d(SynchronizeFolderOperation.TAG, "Synchronizing \(user.getAccountName())\(mRemotePath)")
        Log_OC.d(SynchronizeFolderOperation.TAG, "Synchronizing remote id\(mLocalFolder?.getRemoteId() ?? "")")
        
        if result.isSuccess() {
            try synchronizeData(folderAndFiles: result.getData())
            if mConflictsFound > 0 || mFailsInFileSyncsFound > 0 {
                result = RemoteOperationResult(ResultCode.SYNC_CONFLICT)
            }
        } else {
            if result.getCode() == ResultCode.FILE_NOT_FOUND {
                removeLocalFolder()
            }
        }
        
        return result
    }
    
    private func removeLocalFolder() {
        let storageManager = getStorageManager()
        if storageManager.fileExists(mLocalFolder?.getFileId() ?? "") {
            let currentSavePath = FileStorageUtils.getSavePath(user.getAccountName())
            storageManager.removeFolder(
                mLocalFolder,
                true,
                mLocalFolder?.isDown() ?? false && (mLocalFolder?.getStoragePath() ?? "").hasPrefix(currentSavePath)
            )
        }
    }
    
    private func synchronizeData(folderAndFiles: [Any]) throws {
        guard let remoteFolder = FileStorageUtils.fillOCFile(folderAndFiles[0] as! RemoteFile) else {
            return
        }
        remoteFolder.setParentId(mLocalFolder?.getParentId() ?? "")
        remoteFolder.setFileId(mLocalFolder?.getFileId() ?? "")
        
        Log_OC.d(SynchronizeFolderOperation.TAG, "Remote folder \(mLocalFolder?.getRemotePath() ?? "") changed - starting update of local data ")
        
        mFilesForDirectDownload.removeAll()
        mFilesToSyncContents.removeAll()
        
        if mCancellationRequested.get() {
            throw OperationCancelledException()
        }
        
        let storageManager = getStorageManager()
        
        let encryptedAncestor = FileStorageUtils.checkEncryptionStatus(remoteFolder, storageManager: storageManager)
        mLocalFolder?.setEncrypted(encryptedAncestor)
        
        mLocalFolder?.setPermissions(remoteFolder.getPermissions())
        mLocalFolder?.setRichWorkspace(remoteFolder.getRichWorkspace())
        
        let object = RefreshFolderOperation.getDecryptedFolderMetadata(encryptedAncestor: encryptedAncestor,
                                                                       mLocalFolder: mLocalFolder,
                                                                       getClient: getClient(),
                                                                       user: user,
                                                                       mContext: mContext)
        if mLocalFolder?.isEncrypted() ?? false && object == nil {
            fatalError("metadata is null!")
        }
        
        var localFilesMap: [String: OCFile]
        var e2EVersion: E2EVersion
        
        if let metadataV1 = object as? DecryptedFolderMetadataFileV1 {
            e2EVersion = .V1_2
            localFilesMap = RefreshFolderOperation.prefillLocalFilesMap(metadataV1,
                                                                        storageManager.getFolderContent(mLocalFolder, false))
        } else {
            e2EVersion = .V2_0
            localFilesMap = RefreshFolderOperation.prefillLocalFilesMap(object as! DecryptedFolderMetadataFile,
                                                                        storageManager.getFolderContent(mLocalFolder, false))
        }
        
        var updatedFiles = [OCFile]()
        for i in 1..<folderAndFiles.count {
            let remote = folderAndFiles[i] as! RemoteFile
            guard let remoteFile = FileStorageUtils.fillOCFile(remote) else {
                continue
            }
            
            guard let updatedFile = FileStorageUtils.fillOCFile(remote) else {
                continue
            }
            updatedFile.setParentId(mLocalFolder?.getFileId() ?? "")
            
            var localFile = localFilesMap.removeValue(forKey: remoteFile.getRemotePath())
            
            if localFile == nil {
                localFile = storageManager.getFileByPath(updatedFile.getRemotePath())
            }
            
            updateLocalStateData(remoteFile: remoteFile, localFile: localFile, updatedFile: updatedFile)
            
            FileStorageUtils.searchForLocalFileInDefaultPath(updatedFile, user.getAccountName())
            
            if e2EVersion == .V1_2 {
                RefreshFolderOperation.updateFileNameForEncryptedFileV1(storageManager: storageManager,
                                                                        metadata: object as! DecryptedFolderMetadataFileV1,
                                                                        updatedFile: updatedFile)
            } else {
                RefreshFolderOperation.updateFileNameForEncryptedFile(storageManager: storageManager,
                                                                      metadata: object as! DecryptedFolderMetadataFile,
                                                                      updatedFile: updatedFile)
            }
            
            let encrypted = updatedFile.isEncrypted() || (mLocalFolder?.isEncrypted() ?? false)
            updatedFile.setEncrypted(encrypted)
            
            try classifyFileForLaterSyncOrDownload(remoteFile: remoteFile, localFile: localFile)
            
            updatedFiles.append(updatedFile)
        }
        
        if e2EVersion == .V1_2 {
            RefreshFolderOperation.updateFileNameForEncryptedFileV1(storageManager: storageManager,
                                                                    metadata: object as! DecryptedFolderMetadataFileV1,
                                                                    mLocalFolder: mLocalFolder)
        } else {
            RefreshFolderOperation.updateFileNameForEncryptedFile(storageManager: storageManager,
                                                                  metadata: object as! DecryptedFolderMetadataFile,
                                                                  mLocalFolder: mLocalFolder)
        }
        
        storageManager.saveFolder(remoteFolder, updatedFiles: updatedFiles, localFilesMap.values)
        mLocalFolder?.setLastSyncDateForData(Date().timeIntervalSince1970)
        storageManager.saveFile(mLocalFolder)
    }
    
    private func updateLocalStateData(remoteFile: OCFile, localFile: OCFile?, updatedFile: OCFile) {
        updatedFile.setLastSyncDateForProperties(Date().timeIntervalSince1970 * 1000)
        if let localFile = localFile {
            updatedFile.setFileId(localFile.getFileId())
            updatedFile.setLastSyncDateForData(localFile.getLastSyncDateForData())
            updatedFile.setModificationTimestampAtLastSyncForData(localFile.getModificationTimestampAtLastSyncForData())
            updatedFile.setStoragePath(localFile.getStoragePath())
            updatedFile.setEtag(localFile.getEtag())
            if updatedFile.isFolder() {
                updatedFile.setFileLength(localFile.getFileLength())
            } else if mRemoteFolderChanged && MimeTypeUtil.isImage(remoteFile) &&
                        remoteFile.getModificationTimestamp() != localFile.getModificationTimestamp() {
                updatedFile.setUpdateThumbnailNeeded(true)
                Log_OC.d(SynchronizeFolderOperation.TAG, "Image \(remoteFile.getFileName()) updated on the server")
            }
            updatedFile.setSharedViaLink(localFile.isSharedViaLink())
            updatedFile.setSharedWithSharee(localFile.isSharedWithSharee())
            updatedFile.setEtagInConflict(localFile.getEtagInConflict())
        } else {
            updatedFile.setEtag("")
        }
    }
    
    private func classifyFileForLaterSyncOrDownload(remoteFile: OCFile, localFile: OCFile?) throws {
        if remoteFile.isFolder() {
            objc_sync_enter(mCancellationRequested)
            defer { objc_sync_exit(mCancellationRequested) }
            if mCancellationRequested.boolValue {
                throw OperationCancelledException()
            }
            startSyncFolderOperation(path: remoteFile.getRemotePath())
        } else {
            let operation = SynchronizeFileOperation(
                localFile: localFile,
                remoteFile: remoteFile,
                user: user,
                isSync: true,
                context: mContext,
                storageManager: getStorageManager(),
                syncInBackgroundWorker: syncInBackgroundWorker
            )
            mFilesToSyncContents.append(operation)
        }
    }
    
    private func prepareOpsFromLocalKnowledge() throws {
        let children = getStorageManager().getFolderContent(mLocalFolder, false)
        for child in children {
            if !child.isFolder() {
                if !child.isDown() {
                    mFilesForDirectDownload.append(child)
                } else {
                    let operation = SynchronizeFileOperation(
                        file: child,
                        conflictFile: child.getEtagInConflict() != nil ? child : nil,
                        user: user,
                        isUserInitiated: true,
                        context: mContext,
                        storageManager: getStorageManager(),
                        syncInBackgroundWorker: syncInBackgroundWorker
                    )
                    mFilesToSyncContents.append(operation)
                }
            }
        }
    }
    
    private func syncContents(client: OwnCloudClient) throws {
        startDirectDownloads()
        try startContentSynchronizations(filesToSyncContents: mFilesToSyncContents)
        updateETag(client: client)
    }
    
    private func updateETag(client: OwnCloudClient) {
        let operation = ReadFolderRemoteOperation(remotePath: mRemotePath)
        let result = operation.execute(client: client)
        
        if let remoteFile = result.getData().first as? RemoteFile {
            let eTag = remoteFile.etag
            mLocalFolder?.setEtag(eTag)
            
            let storageManager = getStorageManager()
            storageManager.saveFile(mLocalFolder)
        }
    }
    
    private func startDirectDownloads() {
        let fileDownloadHelper = FileDownloadHelper.instance()
        
        if syncInBackgroundWorker {
            do {
                for file in mFilesForDirectDownload {
                    objc_sync_enter(mCancellationRequested)
                    defer { objc_sync_exit(mCancellationRequested) }
                    if mCancellationRequested.boolValue {
                        break
                    }
                    
                    guard let file = file else {
                        continue
                    }
                    
                    let operation = DownloadFileOperation(user: user, file: file, context: mContext)
                    let result = operation.execute(getClient())
                    
                    guard let filename = file.fileName else {
                        continue
                    }
                    
                    if result.isSuccess {
                        fileDownloadHelper.saveFile(file, operation: operation, storageManager: getStorageManager())
                        Log_OC.d(SynchronizeFolderOperation.TAG, "startDirectDownloads completed for: \(file.fileName ?? "")")
                    } else {
                        Log_OC.d(SynchronizeFolderOperation.TAG, "startDirectDownloads failed for: \(file.fileName ?? "")")
                    }
                }
            } catch {
                Log_OC.d(SynchronizeFolderOperation.TAG, "Exception caught at startDirectDownloads \(error)")
            }
        } else {
            mFilesForDirectDownload.forEach { file in
                fileDownloadHelper.downloadFile(user: user, file: file)
            }
        }
    }
    
    private func startContentSynchronizations(filesToSyncContents: [SyncOperation]) throws {
        Log_OC.v(SynchronizeFolderOperation.TAG, "Starting content synchronization... ")
        for op in filesToSyncContents {
            if mCancellationRequested.get() {
                throw OperationCancelledException()
            }
            let contentsResult = op.execute(mContext)
            if !contentsResult.isSuccess() {
                if contentsResult.getCode() == .SYNC_CONFLICT {
                    mConflictsFound += 1
                } else {
                    mFailsInFileSyncsFound += 1
                    if let exception = contentsResult.getException() {
                        Log_OC.e(SynchronizeFolderOperation.TAG, "Error while synchronizing file : \(contentsResult.getLogMessage())", exception)
                    } else {
                        Log_OC.e(SynchronizeFolderOperation.TAG, "Error while synchronizing file : \(contentsResult.getLogMessage())")
                    }
                }
            }
        }
    }
    
    private func searchForLocalFileInDefaultPath(file: OCFile) {
        if file.getStoragePath() == nil && !file.isFolder() {
            let path = FileStorageUtils.getDefaultSavePathFor(user.getAccountName(), file)
            let f = FileManager.default.fileExists(atPath: path)
            if f {
                file.setStoragePath(path)
                if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                   let modificationDate = attributes[.modificationDate] as? Date {
                    file.setLastSyncDateForData(modificationDate.timeIntervalSince1970)
                }
            }
        }
    }
    
    func cancel() {
        mCancellationRequested.set(true)
    }
    
    func getFolderPath() -> String {
        let path = mLocalFolder?.getStoragePath() ?? ""
        if !path.isEmpty {
            return path
        }
        return FileStorageUtils.getDefaultSavePathFor(user.accountName, mLocalFolder)
    }
    
    private func startSyncFolderOperation(path: String) {
        let intent = Intent(context: mContext, service: OperationsService.self)
        intent.action = OperationsService.ACTION_SYNC_FOLDER
        intent.putExtra(key: OperationsService.EXTRA_ACCOUNT, value: user.toPlatformAccount())
        intent.putExtra(key: OperationsService.EXTRA_REMOTE_PATH, value: path)
        mContext.startService(intent)
    }
    
    func getRemotePath() -> String {
        return mRemotePath
    }
}
