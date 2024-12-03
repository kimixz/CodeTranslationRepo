
import Foundation
import MobileCoreServices

class DownloadFileOperation: RemoteOperation {
    private static let TAG = String(describing: DownloadFileOperation.self)
    
    private var user: User
    private var file: OCFile
    private var behaviour: String?
    private var etag = ""
    private var activityName: String?
    private var packageName: String?
    private var downloadType: DownloadType
    
    private let context: WeakReference<Context>
    private var dataTransferListeners = Set<OnDatatransferProgressListener>()
    private var modificationTimestamp: Int64 = 0
    private var downloadOperation: DownloadFileRemoteOperation?
    
    private var cancellationRequested = AtomicBoolean(false)
    
    init(user: User, file: OCFile, behaviour: String?, activityName: String?, packageName: String?, context: Context, downloadType: DownloadType) {
        guard user != nil else {
            fatalError("Illegal null user in DownloadFileOperation creation")
        }
        guard file != nil else {
            fatalError("Illegal null file in DownloadFileOperation creation")
        }
        
        self.user = user
        self.file = file
        self.behaviour = behaviour
        self.activityName = activityName
        self.packageName = packageName
        self.context = WeakReference(context)
        self.downloadType = downloadType
    }
    
    convenience init(user: User, file: OCFile, context: Context) {
        self.init(user: user, file: file, behaviour: nil, activityName: nil, packageName: nil, context: context, downloadType: .download)
    }
    
    func isMatching(accountName: String, fileId: Int64) -> Bool {
        return getFile().getFileId() == fileId && getUser().getAccountName() == accountName
    }
    
    func cancelMatchingOperation(accountName: String, fileId: Int64) {
        if isMatching(accountName: accountName, fileId: fileId) {
            cancel()
        }
    }
    
    func getSavePath() -> String {
        if let storagePath = file.getStoragePath() {
            let parentFile = URL(fileURLWithPath: storagePath).deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentFile.path) {
                try? FileManager.default.createDirectory(at: parentFile, withIntermediateDirectories: true, attributes: nil)
            }
            let path = URL(fileURLWithPath: storagePath)
            if FileManager.default.isWritableFile(atPath: path.path) || FileManager.default.isWritableFile(atPath: parentFile.path) {
                return path.path
            }
        }
        return FileStorageUtils.getDefaultSavePathFor(user.getAccountName(), file)
    }
    
    func getTmpPath() -> String {
        return FileStorageUtils.getTemporalPath(user.accountName) + file.remotePath
    }
    
    func getTmpFolder() -> String {
        return FileStorageUtils.getTemporalPath(user.accountName)
    }
    
    func getRemotePath() -> String {
        return file.getRemotePath()
    }
    
    func getMimeType() -> String {
        var mimeType = file.getMimeType()
        if mimeType.isEmpty {
            do {
                let fileExtension = file.getRemotePath().components(separatedBy: ".").last ?? ""
                mimeType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension as CFString, nil)?.takeRetainedValue() as String? ?? ""
            } catch {
                print("Trying to find out MIME type of a file without extension: \(file.getRemotePath())")
            }
        }
        if mimeType.isEmpty {
            mimeType = "application/octet-stream"
        }
        return mimeType
    }
    
    func getSize() -> Int64 {
        return file.getFileLength()
    }
    
    func getModificationTimestamp() -> Int64 {
        return modificationTimestamp > 0 ? modificationTimestamp : file.getModificationTimestamp()
    }
    
    override func run(client: OwnCloudClient) -> RemoteOperationResult {
        objc_sync_enter(cancellationRequested)
        defer { objc_sync_exit(cancellationRequested) }
        if cancellationRequested.boolValue {
            return RemoteOperationResult(OperationCancelledException())
        }
        
        guard let operationContext = context.get() else {
            return RemoteOperationResult(.unknownError)
        }
        
        var result: RemoteOperationResult
        var newFile: File?
        var moved: Bool
        
        let tmpFile = File(getTmpPath())
        
        let tmpFolder = getTmpFolder()
        
        downloadOperation = DownloadFileRemoteOperation(file.remotePath, tmpFolder)
        
        if downloadType == .download {
            for listener in dataTransferListeners {
                downloadOperation?.addDatatransferProgressListener(listener)
            }
        }
        
        result = downloadOperation?.execute(client) ?? RemoteOperationResult(.unknownError)
        
        if result.isSuccess {
            modificationTimestamp = downloadOperation?.modificationTimestamp ?? 0
            etag = downloadOperation?.etag ?? ""
            
            if downloadType == .download {
                newFile = File(getSavePath())
                
                if !(newFile?.parentFile.exists() ?? false) && !(newFile?.parentFile.mkdirs() ?? false) {
                    Log_OC.e(DownloadFileOperation.TAG, "Unable to create parent folder \(newFile?.parentFile.absolutePath ?? "")")
                }
            }
            
            if file.isEncrypted {
                let fileDataStorageManager = FileDataStorageManager(user: user, contentResolver: operationContext.contentResolver)
                
                let parent = fileDataStorageManager.getFileByEncryptedRemotePath(file.parentRemotePath)
                
                let object = EncryptionUtils.downloadFolderMetadata(parent, client: client, context: operationContext, user: user)
                
                guard let object = object else {
                    return RemoteOperationResult(.metadataNotFound)
                }
                
                var keyString: String
                var nonceString: String
                var authenticationTagString: String
                if let decryptedFolderMetadataFile = object as? DecryptedFolderMetadataFile {
                    guard let decryptedFile = decryptedFolderMetadataFile.metadata.files[file.encryptedFileName] else {
                        return RemoteOperationResult(.metadataNotFound)
                    }
                    
                    keyString = decryptedFile.key
                    nonceString = decryptedFile.nonce
                    authenticationTagString = decryptedFile.authenticationTag
                } else if let decryptedFolderMetadataFileV1 = object as? DecryptedFolderMetadataFileV1 {
                    guard let decryptedFile = decryptedFolderMetadataFileV1.files[file.encryptedFileName] else {
                        return RemoteOperationResult(.metadataNotFound)
                    }
                    
                    keyString = decryptedFile.encrypted.key
                    nonceString = decryptedFile.initializationVector
                    authenticationTagString = decryptedFile.authenticationTag
                } else {
                    return RemoteOperationResult(.metadataNotFound)
                }
                
                let key = decodeStringToBase64Bytes(keyString)
                let iv = decodeStringToBase64Bytes(nonceString)
                
                do {
                    let cipher = try EncryptionUtils.getCipher(.decryptMode, key: key, iv: iv)
                    try EncryptionUtils.decryptFile(cipher, tmpFile: tmpFile, newFile: newFile, authenticationTag: authenticationTagString, dataProvider: ArbitraryDataProviderImpl(operationContext), user: user)
                } catch {
                    return RemoteOperationResult(error)
                }
            }
            
            if downloadType == .download && !file.isEncrypted {
                moved = tmpFile.renameTo(newFile)
                let isLastModifiedSet = newFile?.setLastModified(file.modificationTimestamp) ?? false
                Log_OC.d(DownloadFileOperation.TAG, "Last modified set: \(isLastModifiedSet)")
                if !moved {
                    result = RemoteOperationResult(.localStorageNotMoved)
                }
            } else if downloadType == .export {
                FileExportUtils().exportFile(file.fileName, mimeType: file.mimeType, contentResolver: operationContext.contentResolver, uri: nil, tmpFile: tmpFile)
                if !tmpFile.delete() {
                    Log_OC.e(DownloadFileOperation.TAG, "Deletion of \(tmpFile.absolutePath) failed!")
                }
            }
        }
        
        Log_OC.i(DownloadFileOperation.TAG, "Download of \(file.remotePath) to \(getSavePath()): \(result.logMessage)")
        
        return result
    }
    
    func cancel() {
        cancellationRequested = true
        downloadOperation?.cancel()
    }
    
    func addDownloadDataTransferProgressListener(listener: OnDatatransferProgressListener) {
        objc_sync_enter(dataTransferListeners)
        dataTransferListeners.insert(listener)
        objc_sync_exit(dataTransferListeners)
    }
    
    func removeDatatransferProgressListener(listener: OnDatatransferProgressListener) {
        objc_sync_enter(dataTransferListeners)
        defer { objc_sync_exit(dataTransferListeners) }
        dataTransferListeners.remove(listener)
    }
    
    func getUser() -> User {
        return self.user
    }
    
    func getFile() -> OCFile? {
        return self.file
    }
    
    func getBehaviour() -> String? {
        return self.behaviour
    }
    
    func getEtag() -> String {
        return self.etag
    }
    
    func getActivityName() -> String? {
        return self.activityName
    }
    
    func getPackageName() -> String? {
        return self.packageName
    }
    
    func getDownloadType() -> DownloadType {
        return downloadType
    }
}
