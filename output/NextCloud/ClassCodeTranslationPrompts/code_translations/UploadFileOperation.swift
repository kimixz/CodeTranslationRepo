
import Foundation

class UploadFileOperation: SyncOperation {
    private static let TAG = String(describing: UploadFileOperation.self)

    public static let CREATED_BY_USER = 0
    public static let CREATED_AS_INSTANT_PICTURE = 1
    public static let CREATED_AS_INSTANT_VIDEO = 2

    private var mFile: OCFile
    private var mOldFile: OCFile?
    private var mRemotePath: String
    private var mFolderUnlockToken: String?
    private var mRemoteFolderToBeCreated: Bool
    private var mNameCollisionPolicy: NameCollisionPolicy
    private var mLocalBehaviour: Int
    private var mCreatedBy: Int
    private var mOnWifiOnly: Bool
    private var mWhileChargingOnly: Bool
    private var mIgnoringPowerSaveMode: Bool
    private let mDisableRetries: Bool

    private var mWasRenamed: Bool = false
    private var mOCUploadId: Int64
    private var mOriginalStoragePath: String
    private var mDataTransferListeners = Set<OnDatatransferProgressListener>()
    private var mRenameUploadListener: OnRenameListener?

    private var mCancellationRequested = AtomicBoolean(false)
    private var mUploadStarted = AtomicBoolean(false)

    private var mContext: Context

    private var mUploadOperation: UploadFileRemoteOperation?

    private var mEntity: RequestEntity?

    private let user: User
    private let mUpload: OCUpload
    private let uploadsStorageManager: UploadsStorageManager
    private let connectivityService: ConnectivityService
    private let powerManagementService: PowerManagementService

    private var encryptedAncestor: Bool = false
    private var duplicatedEncryptedFile: OCFile?

    public static func obtainNewOCFileToUpload(remotePath: String, localPath: String, mimeType: String?) -> OCFile {
        let newFile = OCFile(remotePath: remotePath)
        newFile.setStoragePath(localPath)
        newFile.setLastSyncDateForProperties(0)
        newFile.setLastSyncDateForData(0)

        if !localPath.isEmpty {
            let localFile = FileManager.default.attributesOfItem(atPath: localPath)
            if let fileSize = localFile[.size] as? Int64 {
                newFile.setFileLength(fileSize)
            }
            if let lastModified = localFile[.modificationDate] as? Date {
                newFile.setLastSyncDateForData(Int(lastModified.timeIntervalSince1970))
            }
        }

        if mimeType?.isEmpty ?? true {
            newFile.setMimeType(MimeTypeUtil.getBestMimeTypeByFilename(localPath))
        } else {
            newFile.setMimeType(mimeType!)
        }

        return newFile
    }

    init(uploadsStorageManager: UploadsStorageManager,
         connectivityService: ConnectivityService,
         powerManagementService: PowerManagementService,
         user: User,
         file: OCFile?,
         upload: OCUpload,
         nameCollisionPolicy: NameCollisionPolicy,
         localBehaviour: Int,
         context: Context,
         onWifiOnly: Bool,
         whileChargingOnly: Bool,
         disableRetries: Bool,
         storageManager: FileDataStorageManager) {
        super.init(storageManager: storageManager)

        if upload.getLocalPath().isEmpty {
            fatalError("Illegal file in UploadFileOperation; storage path invalid: \(upload.getLocalPath())")
        }

        self.uploadsStorageManager = uploadsStorageManager
        self.connectivityService = connectivityService
        self.powerManagementService = powerManagementService
        self.user = user
        self.mUpload = upload
        if let file = file {
            self.mFile = file
        } else {
            self.mFile = UploadFileOperation.obtainNewOCFileToUpload(remotePath: upload.getRemotePath(),
                                                                     localPath: upload.getLocalPath(),
                                                                     mimeType: upload.getMimeType())
        }
        self.mOnWifiOnly = onWifiOnly
        self.mWhileChargingOnly = whileChargingOnly
        self.mRemotePath = upload.getRemotePath()
        self.mNameCollisionPolicy = nameCollisionPolicy
        self.mLocalBehaviour = localBehaviour
        self.mOriginalStoragePath = mFile.getStoragePath()
        self.mContext = context
        self.mOCUploadId = upload.getUploadId()
        self.mCreatedBy = upload.getCreatedBy()
        self.mRemoteFolderToBeCreated = upload.isCreateRemoteFolder()
        self.mIgnoringPowerSaveMode = mCreatedBy == UploadFileOperation.CREATED_BY_USER
        self.mFolderUnlockToken = upload.getFolderUnlockToken()
        self.mDisableRetries = disableRetries
    }

    func isWifiRequired() -> Bool {
        return mOnWifiOnly
    }

    func isChargingRequired() -> Bool {
        return mWhileChargingOnly
    }

    func isIgnoringPowerSaveMode() -> Bool {
        return mIgnoringPowerSaveMode
    }

    func getUser() -> User {
        return user
    }

    func getFileName() -> String? {
        return mFile.getFileName()
    }

    func getFile() -> OCFile {
        return mFile
    }

    func getOldFile() -> OCFile? {
        return mOldFile
    }

    func getOriginalStoragePath() -> String {
        return mOriginalStoragePath
    }

    func getStoragePath() -> String {
        return mFile.getStoragePath()
    }

    func getRemotePath() -> String {
        return mFile.getRemotePath()
    }

    func getDecryptedRemotePath() -> String {
        return mFile.getDecryptedRemotePath()
    }

    func getMimeType() -> String {
        return mFile.getMimeType()
    }

    func getLocalBehaviour() -> Int {
        return mLocalBehaviour
    }

    func setRemoteFolderToBeCreated() -> UploadFileOperation {
        mRemoteFolderToBeCreated = true
        return self
    }

    func wasRenamed() -> Bool {
        return mWasRenamed
    }

    func setCreatedBy(_ createdBy: Int) {
        mCreatedBy = createdBy
        if createdBy < UploadFileOperation.CREATED_BY_USER || UploadFileOperation.CREATED_AS_INSTANT_VIDEO < createdBy {
            mCreatedBy = UploadFileOperation.CREATED_BY_USER
        }
    }

    func getCreatedBy() -> Int {
        return mCreatedBy
    }

    func isInstantPicture() -> Bool {
        return mCreatedBy == UploadFileOperation.CREATED_AS_INSTANT_PICTURE
    }

    func isInstantVideo() -> Bool {
        return mCreatedBy == UploadFileOperation.CREATED_AS_INSTANT_VIDEO
    }

    func setOCUploadId(_ id: Int64) {
        mOCUploadId = id
    }

    func getOCUploadId() -> Int64 {
        return mOCUploadId
    }

    func getDataTransferListeners() -> Set<OnDatatransferProgressListener> {
        return mDataTransferListeners
    }

    func addDataTransferProgressListener(listener: OnDatatransferProgressListener) {
        objc_sync_enter(mDataTransferListeners)
        mDataTransferListeners.insert(listener)
        objc_sync_exit(mDataTransferListeners)
        
        if let entity = mEntity as? ProgressiveDataTransfer {
            entity.addDataTransferProgressListener(listener: listener)
        }
        
        mUploadOperation?.addDataTransferProgressListener(listener: listener)
    }

    func removeDataTransferProgressListener(listener: OnDatatransferProgressListener) {
        objc_sync_enter(mDataTransferListeners)
        defer { objc_sync_exit(mDataTransferListeners) }
        mDataTransferListeners.remove(listener)
        
        if let entity = mEntity as? ProgressiveDataTransfer {
            entity.removeDataTransferProgressListener(listener)
        }
        
        mUploadOperation?.removeDataTransferProgressListener(listener)
    }

    func addRenameUploadListener(listener: OnRenameListener) -> UploadFileOperation {
        mRenameUploadListener = listener
        return self
    }

    func getContext() -> Context {
        return mContext
    }

    override func run(client: OwnCloudClient) -> RemoteOperationResult {
        mCancellationRequested.set(false)
        mUploadStarted.set(true)

        updateSize(0)

        var remoteParentPath = (getRemotePath() as NSString).deletingLastPathComponent
        remoteParentPath = remoteParentPath.hasSuffix(OCFile.PATH_SEPARATOR) ? remoteParentPath : remoteParentPath + OCFile.PATH_SEPARATOR
        remoteParentPath = AutoRename.INSTANCE.rename(remoteParentPath, getCapabilities(), true)

        var parent = getStorageManager().getFileByPath(remoteParentPath)

        if parent == nil && (mFolderUnlockToken == nil || mFolderUnlockToken!.isEmpty) {
            let result = grantFolderExistence(remoteParentPath, client)

            if !result.isSuccess {
                return result
            }

            parent = getStorageManager().getFileByPath(remoteParentPath)

            if parent == nil {
                return RemoteOperationResult(success: false, message: "Parent folder not found", httpStatus: HttpStatus.SC_NOT_FOUND)
            }
        }

        mFile.setParentId(parent!.getFileId())

        encryptedAncestor = FileStorageUtils.checkEncryptionStatus(parent!, getStorageManager())
        mFile.setEncrypted(encryptedAncestor)

        if encryptedAncestor {
            Log_OC.d(UploadFileOperation.TAG, "encrypted upload")
            return encryptedUpload(client, parent!)
        } else {
            Log_OC.d(UploadFileOperation.TAG, "normal upload")
            return normalUpload(client)
        }
    }

    private func encryptedUpload(client: OwnCloudClient, parentFile: OCFile) -> RemoteOperationResult {
        var result: RemoteOperationResult? = nil
        let e2eFiles = E2EFiles(parentFile: parentFile, nil, File(mOriginalStoragePath), nil, nil)
        var fileLock: FileLock? = nil
        var size: Int64 = 0

        var metadataExists = false
        var token: String? = nil
        var object: Any? = nil

        let arbitraryDataProvider = ArbitraryDataProviderImpl(context: getContext())
        let publicKey = arbitraryDataProvider.getValue(user.accountName, EncryptionUtils.PUBLIC_KEY)

        do {
            result = checkConditions(e2eFiles.originalFile)

            if result != nil {
                return result!
            }

            let counter = getE2ECounter(parentFile: parentFile)
            token = getFolderUnlockTokenOrLockFolder(client: client, parentFile: parentFile, counter: counter)

            let encryptionUtilsV2 = EncryptionUtilsV2()
            object = EncryptionUtils.downloadFolderMetadata(parentFile: parentFile, client: client, context: mContext, user: user)
            if let decrypted = object as? DecryptedFolderMetadataFileV1, decrypted.metadata != nil {
                metadataExists = true
            }

            if isEndToEndVersionAtLeastV2() {
                if object == nil {
                    return RemoteOperationResult(error: IllegalStateException("Metadata does not exist"))
                }
            } else {
                object = getDecryptedFolderMetadataV1(publicKey: publicKey, object: object)
            }

            let clientData = E2EClientData(client: client, token: token, publicKey: publicKey)

            let fileNames = getCollidedFileNames(object: object)

            if let collisionResult = checkNameCollision(parentFile: parentFile, client: client, fileNames: fileNames, encrypted: parentFile.isEncrypted()) {
                result = collisionResult
                return collisionResult
            }

            mFile.setDecryptedRemotePath(parentFile.getDecryptedRemotePath() + e2eFiles.originalFile.getName())
            let expectedPath = FileStorageUtils.getDefaultSavePathFor(user.accountName, mFile)
            e2eFiles.setExpectedFile(File(expectedPath))

            result = copyFile(originalFile: e2eFiles.originalFile, expectedPath: expectedPath)
            if !result!.isSuccess {
                return result!
            }

            let lastModifiedTimestamp = e2eFiles.originalFile.lastModified() / 1000
            guard let creationTimestamp = FileUtil.getCreationTimestamp(e2eFiles.originalFile) else {
                throw NullPointerException("creationTimestamp cannot be null")
            }

            let e2eData = getE2EData(object: object)
            e2eFiles.setEncryptedTempFile(e2eData.getEncryptedFile().getEncryptedFile())
            if e2eFiles.getEncryptedTempFile() == nil {
                throw NullPointerException("encryptedTempFile cannot be null")
            }

            let channelResult = initFileChannel(result: &result, fileLock: &fileLock, e2eFiles: e2eFiles)
            fileLock = channelResult.0
            result = channelResult.1
            let channel = channelResult.2

            size = getChannelSize(channel: channel)
            updateSize(size: size)
            setUploadOperationForE2E(token: token, encryptedTempFile: e2eFiles.getEncryptedTempFile(), encryptedFileName: e2eData.getEncryptedFileName(), lastModifiedTimestamp: lastModifiedTimestamp, creationTimestamp: creationTimestamp, size: size)

            result = performE2EUpload(data: clientData)

            if result!.isSuccess {
                updateMetadataForE2E(object: object, e2eData: e2eData, clientData: clientData, e2eFiles: e2eFiles, arbitraryDataProvider: arbitraryDataProvider, encryptionUtilsV2: encryptionUtilsV2, metadataExists: metadataExists)
            }
        } catch let e as FileNotFoundException {
            Log_OC.d(UploadFileOperation.TAG, "\(mFile.getStoragePath()) does not exist anymore")
            result = RemoteOperationResult(resultCode: .LOCAL_FILE_NOT_FOUND)
        } catch let e as OverlappingFileLockException {
            Log_OC.d(UploadFileOperation.TAG, "Overlapping file lock exception")
            result = RemoteOperationResult(resultCode: .LOCK_FAILED)
        } catch {
            result = RemoteOperationResult(error: error)
        } finally {
            result = cleanupE2EUpload(fileLock: fileLock, e2eFiles: e2eFiles, result: result, object: object, client: client, token: token)
        }

        completeE2EUpload(result: result, e2eFiles: e2eFiles, client: client)

        return result!
    }

    private func isEndToEndVersionAtLeastV2() -> Bool {
        return getE2EVersion().compareTo(E2EVersion.V2_0) >= 0
    }

    private func getE2EVersion() -> E2EVersion {
        return CapabilityUtils.getCapability(mContext).getEndToEndEncryptionApiVersion()
    }

    private func getE2ECounter(parentFile: OCFile) -> Int64 {
        var counter: Int64 = -1

        if isEndToEndVersionAtLeastV2() {
            counter = parentFile.getE2eCounter() + 1
        }

        return counter
    }

    private func getFolderUnlockTokenOrLockFolder(client: OwnCloudClient, parentFile: OCFile, counter: Int64) throws -> String {
        if let folderUnlockToken = mFolderUnlockToken, !folderUnlockToken.isEmpty {
            return folderUnlockToken
        }

        let token = try EncryptionUtils.lockFolder(parentFile: parentFile, client: client, counter: counter)
        mUpload.setFolderUnlockToken(token)
        uploadsStorageManager.updateUpload(mUpload)

        return token
    }

    private func getDecryptedFolderMetadataV1(publicKey: String, object: Any) throws -> DecryptedFolderMetadataFileV1 {
        var metadata = DecryptedFolderMetadataFileV1()
        metadata.setMetadata(DecryptedMetadata())
        metadata.getMetadata().setVersion(1.2)
        metadata.getMetadata().setMetadataKeys([:])
        let metadataKey = EncryptionUtils.encodeBytesToBase64String(EncryptionUtils.generateKey())
        let encryptedMetadataKey = try EncryptionUtils.encryptStringAsymmetric(metadataKey, publicKey: publicKey)
        metadata.getMetadata().setMetadataKey(encryptedMetadataKey)

        if let decryptedMetadata = object as? DecryptedFolderMetadataFileV1 {
            metadata = decryptedMetadata
        }

        return metadata
    }

    private func getCollidedFileNames(object: Any) -> [String] {
        var result: [String] = []

        if let metadata = object as? DecryptedFolderMetadataFileV1 {
            for file in metadata.getFiles().values {
                result.append(file.getEncrypted().getFilename())
            }
        } else if let metadataFile = object as? DecryptedFolderMetadataFile {
            let files = metadataFile.getMetadata().getFiles()
            for file in files.values {
                result.append(file.getFilename())
            }
        }

        return result
    }

    private func getEncryptedFileName(object: Any) -> String {
        var encryptedFileName = EncryptionUtils.generateUid()

        if let metadata = object as? DecryptedFolderMetadataFileV1 {
            while metadata.getFiles()[encryptedFileName] != nil {
                encryptedFileName = EncryptionUtils.generateUid()
            }
        } else if let metadata = object as? DecryptedFolderMetadataFile {
            while metadata.getMetadata().getFiles()[encryptedFileName] != nil {
                encryptedFileName = EncryptionUtils.generateUid()
            }
        }

        return encryptedFileName
    }

    private func setUploadOperationForE2E(token: String, encryptedTempFile: File, encryptedFileName: String, lastModifiedTimestamp: Int64, creationTimestamp: Int64, size: Int64) {
        if size > ChunkedFileUploadRemoteOperation.CHUNK_SIZE_MOBILE {
            let onWifiConnection = connectivityService.getConnectivity().isWifi()
            
            mUploadOperation = ChunkedFileUploadRemoteOperation(
                encryptedTempFile.getAbsolutePath(),
                mFile.getParentRemotePath() + encryptedFileName,
                mFile.getMimeType(),
                mFile.getEtagInConflict(),
                lastModifiedTimestamp,
                onWifiConnection,
                token,
                creationTimestamp,
                mDisableRetries
            )
        } else {
            mUploadOperation = UploadFileRemoteOperation(
                encryptedTempFile.getAbsolutePath(),
                mFile.getParentRemotePath() + encryptedFileName,
                mFile.getMimeType(),
                mFile.getEtagInConflict(),
                lastModifiedTimestamp,
                creationTimestamp,
                token,
                mDisableRetries
            )
        }
    }

    private func initFileChannel(result: inout RemoteOperationResult?, fileLock: inout FileLock?, e2eFiles: E2EFiles) throws -> (FileLock?, RemoteOperationResult?, FileChannel?) {
        var channel: FileChannel? = nil

        do {
            let randomAccessFile = try RandomAccessFile(path: mFile.getStoragePath(), mode: "rw")
            defer { randomAccessFile.close() }
            channel = randomAccessFile.getChannel()
            fileLock = try channel?.tryLock()
        } catch {
            Log_OC.d(UploadFileOperation.TAG, "Error caught at getChannelFromFile: \(error)")

            let temporalPath = FileStorageUtils.getInternalTemporalPath(user.getAccountName(), mContext) + mFile.getRemotePath()
            mFile.setStoragePath(temporalPath)
            e2eFiles.setTemporalFile(File(temporalPath))

            guard e2eFiles.getTemporalFile() != nil else {
                throw NSError(domain: "Original file cannot be null", code: 0, userInfo: nil)
            }

            try? Files.deleteIfExists(path: Paths.get(temporalPath))
            result = copy(sourceFile: e2eFiles.getOriginalFile(), targetFile: e2eFiles.getTemporalFile())

            if result!.isSuccess {
                if e2eFiles.getTemporalFile()!.length() == e2eFiles.getOriginalFile()!.length() {
                    do {
                        let randomAccessFile = try RandomAccessFile(path: e2eFiles.getTemporalFile()!.getAbsolutePath(), mode: "rw")
                        defer { randomAccessFile.close() }
                        channel = randomAccessFile.getChannel()
                        fileLock = try channel?.tryLock()
                    } catch {
                        Log_OC.d(UploadFileOperation.TAG, "Error caught at getChannelFromFile: \(error)")
                    }
                } else {
                    result = RemoteOperationResult(resultCode: .LOCK_FAILED)
                }
            }
        }

        return (fileLock, result, channel)
    }

    private func getChannelSize(channel: FileChannel?) -> Int64 {
        do {
            return try channel?.size() ?? File(mFile.getStoragePath()).length()
        } catch {
            return FileManager.default.attributesOfItem(atPath: mFile.getStoragePath())[.size] as? Int64 ?? 0
        }
    }

    private func performE2EUpload(data: E2EClientData) throws -> RemoteOperationResult {
        for mDataTransferListener in mDataTransferListeners {
            mUploadOperation?.addDataTransferProgressListener(listener: mDataTransferListener)
        }

        if mCancellationRequested.get() {
            throw OperationCancelledException()
        }

        var result = mUploadOperation?.execute(client: data.getClient())

        if !result!.isSuccess && result!.getHttpCode() == HttpStatus.SC_PRECONDITION_FAILED {
            result = RemoteOperationResult(resultCode: .SYNC_CONFLICT)
        }

        return result!
    }

    private func getE2EData(object: Any) throws -> E2EData {
        let key = try EncryptionUtils.generateKey()
        let iv = EncryptionUtils.randomBytes(length: EncryptionUtils.ivLength)
        let cipher = try EncryptionUtils.getCipher(mode: .encrypt, key: key, iv: iv)
        let file = FileManager.default.fileExists(atPath: mFile.getStoragePath()) ? URL(fileURLWithPath: mFile.getStoragePath()) : nil
        guard let fileURL = file else {
            throw NSError(domain: "File not found", code: 0, userInfo: nil)
        }
        let encryptedFile = try EncryptionUtils.encryptFile(accountName: user.getAccountName(), file: fileURL, cipher: cipher)
        let encryptedFileName = getEncryptedFileName(object: object)

        if key.isEmpty {
            throw NSError(domain: "Key cannot be null", code: 0, userInfo: nil)
        }

        return E2EData(key: key, iv: iv, encryptedFile: encryptedFile, encryptedFileName: encryptedFileName)
    }

    private func updateMetadataForE2E(object: Any, e2eData: E2EData, clientData: E2EClientData, e2eFiles: E2EFiles, arbitraryDataProvider: ArbitraryDataProvider, encryptionUtilsV2: EncryptionUtilsV2, metadataExists: Bool) throws {
        mFile.setDecryptedRemotePath(e2eFiles.getParentFile().getDecryptedRemotePath() + e2eFiles.getOriginalFile().getName())
        mFile.setRemotePath(e2eFiles.getParentFile().getRemotePath() + e2eData.getEncryptedFileName())

        if let metadata = object as? DecryptedFolderMetadataFileV1 {
            updateMetadataForV1(metadata: metadata,
                                e2eData: e2eData,
                                clientData: clientData,
                                parentFile: e2eFiles.getParentFile(),
                                arbitraryDataProvider: arbitraryDataProvider,
                                metadataExists: metadataExists)
        } else if let metadata = object as? DecryptedFolderMetadataFile {
            updateMetadataForV2(metadata: metadata,
                                encryptionUtilsV2: encryptionUtilsV2,
                                e2eData: e2eData,
                                clientData: clientData,
                                parentFile: e2eFiles.getParentFile())
        }
    }

    private func updateMetadataForV1(metadata: DecryptedFolderMetadataFileV1, e2eData: E2EData, clientData: E2EClientData, parentFile: OCFile, arbitraryDataProvider: ArbitraryDataProvider, metadataExists: Bool) throws {
        let decryptedFile = DecryptedFile()
        let data = Data()
        data.setFilename(mFile.getDecryptedFileName())
        data.setMimetype(mFile.getMimeType())
        data.setKey(EncryptionUtils.encodeBytesToBase64String(e2eData.getKey()))
        decryptedFile.setEncrypted(data)
        decryptedFile.setInitializationVector(EncryptionUtils.encodeBytesToBase64String(e2eData.getIv()))
        decryptedFile.setAuthenticationTag(e2eData.getEncryptedFile().getAuthenticationTag())

        metadata.getFiles().put(e2eData.getEncryptedFileName(), decryptedFile)

        let encryptedFolderMetadata = try EncryptionUtils.encryptFolderMetadata(metadata: metadata, publicKey: clientData.getPublicKey(), localId: parentFile.getLocalId(), user: user, arbitraryDataProvider: arbitraryDataProvider)

        let serializedFolderMetadata: String
        if metadata.getMetadata().getMetadataKey() != nil {
            serializedFolderMetadata = try EncryptionUtils.serializeJSON(encryptedFolderMetadata, prettyPrint: true)
        } else {
            serializedFolderMetadata = try EncryptionUtils.serializeJSON(encryptedFolderMetadata)
        }

        try EncryptionUtils.uploadMetadata(parentFile: parentFile, serializedFolderMetadata: serializedFolderMetadata, token: clientData.getToken(), client: clientData.getClient(), metadataExists: metadataExists, version: .V1_2, path: "", arbitraryDataProvider: arbitraryDataProvider, user: user)
    }

    private func updateMetadataForV2(metadata: DecryptedFolderMetadataFile, encryptionUtilsV2: EncryptionUtilsV2, e2eData: E2EData, clientData: E2EClientData, parentFile: OCFile) throws {
        try encryptionUtilsV2.addFileToMetadata(
            encryptedFileName: e2eData.getEncryptedFileName(),
            file: mFile,
            iv: e2eData.getIv(),
            authenticationTag: e2eData.getEncryptedFile().getAuthenticationTag(),
            key: e2eData.getKey(),
            metadata: metadata,
            storageManager: getStorageManager()
        )

        try encryptionUtilsV2.serializeAndUploadMetadata(
            parentFile: parentFile,
            metadata: metadata,
            token: clientData.getToken(),
            client: clientData.getClient(),
            flag: true,
            context: mContext,
            user: user,
            storageManager: getStorageManager()
        )
    }

    private func completeE2EUpload(result: RemoteOperationResult, e2eFiles: E2EFiles, client: OwnCloudClient) {
        if result.isSuccess() {
            handleSuccessfulUpload(temporalFile: e2eFiles.getTemporalFile(), expectedFile: e2eFiles.getExpectedFile(), originalFile: e2eFiles.getOriginalFile(), client: client)
        } else if result.getCode() == .SYNC_CONFLICT {
            getStorageManager().saveConflict(mFile, mFile.getEtagInConflict())
        }
        
        e2eFiles.deleteTemporalFile()
    }

    private func deleteDuplicatedFileAndSendRefreshFolderEvent(client: OwnCloudClient) {
        FileUploadHelper.Companion.instance().removeDuplicatedFile(duplicatedEncryptedFile, client: client, user: user) {
            duplicatedEncryptedFile = nil
            sendRefreshFolderEventBroadcast()
            return nil
        }
    }

    private func cleanupE2EUpload(fileLock: FileLock?, e2eFiles: E2EFiles, result: RemoteOperationResult?, object: Any, client: OwnCloudClient, token: String) -> RemoteOperationResult {
        mUploadStarted.set(false)

        if let fileLock = fileLock {
            do {
                try fileLock.release()
            } catch {
                Log_OC.e(UploadFileOperation.TAG, "Failed to unlock file with path \(mFile.getStoragePath())")
            }
        }

        e2eFiles.deleteTemporalFileWithOriginalFileComparison()

        var result = result ?? RemoteOperationResult(resultCode: .unknownError)

        logResult(result: result, sourcePath: mFile.getStoragePath(), targetPath: mFile.getRemotePath())

        var unlockFolderResult: RemoteOperationResult<Void>
        if object is DecryptedFolderMetadataFileV1 {
            unlockFolderResult = EncryptionUtils.unlockFolderV1(e2eFiles.getParentFile(), client: client, token: token)
        } else {
            unlockFolderResult = EncryptionUtils.unlockFolder(e2eFiles.getParentFile(), client: client, token: token)
        }

        if !unlockFolderResult.isSuccess() {
            result = unlockFolderResult
        }

        if unlockFolderResult.isSuccess() {
            Log_OC.d(UploadFileOperation.TAG, "Folder successfully unlocked: \(e2eFiles.getParentFile().getFileName())")

            if duplicatedEncryptedFile != nil {
                deleteDuplicatedFileAndSendRefreshFolderEvent(client: client)
            } else {
                sendRefreshFolderEventBroadcast()
            }
        }

        e2eFiles.deleteEncryptedTempFile()

        return result
    }

    private func sendRefreshFolderEventBroadcast() {
        let intent = Notification(name: Notification.Name(rawValue: REFRESH_FOLDER_EVENT_RECEIVER))
        NotificationCenter.default.post(intent)
    }

    private func checkConditions(originalFile: File) -> RemoteOperationResult? {
        var remoteOperationResult: RemoteOperationResult? = nil

        let connectivity = connectivityService.getConnectivity()
        if mOnWifiOnly && (!connectivity.isWifi || connectivity.isMetered) {
            Log_OC.d(UploadFileOperation.TAG, "Upload delayed until WiFi is available: \(getRemotePath())")
            remoteOperationResult = RemoteOperationResult(resultCode: .delayedForWifi)
        }

        let battery = powerManagementService.getBattery()
        if mWhileChargingOnly && !battery.isCharging {
            Log_OC.d(UploadFileOperation.TAG, "Upload delayed until the device is charging: \(getRemotePath())")
            remoteOperationResult = RemoteOperationResult(resultCode: .delayedForCharging)
        }

        if !mIgnoringPowerSaveMode && powerManagementService.isPowerSavingEnabled() {
            Log_OC.d(UploadFileOperation.TAG, "Upload delayed because device is in power save mode: \(getRemotePath())")
            remoteOperationResult = RemoteOperationResult(resultCode: .delayedInPowerSaveMode)
        }

        if !originalFile.exists() {
            Log_OC.d(UploadFileOperation.TAG, "\(mOriginalStoragePath) does not exist anymore")
            remoteOperationResult = RemoteOperationResult(resultCode: .localFileNotFound)
        }

        if !connectivityService.getConnectivity().isConnected || connectivityService.isInternetWalled() {
            remoteOperationResult = RemoteOperationResult(resultCode: .noNetworkConnection)
        }

        return remoteOperationResult
    }

    private func normalUpload(client: OwnCloudClient) -> RemoteOperationResult {
        var result: RemoteOperationResult? = nil
        var temporalFile: File? = nil
        let originalFile = File(mOriginalStoragePath)
        var expectedFile: File? = nil
        var fileLock: FileLock? = nil
        var channel: FileChannel? = nil

        var size: Int64

        do {
            result = checkConditions(originalFile)

            if result != nil {
                return result!
            }

            let collisionResult = checkNameCollision(parentFile: nil, client: client, fileNames: [], encrypted: false)
            if collisionResult != nil {
                result = collisionResult
                return collisionResult!
            }

            let expectedPath = FileStorageUtils.getDefaultSavePathFor(user.accountName, mFile)
            expectedFile = File(expectedPath)

            result = copyFile(originalFile: originalFile, expectedPath: expectedPath)
            if !result!.isSuccess {
                return result!
            }

            let lastModifiedTimestamp = originalFile.lastModified() / 1000

            let creationTimestamp = FileUtil.getCreationTimestamp(originalFile)

            do {
                channel = try RandomAccessFile(mFile.getStoragePath(), "rw").getChannel()
                fileLock = try channel?.tryLock()
            } catch is FileNotFoundException {
                let temporalPath = FileStorageUtils.getInternalTemporalPath(user.accountName, mContext) +
                    mFile.getRemotePath()
                mFile.setStoragePath(temporalPath)
                temporalFile = File(temporalPath)

                try? Files.deleteIfExists(Paths.get(temporalPath))
                result = copy(sourceFile: originalFile, targetFile: temporalFile!)

                if result!.isSuccess {
                    if temporalFile!.length() == originalFile.length() {
                        channel = try RandomAccessFile(temporalFile!.getAbsolutePath(), "rw").getChannel()
                        fileLock = try channel?.tryLock()
                    } else {
                        result = RemoteOperationResult(ResultCode.LOCK_FAILED)
                    }
                }
            }

            do {
                size = try channel?.size() ?? File(mFile.getStoragePath()).length()
            } catch {
                size = File(mFile.getStoragePath()).length()
            }

            updateSize(size: size)

            if size > ChunkedFileUploadRemoteOperation.CHUNK_SIZE_MOBILE {
                let onWifiConnection = connectivityService.getConnectivity().isWifi()

                mUploadOperation = ChunkedFileUploadRemoteOperation(mFile.getStoragePath(),
                                                                    mFile.getRemotePath(),
                                                                    mFile.getMimeType(),
                                                                    mFile.getEtagInConflict(),
                                                                    lastModifiedTimestamp,
                                                                    creationTimestamp,
                                                                    onWifiConnection,
                                                                    mDisableRetries)
            } else {
                mUploadOperation = UploadFileRemoteOperation(mFile.getStoragePath(),
                                                             mFile.getRemotePath(),
                                                             mFile.getMimeType(),
                                                             mFile.getEtagInConflict(),
                                                             lastModifiedTimestamp,
                                                             creationTimestamp,
                                                             mDisableRetries)
            }

            for mDataTransferListener in mDataTransferListeners {
                mUploadOperation?.addDataTransferProgressListener(listener: mDataTransferListener)
            }

            if mCancellationRequested.get() {
                throw OperationCancelledException()
            }

            if result!.isSuccess && mUploadOperation != nil {
                result = mUploadOperation?.execute(client: client)

                if !result!.isSuccess && result!.getHttpCode() == HttpStatus.SC_PRECONDITION_FAILED {
                    result = RemoteOperationResult(ResultCode.SYNC_CONFLICT)
                }
            }
        } catch is FileNotFoundException {
            Log_OC.d(UploadFileOperation.TAG, "\(mOriginalStoragePath) not exists anymore")
            result = RemoteOperationResult(ResultCode.LOCAL_FILE_NOT_FOUND)
        } catch is OverlappingFileLockException {
            Log_OC.d(UploadFileOperation.TAG, "Overlapping file lock exception")
            result = RemoteOperationResult(ResultCode.LOCK_FAILED)
        } catch {
            result = RemoteOperationResult(error: error)
        } finally {
            mUploadStarted.set(false)

            if fileLock != nil {
                do {
                    try fileLock?.release()
                } catch {
                    Log_OC.e(UploadFileOperation.TAG, "Failed to unlock file with path \(mOriginalStoragePath)")
                }
            }

            if channel != nil {
                do {
                    try channel?.close()
                } catch {
                    Log_OC.w(UploadFileOperation.TAG, "Failed to close file channel")
                }
            }

            if temporalFile != nil && !originalFile.equals(temporalFile!) {
                temporalFile?.delete()
            }

            if result == nil {
                result = RemoteOperationResult(ResultCode.UNKNOWN_ERROR)
            }

            logResult(result: result!, sourcePath: mOriginalStoragePath, targetPath: mRemotePath)
        }

        if result!.isSuccess {
            handleSuccessfulUpload(temporalFile: temporalFile, expectedFile: expectedFile, originalFile: originalFile, client: client)
        } else if result!.getCode() == ResultCode.SYNC_CONFLICT {
            getStorageManager().saveConflict(mFile, mFile.getEtagInConflict())
        }

        if temporalFile != nil && temporalFile!.exists() && !temporalFile!.delete() {
            Log_OC.e(UploadFileOperation.TAG, "Could not delete temporal file \(temporalFile!.getAbsolutePath())")
        }

        return result!
    }

    private func updateSize(size: Int64) {
        if var ocUpload = uploadsStorageManager.getUploadById(getOCUploadId()) {
            ocUpload.setFileSize(size)
            uploadsStorageManager.updateUpload(ocUpload)
        }
    }

    private func logResult(result: RemoteOperationResult, sourcePath: String, targetPath: String) {
        if result.isSuccess() {
            Log_OC.i(UploadFileOperation.TAG, "Upload of \(sourcePath) to \(targetPath): \(result.getLogMessage())")
        } else {
            if let exception = result.getException() {
                if result.isCancelled() {
                    Log_OC.w(UploadFileOperation.TAG, "Upload of \(sourcePath) to \(targetPath): \(result.getLogMessage())")
                } else {
                    Log_OC.e(UploadFileOperation.TAG, "Upload of \(sourcePath) to \(targetPath): \(result.getLogMessage())", exception)
                }
            } else {
                Log_OC.e(UploadFileOperation.TAG, "Upload of \(sourcePath) to \(targetPath): \(result.getLogMessage())")
            }
        }
    }

    private func copyFile(originalFile: File, expectedPath: String) throws -> RemoteOperationResult {
        if mLocalBehaviour == FileUploadWorker.LOCAL_BEHAVIOUR_COPY && mOriginalStoragePath != expectedPath {
            let temporalPath = FileStorageUtils.getInternalTemporalPath(user.getAccountName(), mContext) + mFile.getRemotePath()
            mFile.setStoragePath(temporalPath)
            let temporalFile = File(temporalPath)

            return try copy(sourceFile: originalFile, targetFile: temporalFile)
        }

        if mCancellationRequested.get() {
            throw OperationCancelledException()
        }

        return RemoteOperationResult(resultCode: .OK)
    }

    func checkNameCollision(parentFile: OCFile?, client: OwnCloudClient, fileNames: [String], encrypted: Bool) throws -> RemoteOperationResult? {
        Log_OC.d(UploadFileOperation.TAG, "Checking name collision in server")

        if existsFile(client: client, remotePath: mRemotePath, fileNames: fileNames, encrypted: encrypted) {
            switch mNameCollisionPolicy {
            case .CANCEL:
                Log_OC.d(UploadFileOperation.TAG, "File exists; canceling")
                throw OperationCancelledException()
            case .RENAME:
                mRemotePath = UploadFileOperation.getNewAvailableRemotePath(client: client, remotePath: mRemotePath, fileNames: fileNames, encrypted: encrypted)
                mWasRenamed = true
                createNewOCFile(newRemotePath: mRemotePath)
                Log_OC.d(UploadFileOperation.TAG, "File renamed as \(mRemotePath)")
                mRenameUploadListener?.onRenameUpload()
            case .OVERWRITE:
                if let parentFile = parentFile, encrypted {
                    duplicatedEncryptedFile = getStorageManager().findDuplicatedFile(parentFile: parentFile, file: mFile)
                }
                Log_OC.d(UploadFileOperation.TAG, "Overwriting file")
            case .ASK_USER:
                Log_OC.d(UploadFileOperation.TAG, "Name collision; asking the user what to do")
                return RemoteOperationResult(resultCode: .SYNC_CONFLICT)
            }
        }

        if mCancellationRequested.get() {
            throw OperationCancelledException()
        }

        return nil
    }

    private func handleSuccessfulUpload(temporalFile: File?, expectedFile: File?, originalFile: File, client: OwnCloudClient) {
        switch mLocalBehaviour {
        case FileUploadWorker.LOCAL_BEHAVIOUR_FORGET:
            fallthrough
        default:
            mFile.setStoragePath("")
            saveUploadedFile(client: client)
            
        case FileUploadWorker.LOCAL_BEHAVIOUR_DELETE:
            originalFile.delete()
            mFile.setStoragePath("")
            getStorageManager().deleteFileInMediaScan(originalFile.getAbsolutePath())
            saveUploadedFile(client: client)
            
        case FileUploadWorker.LOCAL_BEHAVIOUR_COPY:
            if let temporalFile = temporalFile {
                do {
                    try move(sourceFile: temporalFile, targetFile: expectedFile!)
                } catch {
                    Log_OC.e(UploadFileOperation.TAG, error.localizedDescription)
                }
            } else if let originalFile = originalFile {
                do {
                    try copy(sourceFile: originalFile, targetFile: expectedFile!)
                } catch {
                    Log_OC.e(UploadFileOperation.TAG, error.localizedDescription)
                }
            }
            mFile.setStoragePath(expectedFile!.getAbsolutePath())
            saveUploadedFile(client: client)
            if MimeTypeUtil.isMedia(mFile.getMimeType()) {
                FileDataStorageManager.triggerMediaScan(expectedFile!.getAbsolutePath())
            }
            
        case FileUploadWorker.LOCAL_BEHAVIOUR_MOVE:
            let expectedPath = FileStorageUtils.getDefaultSavePathFor(user.getAccountName(), mFile)
            let newFile = File(expectedPath)
            
            do {
                try move(sourceFile: originalFile, targetFile: newFile)
            } catch {
                Log_OC.e(UploadFileOperation.TAG, "Error moving file", error)
            }
            getStorageManager().deleteFileInMediaScan(originalFile.getAbsolutePath())
            mFile.setStoragePath(newFile.getAbsolutePath())
            saveUploadedFile(client: client)
            if MimeTypeUtil.isMedia(mFile.getMimeType()) {
                FileDataStorageManager.triggerMediaScan(newFile.getAbsolutePath())
            }
        }
    }

    private func getCapabilities() -> OCCapability {
        return CapabilityUtils.getCapability(mContext)
    }

    private func grantFolderExistence(pathToGrant: String, client: OwnCloudClient) -> RemoteOperationResult {
        let operation = ExistenceCheckRemoteOperation(path: pathToGrant, isFolder: false)
        var result = operation.execute(client: client)
        if !result.isSuccess && result.getCode() == .FILE_NOT_FOUND && mRemoteFolderToBeCreated {
            let syncOp = CreateFolderOperation(path: pathToGrant, user: user, context: getContext(), storageManager: getStorageManager())
            result = syncOp.execute(client: client)
        }
        if result.isSuccess {
            var parentDir = getStorageManager().getFileByPath(pathToGrant)
            if parentDir == nil {
                parentDir = createLocalFolder(remotePath: pathToGrant)
            }
            if parentDir != nil {
                result = RemoteOperationResult(resultCode: .OK)
            } else {
                result = RemoteOperationResult(resultCode: .CANNOT_CREATE_FILE)
            }
        }
        return result
    }

    private func createLocalFolder(remotePath: String) -> OCFile? {
        var parentPath = (remotePath as NSString).deletingLastPathComponent
        parentPath = parentPath.hasSuffix(OCFile.PATH_SEPARATOR) ? parentPath : parentPath + OCFile.PATH_SEPARATOR
        var parent = getStorageManager().getFileByPath(parentPath)
        if parent == nil {
            parent = createLocalFolder(remotePath: parentPath)
        }
        if let parent = parent {
            let createdFolder = OCFile(remotePath: remotePath)
            createdFolder.setMimeType(MimeType.DIRECTORY)
            createdFolder.setParentId(parent.getFileId())
            getStorageManager().saveFile(createdFolder)
            return createdFolder
        }
        return nil
    }

    private func createNewOCFile(newRemotePath: String) {
        let newFile = OCFile(remotePath: newRemotePath)
        newFile.setCreationTimestamp(mFile.getCreationTimestamp())
        newFile.setFileLength(mFile.getFileLength())
        newFile.setMimeType(mFile.getMimeType())
        newFile.setModificationTimestamp(mFile.getModificationTimestamp())
        newFile.setModificationTimestampAtLastSyncForData(mFile.getModificationTimestampAtLastSyncForData())
        newFile.setEtag(mFile.getEtag())
        newFile.setLastSyncDateForProperties(mFile.getLastSyncDateForProperties())
        newFile.setLastSyncDateForData(mFile.getLastSyncDateForData())
        newFile.setStoragePath(mFile.getStoragePath())
        newFile.setParentId(mFile.getParentId())
        mOldFile = mFile
        mFile = newFile
    }

    static func getNewAvailableRemotePath(client: OwnCloudClient, remotePath: String, fileNames: [String], encrypted: Bool) -> String {
        let extPos = remotePath.lastIndex(of: ".") ?? remotePath.endIndex
        var suffix: String
        var extensionPart = ""
        var remotePathWithoutExtension = ""
        if extPos < remotePath.endIndex {
            extensionPart = String(remotePath[remotePath.index(after: extPos)...])
            remotePathWithoutExtension = String(remotePath[..<extPos])
        }

        var count = 2
        var exists: Bool
        var newPath: String
        repeat {
            suffix = " (\(count))"
            newPath = extPos < remotePath.endIndex ? remotePathWithoutExtension + suffix + "." + extensionPart : remotePath + suffix
            exists = existsFile(client: client, remotePath: newPath, fileNames: fileNames, encrypted: encrypted)
            count += 1
        } while exists

        return newPath
    }

    private static func existsFile(client: OwnCloudClient, remotePath: String, fileNames: [String], encrypted: Bool) -> Bool {
        if encrypted {
            let fileName = (remotePath as NSString).lastPathComponent

            for name in fileNames {
                if name.caseInsensitiveCompare(fileName) == .orderedSame {
                    return true
                }
            }

            return false
        } else {
            let existsOperation = ExistenceCheckRemoteOperation(remotePath: remotePath, isFolder: false)
            let result = existsOperation.execute(client: client)
            return result.isSuccess
        }
    }

    func cancel(cancellationReason: ResultCode) {
        if mUploadOperation == nil {
            if mUploadStarted.get() {
                Log_OC.d(UploadFileOperation.TAG, "Cancelling upload during upload preparations.")
                mCancellationRequested.set(true)
            } else {
                mCancellationRequested.set(true)
                Log_OC.e(UploadFileOperation.TAG, "No upload in progress. This should not happen.")
            }
        } else {
            Log_OC.d(UploadFileOperation.TAG, "Cancelling upload during actual upload operation.")
            mUploadOperation?.cancel(cancellationReason: cancellationReason)
        }
    }

    func isUploadInProgress() -> Bool {
        return mUploadStarted.get()
    }

    private func copy(sourceFile: File, targetFile: File) throws -> RemoteOperationResult {
        Log_OC.d(UploadFileOperation.TAG, "Copying local file")

        if FileStorageUtils.getUsableSpace() < sourceFile.length() {
            return RemoteOperationResult(resultCode: .LOCAL_STORAGE_FULL)
        } else {
            Log_OC.d(UploadFileOperation.TAG, "Creating temporal folder")
            let temporalParent = targetFile.getParentFile()

            if !temporalParent.mkdirs() && !temporalParent.isDirectory() {
                return RemoteOperationResult(resultCode: .CANNOT_CREATE_FILE)
            }

            Log_OC.d(UploadFileOperation.TAG, "Creating temporal file")
            if !targetFile.createNewFile() && !targetFile.isFile() {
                return RemoteOperationResult(resultCode: .CANNOT_CREATE_FILE)
            }

            Log_OC.d(UploadFileOperation.TAG, "Copying file contents")
            var inputStream: InputStream? = nil
            var outputStream: OutputStream? = nil

            do {
                if mOriginalStoragePath != targetFile.getAbsolutePath() {
                    if mOriginalStoragePath.hasPrefix(UriUtils.URI_CONTENT_SCHEME) {
                        let uri = URL(string: mOriginalStoragePath)!
                        inputStream = mContext.getContentResolver().openInputStream(uri)
                    } else {
                        inputStream = InputStream(fileAtPath: sourceFile.getPath())
                    }
                    outputStream = OutputStream(toFileAtPath: targetFile.getPath(), append: false)
                    outputStream?.open()
                    inputStream?.open()
                    
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while !mCancellationRequested.get() && inputStream!.hasBytesAvailable {
                        let bytesRead = inputStream!.read(&buffer, maxLength: buffer.count)
                        if bytesRead > 0 {
                            outputStream!.write(buffer, maxLength: bytesRead)
                        }
                    }
                    outputStream?.close()
                    inputStream?.close()
                }

                if mCancellationRequested.get() {
                    return RemoteOperationResult(OperationCancelledException())
                }
            } catch {
                return RemoteOperationResult(resultCode: .LOCAL_STORAGE_NOT_COPIED)
            } finally {
                if inputStream != nil {
                    inputStream?.close()
                }
                if outputStream != nil {
                    outputStream?.close()
                }
            }
        }
        return RemoteOperationResult(resultCode: .OK)
    }

    private func move(sourceFile: File, targetFile: File) throws {
        if targetFile != sourceFile {
            let expectedFolder = targetFile.getParentFile()
            expectedFolder.mkdirs()

            if expectedFolder.isDirectory() {
                if !sourceFile.renameTo(targetFile) {
                    targetFile.createNewFile()
                    let inChannel = try FileInputStream(sourceFile).getChannel()
                    let outChannel = try FileOutputStream(targetFile).getChannel()
                    defer {
                        inChannel.close()
                        outChannel.close()
                    }
                    do {
                        inChannel.transferTo(0, inChannel.size(), outChannel)
                        sourceFile.delete()
                    } catch {
                        mFile.setStoragePath("")
                    }
                }
            } else {
                mFile.setStoragePath("")
            }
        }
    }

    private func saveUploadedFile(client: OwnCloudClient) {
        var file = mFile
        if file.fileExists() {
            file = getStorageManager().getFileById(file.getFileId())
        }
        guard let file = file else {
            return
        }
        let syncDate = Date().timeIntervalSince1970
        file.setLastSyncDateForData(syncDate)

        let path: String
        if encryptedAncestor {
            path = file.getParentRemotePath() + mFile.getEncryptedFileName()
        } else {
            path = getRemotePath()
        }

        let operation = ReadFileRemoteOperation(path: path)
        let result = operation.execute(client: client)
        if result.isSuccess() {
            updateOCFile(file: file, remoteFile: result.getData().first as! RemoteFile)
            file.setLastSyncDateForProperties(syncDate)
        } else {
            Log_OC.e(UploadFileOperation.TAG, "Error reading properties of file after successful upload; this is gonna hurt...")
        }

        if mWasRenamed {
            if let oldFile = getStorageManager().getFileByPath(mOldFile!.getRemotePath()) {
                oldFile.setStoragePath(nil)
                getStorageManager().saveFile(oldFile)
                getStorageManager().saveConflict(oldFile, nil)
            }
        }
        file.setUpdateThumbnailNeeded(true)
        getStorageManager().saveFile(file)
        getStorageManager().saveConflict(file, nil)

        if MimeTypeUtil.isMedia(file.getMimeType()) {
            FileDataStorageManager.triggerMediaScan(file.getStoragePath(), file: file)
        }

        let task = ThumbnailsCacheManager.ThumbnailGenerationTask(storageManager: getStorageManager(), user: user)
        task.execute(ThumbnailsCacheManager.ThumbnailGenerationTaskObject(file: file, remoteId: file.getRemoteId()))
    }

    private func updateOCFile(file: OCFile, remoteFile: RemoteFile) {
        file.setCreationTimestamp(remoteFile.getCreationTimestamp())
        file.setFileLength(remoteFile.getLength())
        file.setMimeType(remoteFile.getMimeType())
        file.setModificationTimestamp(remoteFile.getModifiedTimestamp())
        file.setModificationTimestampAtLastSyncForData(remoteFile.getModifiedTimestamp())
        file.setEtag(remoteFile.getEtag())
        file.setRemoteId(remoteFile.getRemoteId())
        file.setPermissions(remoteFile.getPermissions())
    }

    public protocol OnRenameListener {
        func onRenameUpload()
    }
}
