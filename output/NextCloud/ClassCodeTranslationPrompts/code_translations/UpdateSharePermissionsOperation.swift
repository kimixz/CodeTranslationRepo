
import Foundation

class UpdateSharePermissionsOperation: SyncOperation {
    private let shareId: Int64
    private var permissions: Int
    private var expirationDateInMillis: Int64
    private var password: String?
    private var path: String?

    init(shareId: Int64, storageManager: FileDataStorageManager) {
        self.shareId = shareId
        self.permissions = -1
        self.expirationDateInMillis = 0
        self.password = nil
        super.init(storageManager: storageManager)
    }

    override func run(client: OwnCloudClient) -> RemoteOperationResult {
        guard var share = getStorageManager().getShareById(shareId) else {
            return RemoteOperationResult(resultCode: .shareNotFound)
        }

        path = share.getPath()

        let updateOp = UpdateShareRemoteOperation(remoteId: share.getRemoteId())
        updateOp.setPassword(password)
        updateOp.setPermissions(permissions)
        updateOp.setExpirationDate(expirationDateInMillis)
        var result = updateOp.execute(client: client)

        if result.isSuccess() {
            let getShareOp = GetShareRemoteOperation(remoteId: share.getRemoteId())
            result = getShareOp.execute(client: client)
            if result.isSuccess() {
                if let updatedShare = result.getData().first as? OCShare {
                    share = updatedShare
                    updateData(share: share)
                }
            }
        }

        return result
    }

    private func updateData(share: OCShare) {
        share.setPath(path)
        share.setFolder(path?.hasSuffix(FileUtils.PATH_SEPARATOR) ?? false)
        share.setPasswordProtected(!(password?.isEmpty ?? true))
        getStorageManager().saveShare(share)
    }

    func getPassword() -> String? {
        return self.password
    }

    func getPath() -> String? {
        return self.path
    }

    func setPermissions(_ permissions: Int) {
        self.permissions = permissions
    }

    func setExpirationDateInMillis(_ expirationDateInMillis: Int64) {
        self.expirationDateInMillis = expirationDateInMillis
    }

    func setPassword(_ password: String?) {
        self.password = password
    }
}
