
import Foundation

class RemoveFileOperation: SyncOperation {
    
    private let fileToRemove: OCFile
    private let onlyLocalCopy: Bool
    private let user: User
    private let inBackground: Bool
    private let context: Context
    
    init(fileToRemove: OCFile, onlyLocalCopy: Bool, user: User, inBackground: Bool, context: Context, storageManager: FileDataStorageManager) {
        self.fileToRemove = fileToRemove
        self.onlyLocalCopy = onlyLocalCopy
        self.user = user
        self.inBackground = inBackground
        self.context = context
        super.init(storageManager: storageManager)
    }
    
    func getFile() -> OCFile? {
        return fileToRemove
    }
    
    func isInBackground() -> Bool {
        return inBackground
    }
    
    override func run(client: OwnCloudClient) -> RemoteOperationResult {
        var result: RemoteOperationResult? = nil
        var operation: RemoteOperation
        
        if MimeTypeUtil.isImage(fileToRemove.mimeType) {
            // store resized image
            ThumbnailsCacheManager.generateResizedImage(fileToRemove)
        }
        
        var localRemovalFailed = false
        if !onlyLocalCopy {
            if fileToRemove.isEncrypted {
                guard let parent = getStorageManager().getFileById(fileToRemove.parentId) else {
                    return RemoteOperationResult(resultCode: .localFileNotFound)
                }
                
                operation = RemoveRemoteEncryptedFileOperation(remotePath: fileToRemove.remotePath,
                                                               user: user,
                                                               context: context,
                                                               encryptedFileName: fileToRemove.encryptedFileName,
                                                               parent: parent,
                                                               isFolder: fileToRemove.isFolder)
            } else {
                operation = RemoveFileRemoteOperation(remotePath: fileToRemove.remotePath)
            }
            result = operation.execute(client: client)
            if result?.isSuccess() == true || result?.code == .fileNotFound {
                localRemovalFailed = !getStorageManager().removeFile(fileToRemove, removeLocal: true, removeRemote: true)
            }
        } else {
            localRemovalFailed = !getStorageManager().removeFile(fileToRemove, removeLocal: false, removeRemote: true)
            if !localRemovalFailed {
                result = RemoteOperationResult(resultCode: .ok)
            }
        }
        
        if localRemovalFailed {
            result = RemoteOperationResult(resultCode: .localStorageNotRemoved)
        }
        
        return result!
    }
}
