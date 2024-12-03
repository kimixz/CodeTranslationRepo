
import Foundation

class CreateShareViaLinkOperation: SyncOperation {
    private var path: String
    private var password: String?
    private var permissions: Int = OCShare.NO_PERMISSION

    init(path: String, password: String?, storageManager: FileDataStorageManager) {
        self.path = path
        self.password = password
        super.init(storageManager: storageManager)
    }

    init(path: String, storageManager: FileDataStorageManager, permissions: Int) {
        self.path = path
        self.permissions = permissions
        super.init(storageManager: storageManager)
    }

    override func run(client: OwnCloudClient) -> RemoteOperationResult {
        let createOp = CreateShareRemoteOperation(path: path, shareType: .publicLink, password: "", isPublic: false, password: password, permissions: permissions)
        createOp.setGetShareDetails(true)
        var result = createOp.execute(client: client)

        if result.isSuccess() {
            if result.getData().count > 0 {
                if let item = result.getData().first as? OCShare {
                    updateData(share: item)
                } else {
                    let data = result.getData()
                    result = RemoteOperationResult(resultCode: .shareNotFound)
                    result.setData(data)
                }
            } else {
                result = RemoteOperationResult(resultCode: .shareNotFound)
            }
        }

        return result
    }

    private func updateData(share: OCShare) {
        share.setPath(path)
        if path.hasSuffix(FileUtils.PATH_SEPARATOR) {
            share.setFolder(true)
        } else {
            share.setFolder(false)
        }

        getStorageManager().saveShare(share)

        if let file = getStorageManager().getFileByEncryptedRemotePath(path) {
            file.setSharedViaLink(true)
            getStorageManager().saveFile(file)
        }
    }

    func getPath() -> String {
        return self.path
    }

    func getPassword() -> String? {
        return self.password
    }
}
