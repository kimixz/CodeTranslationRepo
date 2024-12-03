
import Foundation

class MoveFileOperation: SyncOperation {
    private let srcPath: String
    private var targetParentPath: String

    init(srcPath: String, targetParentPath: String, storageManager: FileDataStorageManager) {
        self.srcPath = srcPath
        self.targetParentPath = targetParentPath
        super.init(storageManager: storageManager)

        if !self.targetParentPath.hasSuffix(OCFile.PATH_SEPARATOR) {
            self.targetParentPath += OCFile.PATH_SEPARATOR
        }
    }

    override func run(client: OwnCloudClient) -> RemoteOperationResult {
        // 1. check move validity
        if targetParentPath.hasPrefix(srcPath) {
            return RemoteOperationResult(resultCode: .invalidMoveIntoDescendant)
        }
        guard let file = getStorageManager().getFileByPath(srcPath) else {
            return RemoteOperationResult(resultCode: .fileNotFound)
        }

        // 2. remote move
        var targetPath = targetParentPath + file.getFileName()
        if file.isFolder() {
            targetPath += OCFile.PATH_SEPARATOR
        }
        let result = MoveFileRemoteOperation(srcPath: srcPath, targetPath: targetPath, isFolder: false).execute(client: client)

        // 3. local move
        if result.isSuccess {
            getStorageManager().moveLocalFile(file: file, targetPath: targetPath, targetParentPath: targetParentPath)
        }
        // TODO handle ResultCode.PARTIAL_MOVE_DONE in client Activity, for the moment

        return result
    }
}
