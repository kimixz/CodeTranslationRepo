
import Foundation

class GetSharesForFileOperation: SyncOperation {
    
    private static let TAG = String(describing: GetSharesForFileOperation.self)
    
    private let path: String
    private let reshares: Bool
    private let subfiles: Bool
    
    init(path: String, reshares: Bool, subfiles: Bool, storageManager: FileDataStorageManager) {
        self.path = path
        self.reshares = reshares
        self.subfiles = subfiles
        super.init(storageManager: storageManager)
    }
    
    override func run(client: OwnCloudClient) -> RemoteOperationResult {
        let operation = GetSharesForFileRemoteOperation(path: path, reshares: reshares, subfiles: subfiles)
        let result = operation.execute(client: client)
        
        if result.isSuccess {
            // Update DB with the response
            Log_OC.d(GetSharesForFileOperation.TAG, "File = \(path) Share list size  \(result.getData().count)")
            var shares = [OCShare]()
            for obj in result.getData() {
                if let share = obj as? OCShare {
                    shares.append(share)
                }
            }
            
            getStorageManager().saveSharesDB(shares: shares)
            
        } else if result.getCode() == .SHARE_NOT_FOUND {
            // no share on the file - remove local shares
            getStorageManager().removeSharesForFile(path: path)
        }
        
        return result
    }
}
