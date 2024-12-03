
import Foundation
import UIKit

class DocumentsStorageProvider: DocumentsProvider {
    private static let TAG = String(describing: DocumentsStorageProvider.self)
    private static let CACHE_EXPIRATION = TimeUnit.MILLISECONDS.convert(1, TimeUnit.MINUTES)
    
    @Inject var accountManager: UserAccountManager!
    
    private var isFolderPathValid = true
    
    @VisibleForTesting
    static let DOCUMENTID_SEPARATOR = "/"
    private static let DOCUMENTID_PARTS = 2
    private var rootIdToStorageManager = [String: FileDataStorageManager]()
    
    private let executor = Executors.newCachedThreadPool()
    
    override func queryRoots(projection: [String]?) -> Cursor {
        initiateStorageMap()
        
        let context = MainApp.getAppContext()
        let preferences = AppPreferencesImpl.fromContext(context)
        if preferences.getLockPreference() == SettingsActivity.LOCK_PASSCODE ||
            preferences.getLockPreference() == SettingsActivity.LOCK_DEVICE_CREDENTIALS {
            return FileCursor()
        }
        
        let result = RootCursor(projection: projection)
        for manager in rootIdToStorageManager.values {
            result.addRoot(Document(manager: manager, path: ROOT_PATH), context: getContext())
        }
        
        return result
    }
    
    static func notifyRootsChanged(context: Context) {
        let authority = context.getString(R.string.document_provider_authority)
        let rootsUri = DocumentsContract.buildRootsUri(authority)
        context.getContentResolver().notifyChange(rootsUri, nil)
    }
    
    override func queryDocument(documentId: String, projection: [String]?) throws -> Cursor {
        Log_OC.d(TAG, "queryDocument(), id=\(documentId)")
        
        let document = toDocument(documentId)
        
        let result = FileCursor(projection: projection)
        result.addFile(document)
        
        return result
    }
    
    func queryChildDocuments(parentDocumentId: String, projection: [String]?, sortOrder: String?) throws -> FileCursor {
        Log_OC.d(TAG, "queryChildDocuments(), id=\(parentDocumentId)")
        
        let context = getNonNullContext()
        let parentFolder = toDocument(parentDocumentId)
        let resultCursor = FileCursor(projection: projection)
        
        if parentFolder.getFile().isEncrypted() &&
            !FileOperationsHelper.isEndToEndEncryptionSetup(context: context, user: parentFolder.getUser()) {
            Toast.makeText(context, R.string.e2e_not_yet_setup, Toast.LENGTH_LONG).show()
            return resultCursor
        }
        
        let storageManager = parentFolder.getStorageManager()
        
        for file in storageManager.getFolderContent(parentFolder.getFile(), false) {
            resultCursor.addFile(Document(storageManager: storageManager, file: file))
        }
        
        var isLoading = false
        if parentFolder.isExpired() {
            let task = ReloadFolderDocumentTask(parentFolder: parentFolder) { result in
                context.getContentResolver().notifyChange(toNotifyUri(document: parentFolder), nil, false)
            }
            task.executeOnExecutor(executor: executor)
            resultCursor.setLoadingTask(task: task)
            isLoading = true
        }
        
        let extra = Bundle()
        extra.putBoolean(DocumentsContract.EXTRA_LOADING, isLoading)
        resultCursor.setExtras(extra)
        resultCursor.setNotificationUri(context.getContentResolver(), toNotifyUri(document: parentFolder))
        return resultCursor
    }
    
    func openDocument(documentId: String, mode: String, cancellationSignal: Any?) throws -> FileHandle? {
        Log_OC.d(TAG, "openDocument(), id=\(documentId)")
        
        guard isFolderPathValid else {
            Log_OC.d(TAG, "Folder path is not valid, operation is cancelled")
            return nil
        }
        
        let document = toDocument(documentId: documentId)
        let context = getNonNullContext()
        
        let ocFile = document.getFile()
        let user = document.getUser()
        
        let accessMode = try FileHandle.AccessMode(mode: mode)
        let writeOnly = accessMode.contains(.writeOnly)
        let needsDownload = !ocFile.existsOnDevice() || (!writeOnly && hasServerChange(document: document))
        if needsDownload {
            if ocFile.getLocalModificationTimestamp() > ocFile.getLastSyncDateForData() {
                Log_OC.w(TAG, "Conflict found!")
            } else {
                let downloadResult = AtomicBoolean(false)
                let downloadThread = Thread {
                    let downloadFileOperation = DownloadFileOperation(user: user, ocFile: ocFile, context: context)
                    let result = downloadFileOperation.execute(client: document.getClient())
                    if !result.isSuccess() {
                        if ocFile.isDown() {
                            DispatchQueue.main.async {
                                let alert = UIAlertController(title: nil, message: "File not synced", preferredStyle: .alert)
                                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                                UIApplication.shared.keyWindow?.rootViewController?.present(alert, animated: true, completion: nil)
                            }
                            downloadResult.set(true)
                        } else {
                            Log_OC.e(TAG, result.description)
                        }
                    } else {
                        saveDownloadedFile(storageManager: document.getStorageManager(), downloadFileOperation: downloadFileOperation, ocFile: ocFile)
                        downloadResult.set(true)
                    }
                }
                downloadThread.start()
                
                downloadThread.join()
                if !downloadResult.get() {
                    throw NSError(domain: "FileNotFound", code: 0, userInfo: [NSLocalizedDescriptionKey: "Error downloading file: \(ocFile.getFileName())"])
                }
            }
        }
        
        let file = FileManager.default.fileExists(atPath: ocFile.getStoragePath()) ? ocFile.getStoragePath() : nil
        
        if accessMode != .readOnly {
            let handler = DispatchQueue.main
            do {
                return try FileHandle(forUpdatingAtPath: file!)
            } catch {
                throw NSError(domain: "FileNotFound", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to open document for writing \(ocFile.getFileName())"])
            }
        } else {
            return try FileHandle(forReadingAtPath: file!)
        }
    }
    
    private func hasServerChange(document: Document) throws -> Bool {
        let context = getNonNullContext()
        let ocFile = document.getFile()
        let result = CheckEtagRemoteOperation(remotePath: ocFile.getRemotePath(), etag: ocFile.getEtag())
            .execute(user: document.getUser(), context: context)
        
        switch result.getCode() {
        case .etagChanged:
            return true
        case .etagUnchanged:
            return false
        case .fileNotFound, _:
            Log_OC.e(TAG, result.description)
            throw NSError(domain: "FileNotFoundException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Error synchronizing file: \(ocFile.getFileName())"])
        }
    }
    
    private func saveDownloadedFile(storageManager: FileDataStorageManager, dfo: DownloadFileOperation, file: OCFile) {
        let syncDate = Date().timeIntervalSince1970
        file.setLastSyncDateForProperties(syncDate)
        file.setLastSyncDateForData(syncDate)
        file.setUpdateThumbnailNeeded(true)
        file.setModificationTimestamp(dfo.getModificationTimestamp())
        file.setModificationTimestampAtLastSyncForData(dfo.getModificationTimestamp())
        file.setEtag(dfo.getEtag())
        file.setMimeType(dfo.getMimeType())
        let savePath = dfo.getSavePath()
        file.setStoragePath(savePath)
        file.setFileLength(FileManager.default.attributesOfItem(atPath: savePath)[.size] as? Int64 ?? 0)
        file.setRemoteId(dfo.getFile().getRemoteId())
        storageManager.saveFile(file)
        if MimeTypeUtil.isMedia(dfo.getMimeType()) {
            FileDataStorageManager.triggerMediaScan(file.getStoragePath(), file)
        }
        storageManager.saveConflict(file, nil)
    }
    
    override func onCreate() -> Bool {
        AndroidInjection.inject(self)
        
        initiateStorageMap()
        
        return true
    }
    
    override func openDocumentThumbnail(documentId: String, sizeHint: CGPoint, signal: CancellationSignal) throws -> AssetFileDescriptor {
        Log_OC.d(TAG, "openDocumentThumbnail(), id=\(documentId)")
        
        let document = toDocument(documentId)
        let file = document.getFile()
        
        let exists = ThumbnailsCacheManager.containsBitmap(ThumbnailsCacheManager.PREFIX_THUMBNAIL + file.getRemoteId())
        if !exists {
            ThumbnailsCacheManager.generateThumbnailFromOCFile(file, document.getUser(), getContext())
        }
        
        return AssetFileDescriptor(DiskLruImageCacheFileProvider.getParcelFileDescriptorForOCFile(file), 0, file.getFileLength())
    }
    
    override func renameDocument(documentId: String, displayName: String) throws -> String? {
        Log_OC.d(TAG, "renameDocument(), id=\(documentId)")
        
        if let errorMessage = checkFileName(displayName) {
            ContextExtensionsKt.showToast(getNonNullContext(), errorMessage)
            return nil
        }
        
        let document = toDocument(documentId)
        let result = RenameFileOperation(remotePath: document.getRemotePath(),
                                         newName: displayName,
                                         storageManager: document.getStorageManager())
            .execute(client: document.getClient())
        
        if !result.isSuccess() {
            Log_OC.e(TAG, result.description)
            throw NSError(domain: "FileNotFoundException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to rename document with documentId \(documentId): \(result.getException())"])
        }
        
        let context = getNonNullContext()
        context.contentResolver.notifyChange(toNotifyUri(document.getParent()), observer: nil, syncToNetwork: false)
        
        return nil
    }
    
    override func copyDocument(sourceDocumentId: String, targetParentDocumentId: String) throws -> String? {
        Log_OC.d(TAG, "copyDocument(), id=\(sourceDocumentId)")
        
        let targetFolder = toDocument(targetParentDocumentId)
        
        let filename = targetFolder.getFile().getFileName()
        isFolderPathValid = checkFolderPath(filename)
        if !isFolderPathValid {
            ContextExtensionsKt.showToast(getNonNullContext(), R.string.file_name_validator_error_contains_reserved_names_or_invalid_characters)
            return nil
        }
        
        let document = toDocument(sourceDocumentId)
        let storageManager = document.getStorageManager()
        let result = CopyFileOperation(remotePath: document.getRemotePath(),
                                       targetRemotePath: targetFolder.getRemotePath(),
                                       storageManager: document.getStorageManager())
            .execute(client: document.getClient())
        
        if !result.isSuccess() {
            Log_OC.e(TAG, result.description)
            throw NSError(domain: "FileNotFoundException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to copy document with documentId \(sourceDocumentId) to \(targetParentDocumentId)"])
        }
        
        let context = getNonNullContext()
        let user = document.getUser()
        
        let updateParent = RefreshFolderOperation(file: targetFolder.getFile(),
                                                  timestamp: Date().timeIntervalSince1970,
                                                  recursive: false,
                                                  force: false,
                                                  sync: true,
                                                  storageManager: storageManager,
                                                  user: user,
                                                  context: context)
            .execute(client: targetFolder.getClient())
        
        if !updateParent.isSuccess() {
            Log_OC.e(TAG, updateParent.description)
            throw NSError(domain: "FileNotFoundException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to copy document with documentId \(sourceDocumentId) to \(targetParentDocumentId)"])
        }
        
        var newPath = targetFolder.getRemotePath() + document.getFile().getFileName()
        
        if document.getFile().isFolder() {
            newPath += PATH_SEPARATOR
        }
        let newFile = Document(storageManager: storageManager, remotePath: newPath)
        
        context.contentResolver.notifyChange(toNotifyUri(targetFolder), observer: nil, syncToNetwork: false)
        
        return newFile.getDocumentId()
    }
    
    override func moveDocument(sourceDocumentId: String, sourceParentDocumentId: String, targetParentDocumentId: String) throws -> String? {
        Log_OC.d(TAG, "moveDocument(), id=\(sourceDocumentId)")
        
        let targetFolder = toDocument(targetParentDocumentId)
        
        let filename = targetFolder.getFile().getFileName()
        isFolderPathValid = checkFolderPath(filename)
        if !isFolderPathValid {
            ContextExtensionsKt.showToast(getNonNullContext(), R.string.file_name_validator_error_contains_reserved_names_or_invalid_characters)
            return nil
        }
        
        let document = toDocument(sourceDocumentId)
        let result = MoveFileOperation(remotePath: document.getRemotePath(),
                                       targetRemotePath: targetFolder.getRemotePath(),
                                       storageManager: document.getStorageManager())
            .execute(client: document.getClient())
        
        if !result.isSuccess() {
            Log_OC.e(TAG, result.description)
            throw NSError(domain: "FileNotFoundException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to move document with documentId \(sourceDocumentId) to \(targetParentDocumentId)"])
        }
        
        let sourceFolder = toDocument(sourceParentDocumentId)
        
        let context = getNonNullContext()
        context.contentResolver.notifyChange(toNotifyUri(sourceFolder), observer: nil, syncToNetwork: false)
        context.contentResolver.notifyChange(toNotifyUri(targetFolder), observer: nil, syncToNetwork: false)
        
        return sourceDocumentId
    }
    
    override func querySearchDocuments(rootId: String, query: String, projection: [String]?) -> Cursor {
        Log_OC.d(TAG, "querySearchDocuments(), rootId=\(rootId)")
        
        let result = FileCursor(projection: projection)
        
        guard let storageManager = getStorageManager(rootId: rootId) else {
            return result
        }
        
        for document in findFiles(Document(storageManager: storageManager, path: ROOT_PATH), query: query) {
            result.addFile(document)
        }
        
        return result
    }
    
    private func getCapabilities() -> OCCapability {
        return CapabilityUtils.getCapability(accountManager.getUser(), getNonNullContext())
    }
    
    private func checkFolderPath(filename: String) -> Bool {
        return FileNameValidator.INSTANCE.checkFolderPath(filename, getCapabilities(), getNonNullContext())
    }
    
    private func checkFileName(_ filename: String) -> String {
        return FileNameValidator.INSTANCE.checkFileName(filename, getCapabilities(), getNonNullContext(), nil)
    }
    
    override func createDocument(documentId: String, mimeType: String, displayName: String) throws -> String? {
        Log_OC.d(TAG, "createDocument(), id=\(documentId)")
        
        if let errorMessage = checkFileName(displayName) {
            getNonNullContext().showToast(message: errorMessage)
            return nil
        }
        
        let folderDocument = toDocument(documentId)
        
        if mimeType.caseInsensitiveCompare(DocumentsContract.Document.MIME_TYPE_DIR) == .orderedSame {
            return createFolder(folderDocument, displayName: displayName)
        } else {
            return createFile(folderDocument, displayName: displayName, mimeType: mimeType)
        }
    }
    
    private func createFolder(targetFolder: Document, displayName: String) throws -> String {
        let context = getNonNullContext()
        let newDirPath = targetFolder.getRemotePath() + displayName + PATH_SEPARATOR
        let storageManager = targetFolder.getStorageManager()
        
        let result = CreateFolderOperation(newDirPath: newDirPath,
                                           user: accountManager.getUser(),
                                           context: context,
                                           storageManager: storageManager)
            .execute(client: targetFolder.getClient())
        
        if !result.isSuccess() {
            Log_OC.e(TAG, result.description)
            throw NSError(domain: "FileNotFoundException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create document with name \(displayName) and documentId \(targetFolder.getDocumentId())"])
        }
        
        let updateParent = RefreshFolderOperation(file: targetFolder.getFile(), timestamp: Date().timeIntervalSince1970,
                                                  param1: false, param2: false, param3: true, storageManager: storageManager,
                                                  user: targetFolder.getUser(), context: context)
            .execute(client: targetFolder.getClient())
        
        if !updateParent.isSuccess() {
            Log_OC.e(TAG, updateParent.description)
            throw NSError(domain: "FileNotFoundException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create document with documentId \(targetFolder.getDocumentId())"])
        }
        
        let newFolder = Document(storageManager: storageManager, remotePath: newDirPath)
        
        context.contentResolver.notifyChange(toNotifyUri(targetFolder), observer: nil, syncToNetwork: false)
        
        return newFolder.getDocumentId()
    }
    
    private func createFile(targetFolder: Document, displayName: String, mimeType: String) throws -> String {
        let user = targetFolder.getUser()
        
        let tempDir = File(FileStorageUtils.getTemporalPath(user.getAccountName()))
        
        if !tempDir.exists() && !tempDir.mkdirs() {
            throw NSError(domain: "FileNotFoundException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Temp folder could not be created: \(tempDir.getAbsolutePath())"])
        }
        
        let emptyFile = File(tempDir, displayName)
        
        if emptyFile.exists() && !emptyFile.delete() {
            throw NSError(domain: "FileNotFoundException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Previous file could not be deleted"])
        }
        
        do {
            if !emptyFile.createNewFile() {
                throw NSError(domain: "FileNotFoundException", code: 0, userInfo: [NSLocalizedDescriptionKey: "File could not be created"])
            }
        } catch let e as NSError {
            throw getFileNotFoundExceptionWithCause("File could not be created", e)
        }
        
        let newFilePath = targetFolder.getRemotePath() + displayName
        
        let client = targetFolder.getClient()
        let result = UploadFileRemoteOperation(emptyFile.getAbsolutePath(),
                                               newFilePath,
                                               mimeType,
                                               "",
                                               Date().timeIntervalSince1970,
                                               FileUtil.getCreationTimestamp(emptyFile),
                                               false)
            .execute(client)
        
        if !result.isSuccess() {
            Log_OC.e(TAG, result.toString())
            throw NSError(domain: "FileNotFoundException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to upload document with path \(newFilePath)"])
        }
        
        let context = getNonNullContext()
        
        let updateParent = RefreshFolderOperation(targetFolder.getFile(),
                                                  Date().timeIntervalSince1970,
                                                  false,
                                                  false,
                                                  true,
                                                  targetFolder.getStorageManager(),
                                                  user,
                                                  context)
            .execute(client)
        
        if !updateParent.isSuccess() {
            Log_OC.e(TAG, updateParent.toString())
            throw NSError(domain: "FileNotFoundException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create document with documentId \(targetFolder.getDocumentId())"])
        }
        
        let newFile = Document(targetFolder.getStorageManager(), newFilePath)
        
        context.getContentResolver().notifyChange(toNotifyUri(targetFolder), nil, false)
        
        return newFile.getDocumentId()
    }
    
    override func removeDocument(documentId: String, parentDocumentId: String) throws {
        try deleteDocument(documentId: documentId)
    }
    
    func deleteDocument(documentId: String) throws {
        Log_OC.d(TAG, "deleteDocument(), id=\(documentId)")
        
        guard let context = getNonNullContext() else {
            throw NSError(domain: "ContextError", code: 0, userInfo: nil)
        }
        
        let document = toDocument(documentId)
        let parentFolder = document.getParent()
        
        recursiveRevokePermission(document)
        
        guard let file = document.getStorageManager().getFileByPath(document.getRemotePath()) else {
            throw NSError(domain: "FileError", code: 0, userInfo: nil)
        }
        
        let operation = RemoveFileOperation(file: file,
                                            isFolder: false,
                                            user: document.getUser(),
                                            removeLocal: true,
                                            context: context,
                                            storageManager: document.getStorageManager())
        
        let result = operation.execute(document.getClient())
        
        if !result.isSuccess() {
            throw NSError(domain: "FileNotFoundError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to delete document with documentId \(documentId)"])
        }
        
        context.contentResolver.notifyChange(toNotifyUri(parentFolder), observer: nil, syncToNetwork: false)
    }
    
    private func recursiveRevokePermission(document: Document) {
        let storageManager = document.getStorageManager()
        let file = document.getFile()
        if file.isFolder() {
            for child in storageManager.getFolderContent(file, false) {
                recursiveRevokePermission(document: Document(storageManager: storageManager, file: child))
            }
        }
        
        revokeDocumentPermission(documentId: document.getDocumentId())
    }
    
    func isChildDocument(parentDocumentId: String, documentId: String) -> Bool {
        Log_OC.d(TAG, "isChildDocument(), parent=\(parentDocumentId), id=\(documentId)")
        
        do {
            let parentDocument = try toDocument(documentId: parentDocumentId)
            guard let parentFile = parentDocument.getFile() else {
                throw NSError(domain: "FileNotFound", code: 0, userInfo: [NSLocalizedDescriptionKey: "No parent file with ID \(parentDocumentId)"])
            }
            let currentDocument = try toDocument(documentId: documentId)
            guard let childFile = currentDocument.getFile() else {
                throw NSError(domain: "FileNotFound", code: 0, userInfo: [NSLocalizedDescriptionKey: "No child file with ID \(documentId)"])
            }
            
            let parentPath = parentFile.getDecryptedRemotePath()
            let childPath = childFile.getDecryptedRemotePath()
            
            let parentDocumentOwner = parentDocument.getUser()
            let currentDocumentOwner = currentDocument.getUser()
            return parentDocumentOwner.nameEquals(currentDocumentOwner) && childPath.hasPrefix(parentPath)
            
        } catch {
            Log_OC.e(TAG, "failed to check for child document", error)
        }
        
        return false
    }
    
    private func getFileNotFoundExceptionWithCause(msg: String, cause: Error) -> NSError {
        let userInfo: [String: Any] = [NSUnderlyingErrorKey: cause]
        return NSError(domain: "FileNotFoundException", code: 0, userInfo: userInfo)
    }
    
    private func getStorageManager(rootId: String) -> FileDataStorageManager? {
        return rootIdToStorageManager[rootId]
    }
    
    @available(*, deprecated)
    static func rootIdForUser(user: User) -> String {
        return HashUtil.md5Hash(user.getAccountName())
    }
    
    private func initiateStorageMap() {
        rootIdToStorageManager.removeAll()
        
        guard let contentResolver = context?.contentResolver else { return }
        
        for user in accountManager.getAllUsers() {
            let storageManager = FileDataStorageManager(user: user, contentResolver: contentResolver)
            rootIdToStorageManager[rootIdForUser(user)] = storageManager
        }
    }
    
    private func findFiles(root: Document, query: String) -> [Document] {
        let storageManager = root.getStorageManager()
        var result: [Document] = []
        for f in storageManager.getFolderContent(root.getFile(), false) {
            if f.isFolder() {
                result.append(contentsOf: findFiles(root: Document(storageManager: storageManager, file: f), query: query))
            } else if f.getFileName().contains(query) {
                result.append(Document(storageManager: storageManager, file: f))
            }
        }
        return result
    }
    
    private func toNotifyUri(document: Document) -> URL? {
        let authority = Bundle.main.object(forInfoDictionaryKey: "document_provider_authority") as? String ?? ""
        return URL(string: "content://\(authority)/\(document.documentId)")
    }
    
    private func toDocument(documentId: String) throws -> Document {
        let separated = documentId.split(separator: DOCUMENTID_SEPARATOR, maxSplits: DOCUMENTID_PARTS, omittingEmptySubsequences: false)
        if separated.count != DOCUMENTID_PARTS {
            throw NSError(domain: "FileNotFoundException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid documentID \(documentId)!"])
        }
        
        guard let storageManager = rootIdToStorageManager[String(separated[0])] else {
            throw NSError(domain: "FileNotFoundException", code: 0, userInfo: [NSLocalizedDescriptionKey: "No storage manager associated for \(documentId)!"])
        }
        
        return Document(storageManager: storageManager, id: Int64(separated[1])!)
    }
    
    private func getNonNullContext() -> Context {
        guard let context = getContext() else {
            fatalError("IllegalStateException")
        }
        return context
    }
    
    func onTaskFinished(result: RemoteOperationResult) {
        // Implementation goes here
    }
    
    override func doInBackground(_ params: Void...) -> RemoteOperationResult {
        Log_OC.d(TAG, "run ReloadFolderDocumentTask(), id=\(folder.getDocumentId())")
        return RefreshFolderOperation(file: folder.getFile(),
                                      timestamp: Date().timeIntervalSince1970,
                                      param1: false,
                                      param2: true,
                                      param3: true,
                                      storageManager: folder.getStorageManager(),
                                      user: folder.getUser(),
                                      context: MainApp.getAppContext())
            .execute(client: folder.getClient())
    }
    
    override func onPostExecute(result: RemoteOperationResult) {
        callback?.onTaskFinished(result)
    }
    
    func getDocumentId() -> String? {
        for (key, value) in rootIdToStorageManager {
            if storageManager == value {
                return key + DOCUMENTID_SEPARATOR + fileId
            }
        }
        return nil
    }
    
    func getStorageManager() -> FileDataStorageManager {
        return storageManager
    }
    
    func getUser() -> User {
        return getStorageManager().getUser()
    }
    
    func getFile() -> OCFile? {
        return getStorageManager().getFileById(fileId)
    }
    
    func getRemotePath() -> String {
        return getFile().getRemotePath()
    }
    
    func getClient() -> OwnCloudClient? {
        do {
            let ocAccount = try getUser().toOwnCloudAccount()
            return OwnCloudClientManagerFactory.getDefaultSingleton().getClientFor(ocAccount, context: getContext())
        } catch {
            Log_OC.e(TAG, "Failed to set client", error)
        }
        return nil
    }
    
    func isExpired() -> Bool {
        return getFile().getLastSyncDateForData() + CACHE_EXPIRATION < Date().timeIntervalSince1970 * 1000
    }
    
    func getParent() -> Document? {
        let parentId = getFile().getParentId()
        if parentId <= 0 {
            return nil
        }
        
        return Document(getStorageManager(), parentId)
    }
}
