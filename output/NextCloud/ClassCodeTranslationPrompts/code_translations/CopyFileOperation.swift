
import Foundation

class CopyFileOperation: SyncOperation {
    private let srcPath: String
    private var targetParentPath: String

    init(srcPath: String, targetParentPath: String, storageManager: FileDataStorageManager) {
        self.srcPath = srcPath
        self.targetParentPath = targetParentPath
        super.init(storageManager: storageManager)

        if !self.targetParentPath.hasSuffix(OCFile.pathSeparator) {
            self.targetParentPath += OCFile.pathSeparator
        }
    }

    override func run(client: OwnCloudClient) -> RemoteOperationResult {
        // 1. check copy validity
        if targetParentPath.hasPrefix(srcPath) {
            return RemoteOperationResult(resultCode: .invalidCopyIntoDescendant)
        }
        guard let file = getStorageManager().getFileByPath(srcPath) else {
            return RemoteOperationResult(resultCode: .fileNotFound)
        }

        // 2. remote copy
        var targetPath = targetParentPath + file.getFileName()
        if file.isFolder() {
            targetPath += OCFile.pathSeparator
        }
        
        // auto rename, to allow copy
        if targetPath == srcPath {
            if file.isFolder() {
                targetPath = targetParentPath + file.getFileName()
            }
            targetPath = UploadFileOperation.getNewAvailableRemotePath(client: client, path: targetPath, null: nil, autoRename: false)

            if file.isFolder() {
                targetPath += OCFile.pathSeparator
            }
        }
        
        let result = CopyFileRemoteOperation(srcPath: srcPath, targetPath: targetPath, autoRename: false).execute(client: client)

        // 3. local copy
        if result.isSuccess {
            getStorageManager().copyLocalFile(file: file, targetPath: targetPath)
        }
        // TODO handle ResultCode.PARTIAL_COPY_DONE in client Activity, for the moment

        return result
    }
}
