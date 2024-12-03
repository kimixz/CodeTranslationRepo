
import Foundation

class RefreshFolderOperation: RemoteOperation {
    private static let TAG = String(describing: RefreshFolderOperation.self)
    
    public static let EVENT_SINGLE_FOLDER_CONTENTS_SYNCED = "\(RefreshFolderOperation.self).EVENT_SINGLE_FOLDER_CONTENTS_SYNCED"
    public static let EVENT_SINGLE_FOLDER_SHARES_SYNCED = "\(RefreshFolderOperation.self).EVENT_SINGLE_FOLDER_SHARES_SYNCED"
    
    private let mCurrentSyncTime: Int64
    private var mLocalFolder: OCFile
    private let fileDataStorageManager: FileDataStorageManager
    private let user: User
    private let mContext: Context
    private var mChildren: [OCFile] = []
    private var mConflictsFound: Int = 0
    private var mFailsInKeptInSyncFound: Int = 0
    private var mForgottenLocalFiles: [String: String] = [:]
    private let mSyncFullAccount: Bool
    private var mRemoteFolderChanged: Bool = false
    private let mIgnoreETag: Bool
    private let mOnlyFileMetadata: Bool
    private var mFilesToSyncContents: [SynchronizeFileOperation] = []
    
    init(folder: OCFile, currentSyncTime: Int64, syncFullAccount: Bool, ignoreETag: Bool, dataStorageManager: FileDataStorageManager, user: User, context: Context) {
        self.mLocalFolder = folder
        self.mCurrentSyncTime = currentSyncTime
        self.mSyncFullAccount = syncFullAccount
        self.fileDataStorageManager = dataStorageManager
        self.user = user
        self.mContext = context
        self.mIgnoreETag = ignoreETag
        self.mOnlyFileMetadata = false
    }
    
    init(folder: OCFile, currentSyncTime: Int64, syncFullAccount: Bool, ignoreETag: Bool, onlyFileMetadata: Bool, dataStorageManager: FileDataStorageManager, user: User, context: Context) {
        self.mLocalFolder = folder
        self.mCurrentSyncTime = currentSyncTime
        self.mSyncFullAccount = syncFullAccount
        self.fileDataStorageManager = dataStorageManager
        self.user = user
        self.mContext = context
        self.mIgnoreETag = ignoreETag
        self.mOnlyFileMetadata = onlyFileMetadata
    }
    
    func getConflictsFound() -> Int {
        return mConflictsFound
    }
    
    func getFailsInKeptInSyncFound() -> Int {
        return mFailsInKeptInSyncFound
    }
    
    func getForgottenLocalFiles() -> [String: String] {
        return mForgottenLocalFiles
    }
    
    func getChildren() -> [OCFile] {
        return mChildren
    }
    
    override func run(client: OwnCloudClient) -> RemoteOperationResult {
        var result: RemoteOperationResult
        mFailsInKeptInSyncFound = 0
        mConflictsFound = 0
        mForgottenLocalFiles.removeAll()
        
        if OCFile.ROOT_PATH == mLocalFolder.remotePath && !mSyncFullAccount && !mOnlyFileMetadata {
            updateOCVersion(client: client)
            updateUserProfile()
        }
        
        result = checkForChanges(client: client)
        
        if result.isSuccess() {
            if mRemoteFolderChanged {
                result = fetchAndSyncRemoteFolder(client: client)
            } else {
                mChildren = fileDataStorageManager.getFolderContent(mLocalFolder, false)
            }
            
            if result.isSuccess() {
                startContentSynchronizations(filesToSyncContents: mFilesToSyncContents)
            } else {
                mLocalFolder.etag = ""
            }
            
            mLocalFolder.lastSyncDateForData = Date().timeIntervalSince1970
            fileDataStorageManager.saveFile(mLocalFolder)
        }
        
        checkFolderConflictData(result: result)
        
        if !mSyncFullAccount && mRemoteFolderChanged {
            sendLocalBroadcast(event: RefreshFolderOperation.EVENT_SINGLE_FOLDER_CONTENTS_SYNCED, dirRemotePath: mLocalFolder.remotePath, result: result)
        }
        
        if result.isSuccess() && !mSyncFullAccount && !mOnlyFileMetadata {
            refreshSharesForFolder(client: client)
        }
        
        if !mSyncFullAccount {
            sendLocalBroadcast(event: RefreshFolderOperation.EVENT_SINGLE_FOLDER_SHARES_SYNCED, dirRemotePath: mLocalFolder.remotePath, result: result)
        }
        
        return result
    }
    
    private func checkFolderConflictData(result: RemoteOperationResult) {
        let offlineOperations = fileDataStorageManager.offlineOperationDao.getAll()
        if offlineOperations.isEmpty { return }
        
        let conflictData = RemoteOperationResultExtensionsKt.getConflictedRemoteIdsWithOfflineOperations(result, offlineOperations, fileDataStorageManager)
        if let conflictData = conflictData, conflictData != lastConflictData {
            lastConflictData = conflictData
            sendFolderSyncConflictEventBroadcast(conflictData: conflictData)
        }
    }
    
    private func sendFolderSyncConflictEventBroadcast(conflictData: [String: String]) {
        let intent = Intent(action: FileDisplayActivity.FOLDER_SYNC_CONFLICT)
        intent.putExtra(FileDisplayActivity.FOLDER_SYNC_CONFLICT_ARG_REMOTE_IDS_TO_OPERATION_PATHS, conflictData)
        LocalBroadcastManager.getInstance(context: mContext).sendBroadcast(intent)
    }
    
    private func updateOCVersion(client: OwnCloudClient) {
        let update = UpdateOCVersionOperation(user: user, context: mContext)
        let result = update.execute(client: client)
        if result.isSuccess() {
            updateCapabilities()
        }
    }
    
    private func updateUserProfile() {
        do {
            let nextcloudClient = try OwnCloudClientFactory.createNextcloudClient(user: user, context: mContext)
            let result = try GetUserProfileOperation(fileDataStorageManager: fileDataStorageManager).execute(client: nextcloudClient)
            if !result.isSuccess {
                Log_OC.w(RefreshFolderOperation.TAG, "Couldn't update user profile from server")
            } else {
                Log_OC.i(RefreshFolderOperation.TAG, "Got display name: \(result.getResultData())")
            }
        } catch {
            Log_OC.e(self, "Error updating profile", error)
        }
    }
    
    private func updateCapabilities() {
        let arbitraryDataProvider = ArbitraryDataProviderImpl(context: mContext)
        let oldDirectEditingEtag = arbitraryDataProvider.getValue(user, key: ArbitraryDataProvider.DIRECT_EDITING_ETAG)
        
        let result = GetCapabilitiesOperation(fileDataStorageManager: fileDataStorageManager).execute(context: mContext)
        if result.isSuccess() {
            let newDirectEditingEtag = fileDataStorageManager.getCapability(user.accountName).getDirectEditingEtag()
            
            if !oldDirectEditingEtag.caseInsensitiveCompare(newDirectEditingEtag).rawValue == 0 {
                updateDirectEditing(arbitraryDataProvider: arbitraryDataProvider, newDirectEditingEtag: newDirectEditingEtag)
            }
            
            updatePredefinedStatus(arbitraryDataProvider: arbitraryDataProvider)
        } else {
            Log_OC.w(RefreshFolderOperation.TAG, "Update Capabilities unsuccessfully")
        }
    }
    
    private func updateDirectEditing(arbitraryDataProvider: ArbitraryDataProvider, newDirectEditingEtag: String) {
        let result = DirectEditingObtainRemoteOperation().executeNextcloudClient(user: user, context: mContext)
        
        if result.isSuccess {
            if let directEditing = result.getResultData() {
                let json = try? JSONEncoder().encode(directEditing)
                if let jsonString = String(data: json!, encoding: .utf8) {
                    arbitraryDataProvider.storeOrUpdateKeyValue(accountName: user.getAccountName(), key: ArbitraryDataProvider.DIRECT_EDITING, value: jsonString)
                }
            }
        } else {
            arbitraryDataProvider.deleteKeyForAccount(accountName: user.getAccountName(), key: ArbitraryDataProvider.DIRECT_EDITING)
        }
        
        arbitraryDataProvider.storeOrUpdateKeyValue(accountName: user.getAccountName(), key: ArbitraryDataProvider.DIRECT_EDITING_ETAG, value: newDirectEditingEtag)
    }
    
    private func updatePredefinedStatus(arbitraryDataProvider: ArbitraryDataProvider) {
        var client: NextcloudClient
        
        do {
            client = try OwnCloudClientFactory.createNextcloudClient(user: user, context: mContext)
        } catch {
            Log_OC.e(self, "Update of predefined status not possible!")
            return
        }
        
        let result = GetPredefinedStatusesRemoteOperation().execute(client: client)
        
        if result.isSuccess {
            if let predefinedStatuses = result.getResultData() {
                let json = try? JSONEncoder().encode(predefinedStatuses)
                if let jsonString = String(data: json!, encoding: .utf8) {
                    arbitraryDataProvider.storeOrUpdateKeyValue(accountName: user.accountName, key: ArbitraryDataProvider.PREDEFINED_STATUS, value: jsonString)
                }
            }
        } else {
            arbitraryDataProvider.deleteKeyForAccount(accountName: user.accountName, key: ArbitraryDataProvider.PREDEFINED_STATUS)
        }
    }
    
    private func checkForChanges(client: OwnCloudClient) -> RemoteOperationResult {
        mRemoteFolderChanged = true
        var result: RemoteOperationResult
        let remotePath = mLocalFolder.getRemotePath()
        
        Log_OC.d(RefreshFolderOperation.TAG, "Checking changes in \(user.getAccountName())\(remotePath)")
        
        result = ReadFileRemoteOperation(remotePath: remotePath).execute(client: client)
        
        if result.isSuccess() {
            if let remoteFile = result.getData().first as? RemoteFile {
                let remoteFolder = FileStorageUtils.fillOCFile(remoteFile)
                
                if !mIgnoreETag {
                    if let remoteFolderETag = remoteFolder.getEtag() {
                        mRemoteFolderChanged = !(remoteFolderETag.caseInsensitiveCompare(mLocalFolder.getEtag()) == .orderedSame)
                    } else {
                        Log_OC.e(RefreshFolderOperation.TAG, "Checked \(user.getAccountName())\(remotePath): No ETag received from server")
                    }
                }
                
                result = RemoteOperationResult(resultCode: .OK)
                
                Log_OC.i(RefreshFolderOperation.TAG, "Checked \(user.getAccountName())\(remotePath) : " +
                    (mRemoteFolderChanged ? "changed" : "not changed"))
            }
        } else {
            if result.getCode() == .FILE_NOT_FOUND {
                removeLocalFolder()
            }
            if result.isException() {
                Log_OC.e(RefreshFolderOperation.TAG, "Checked \(user.getAccountName())\(remotePath) : " +
                    result.getLogMessage(), result.getException())
            } else {
                Log_OC.e(RefreshFolderOperation.TAG, "Checked \(user.getAccountName())\(remotePath) : " +
                    result.getLogMessage())
            }
        }
        
        return result
    }
    
    private func fetchAndSyncRemoteFolder(client: OwnCloudClient) -> RemoteOperationResult {
        let remotePath = mLocalFolder.getRemotePath()
        var result = ReadFolderRemoteOperation(remotePath: remotePath).execute(client: client)
        Log_OC.d(RefreshFolderOperation.TAG, "Refresh folder \(user.getAccountName())\(remotePath)")
        Log_OC.d(RefreshFolderOperation.TAG, "Refresh folder with remote id \(mLocalFolder.getRemoteId())")
        
        if result.isSuccess() {
            synchronizeData(folderAndFiles: result.getData())
            if mConflictsFound > 0 || mFailsInKeptInSyncFound > 0 {
                result = RemoteOperationResult(code: .SYNC_CONFLICT)
            }
        } else {
            if result.getCode() == .FILE_NOT_FOUND {
                removeLocalFolder()
            }
        }
        
        return result
    }
    
    private func removeLocalFolder() {
        if fileDataStorageManager.fileExists(mLocalFolder.fileId) {
            let currentSavePath = FileStorageUtils.getSavePath(user.accountName)
            fileDataStorageManager.removeFolder(
                mLocalFolder,
                true,
                mLocalFolder.isDown && mLocalFolder.storagePath.starts(with: currentSavePath)
            )
        }
    }
    
    private func synchronizeData(folderAndFiles: [Any]) {
        mLocalFolder = fileDataStorageManager.getFileByPath(mLocalFolder.getRemotePath())!
        
        let remoteFolder = FileStorageUtils.fillOCFile(folderAndFiles[0] as! RemoteFile)
        remoteFolder.setParentId(mLocalFolder.getParentId())
        remoteFolder.setFileId(mLocalFolder.getFileId())
        
        Log_OC.d(RefreshFolderOperation.TAG, "Remote folder \(mLocalFolder.getRemotePath()) changed - starting update of local data ")
        
        var updatedFiles: [OCFile] = []
        mFilesToSyncContents.removeAll()
        
        let encryptedAncestor = FileStorageUtils.checkEncryptionStatus(mLocalFolder, fileDataStorageManager: fileDataStorageManager)
        mLocalFolder.setEncrypted(encryptedAncestor)
        
        mLocalFolder.setPermissions(remoteFolder.getPermissions())
        mLocalFolder.setRichWorkspace(remoteFolder.getRichWorkspace())
        mLocalFolder.setEtag(remoteFolder.getEtag())
        mLocalFolder.setFileLength(remoteFolder.getFileLength())
        
        var object: Any? = nil
        if mLocalFolder.isEncrypted() {
            object = getDecryptedFolderMetadata(encryptedAncestor: encryptedAncestor, localFolder: mLocalFolder, client: getClient(), user: user, context: mContext)
        }
        
        if CapabilityUtils.getCapability(mContext).getEndToEndEncryptionApiVersion().compareTo(E2EVersion.V2_0) >= 0 {
            if encryptedAncestor && object == nil {
                fatalError("metadata is null!")
            }
        }
        
        var localFilesMap: [String: OCFile]
        let e2EVersion: E2EVersion
        if let object = object as? DecryptedFolderMetadataFileV1 {
            e2EVersion = .V1_2
            localFilesMap = prefillLocalFilesMap(metadata: object, localFiles: fileDataStorageManager.getFolderContent(mLocalFolder, false))
        } else {
            e2EVersion = .V2_0
            localFilesMap = prefillLocalFilesMap(metadata: object as! DecryptedFolderMetadataFile, localFiles: fileDataStorageManager.getFolderContent(mLocalFolder, false))
            
            if let object = object as? DecryptedFolderMetadataFile {
                mLocalFolder.setE2eCounter(object.getMetadata().getCounter())
            }
        }
        
        for i in 1..<folderAndFiles.count {
            let remote = folderAndFiles[i] as! RemoteFile
            let remoteFile = FileStorageUtils.fillOCFile(remote)
            
            let updatedFile = FileStorageUtils.fillOCFile(remote)
            updatedFile.setParentId(mLocalFolder.getFileId())
            
            var localFile = localFilesMap.removeValue(forKey: remoteFile.getRemotePath())
            
            if localFile == nil {
                localFile = fileDataStorageManager.getFileByPath(updatedFile.getRemotePath())
            }
            
            updatedFile.setLastSyncDateForProperties(mCurrentSyncTime)
            
            if !updatedFile.isUpdateThumbnailNeeded(), let localFile = localFile, let imageDimension = localFile.getImageDimension() {
                updatedFile.setImageDimension(imageDimension)
            }
            
            setLocalFileDataOnUpdatedFile(remoteFile: remoteFile, localFile: localFile, updatedFile: updatedFile, remoteFolderChanged: mRemoteFolderChanged)
            
            FileStorageUtils.searchForLocalFileInDefaultPath(updatedFile, user.getAccountName())
            
            if e2EVersion == .V1_2 {
                updateFileNameForEncryptedFileV1(storageManager: fileDataStorageManager, metadata: object as! DecryptedFolderMetadataFileV1, updatedFile: updatedFile)
            } else {
                updateFileNameForEncryptedFile(storageManager: fileDataStorageManager, metadata: object as! DecryptedFolderMetadataFile, updatedFile: updatedFile)
                if let localFile = localFile {
                    updatedFile.setE2eCounter(localFile.getE2eCounter())
                }
            }
            
            let encrypted = updatedFile.isEncrypted() || mLocalFolder.isEncrypted()
            updatedFile.setEncrypted(encrypted)
            
            updatedFiles.append(updatedFile)
        }
        
        if e2EVersion == .V1_2 {
            updateFileNameForEncryptedFileV1(storageManager: fileDataStorageManager, metadata: object as! DecryptedFolderMetadataFileV1, updatedFile: mLocalFolder)
        } else {
            updateFileNameForEncryptedFile(storageManager: fileDataStorageManager, metadata: object as! DecryptedFolderMetadataFile, updatedFile: mLocalFolder)
        }
        fileDataStorageManager.saveFolder(remoteFolder, updatedFiles: updatedFiles, localFilesMap.values)
        
        mChildren = updatedFiles
    }
    
    func getDecryptedFolderMetadata(encryptedAncestor: Bool, localFolder: OCFile, client: OwnCloudClient, user: User, context: Context) -> Any? {
        var metadata: Any?
        if encryptedAncestor {
            metadata = EncryptionUtils.downloadFolderMetadata(localFolder: localFolder, client: client, context: context, user: user)
        } else {
            metadata = nil
        }
        return metadata
    }
    
    private static func setMimeTypeAndDecryptedRemotePath(updatedFile: OCFile, storageManager: FileDataStorageManager, decryptedFileName: String?, mimetype: String?) {
        guard let parentFile = storageManager.getFileById(updatedFile.getParentId()) else {
            fatalError("parentFile cannot be null")
        }
        
        let decryptedRemotePath: String
        if let decryptedFileName = decryptedFileName {
            decryptedRemotePath = parentFile.getDecryptedRemotePath() + decryptedFileName
        } else {
            decryptedRemotePath = parentFile.getRemotePath() + updatedFile.getFileName()
        }
        
        if updatedFile.isFolder() {
            decryptedRemotePath += "/"
        }
        updatedFile.setDecryptedRemotePath(decryptedRemotePath)
        
        if mimetype == nil || mimetype!.isEmpty {
            if updatedFile.isFolder() {
                updatedFile.setMimeType(MimeType.DIRECTORY)
            } else {
                updatedFile.setMimeType("application/octet-stream")
            }
        } else {
            updatedFile.setMimeType(mimetype!)
        }
    }
    
    static func updateFileNameForEncryptedFileV1(storageManager: FileDataStorageManager, metadata: DecryptedFolderMetadataFileV1, updatedFile: OCFile) {
        do {
            var decryptedFileName: String
            var mimetype: String
            
            if updatedFile.isFolder() {
                decryptedFileName = metadata.files[updatedFile.fileName]?.encrypted.filename ?? ""
                mimetype = MimeType.directory
            } else {
                guard let decryptedFile = metadata.files[updatedFile.fileName] else {
                    throw NSError(domain: "DecryptedFileError", code: 0, userInfo: [NSLocalizedDescriptionKey: "decryptedFile cannot be null"])
                }
                
                decryptedFileName = decryptedFile.encrypted.filename
                mimetype = decryptedFile.encrypted.mimetype
            }
            
            setMimeTypeAndDecryptedRemotePath(updatedFile: updatedFile, storageManager: storageManager, decryptedFileName: decryptedFileName, mimetype: mimetype)
        } catch {
            Log_OC.e(RefreshFolderOperation.TAG, "DecryptedMetadata for file \(updatedFile.fileId) not found!")
        }
    }
    
    static func updateFileNameForEncryptedFile(storageManager: FileDataStorageManager, metadata: DecryptedFolderMetadataFile, updatedFile: OCFile) {
        do {
            var decryptedFileName: String
            var mimetype: String
            
            if updatedFile.isFolder() {
                decryptedFileName = metadata.metadata.folders[updatedFile.fileName] ?? ""
                mimetype = MimeType.directory
            } else {
                guard let decryptedFile = metadata.metadata.files[updatedFile.fileName] else {
                    throw NSError(domain: "DecryptedFileError", code: 0, userInfo: [NSLocalizedDescriptionKey: "decryptedFile cannot be null"])
                }
                
                decryptedFileName = decryptedFile.filename
                mimetype = decryptedFile.mimetype
            }
            
            setMimeTypeAndDecryptedRemotePath(updatedFile: updatedFile, storageManager: storageManager, decryptedFileName: decryptedFileName, mimetype: mimetype)
        } catch {
            Log_OC.e(RefreshFolderOperation.TAG, "DecryptedMetadata for file \(updatedFile.fileId) not found!")
        }
    }
    
    private func setLocalFileDataOnUpdatedFile(remoteFile: OCFile, localFile: OCFile?, updatedFile: OCFile, remoteFolderChanged: Bool) {
        if let localFile = localFile {
            updatedFile.setFileId(localFile.getFileId())
            updatedFile.setLastSyncDateForData(localFile.getLastSyncDateForData())
            updatedFile.setInternalFolderSyncTimestamp(localFile.getInternalFolderSyncTimestamp())
            updatedFile.setModificationTimestampAtLastSyncForData(localFile.getModificationTimestampAtLastSyncForData())
            
            if localFile.isEncrypted() {
                if mLocalFolder.getStoragePath() == nil {
                    updatedFile.setStoragePath(FileStorageUtils.getDefaultSavePathFor(user.getAccountName(), mLocalFolder) + localFile.getFileName())
                } else {
                    updatedFile.setStoragePath(mLocalFolder.getStoragePath()! + PATH_SEPARATOR + localFile.getFileName())
                }
            } else {
                updatedFile.setStoragePath(localFile.getStoragePath())
            }
            
            if !updatedFile.isFolder() && localFile.isDown() && updatedFile.getEtag() != localFile.getEtag() {
                updatedFile.setEtagInConflict(updatedFile.getEtag())
            }
            
            updatedFile.setEtag(localFile.getEtag())
            
            if updatedFile.isFolder() {
                updatedFile.setFileLength(remoteFile.getFileLength())
                updatedFile.setMountType(remoteFile.getMountType())
            } else if remoteFolderChanged && MimeTypeUtil.isImage(remoteFile) && remoteFile.getModificationTimestamp() != localFile.getModificationTimestamp() {
                updatedFile.setUpdateThumbnailNeeded(true)
                Log_OC.d(RefreshFolderOperation.TAG, "Image \(remoteFile.getFileName()) updated on the server")
            }
            
            updatedFile.setSharedViaLink(localFile.isSharedViaLink())
            updatedFile.setSharedWithSharee(localFile.isSharedWithSharee())
        } else {
            updatedFile.setEtag("")
        }
        
        updatedFile.setEtagOnServer(remoteFile.getEtag())
    }
    
    func prefillLocalFilesMap(metadata: Any?, localFiles: [OCFile]) -> [String: OCFile] {
        var localFilesMap = [String: OCFile](minimumCapacity: localFiles.count)
        
        for file in localFiles {
            var remotePath = file.getRemotePath()
            
            if metadata != nil {
                remotePath = file.getParentRemotePath() + file.getEncryptedFileName()
                if file.isFolder() && !remotePath.hasSuffix(PATH_SEPARATOR) {
                    remotePath += PATH_SEPARATOR
                }
            }
            localFilesMap[remotePath] = file
        }
        return localFilesMap
    }
    
    private func startContentSynchronizations(filesToSyncContents: [SynchronizeFileOperation]) {
        for op in filesToSyncContents {
            let contentsResult = op.execute(mContext)
            if !contentsResult.isSuccess() {
                if contentsResult.code == .syncConflict {
                    mConflictsFound += 1
                } else {
                    mFailsInKeptInSyncFound += 1
                    if let exception = contentsResult.exception {
                        Log_OC.e(RefreshFolderOperation.TAG, "Error while synchronizing favourites : \(contentsResult.logMessage)", exception)
                    } else {
                        Log_OC.e(RefreshFolderOperation.TAG, "Error while synchronizing favourites : \(contentsResult.logMessage)")
                    }
                }
            }
        }
    }
    
    private func refreshSharesForFolder(client: OwnCloudClient) -> RemoteOperationResult {
        var result: RemoteOperationResult
        
        let operation = GetSharesForFileRemoteOperation(remotePath: mLocalFolder.remotePath, includeReshares: true, includeSubfiles: true)
        result = operation.execute(client: client)
        
        if result.isSuccess {
            var shares: [OCShare] = []
            for obj in result.getData() {
                if let share = obj as? OCShare, share.shareType != .noShared {
                    shares.append(share)
                }
            }
            fileDataStorageManager.saveSharesInFolder(shares: shares, folder: mLocalFolder)
        }
        
        return result
    }
    
    private func sendLocalBroadcast(event: String, dirRemotePath: String?, result: RemoteOperationResult) {
        Log_OC.d(RefreshFolderOperation.TAG, "Send broadcast \(event)")
        let intent = Intent(event)
        intent.putExtra(FileSyncAdapter.EXTRA_ACCOUNT_NAME, user.getAccountName())
        
        if let dirRemotePath = dirRemotePath {
            intent.putExtra(FileSyncAdapter.EXTRA_FOLDER_PATH, dirRemotePath)
        }
        
        let dataHolderUtil = DataHolderUtil.getInstance()
        let dataHolderItemId = dataHolderUtil.nextItemId()
        dataHolderUtil.save(dataHolderItemId, result)
        intent.putExtra(FileSyncAdapter.EXTRA_RESULT, dataHolderItemId)
        
        intent.setPackage(mContext.getPackageName())
        LocalBroadcastManager.getInstance(mContext.getApplicationContext()).sendBroadcast(intent)
    }
}
