
import Foundation

class UpdateOCVersionOperation: RemoteOperation {
    
    private static let TAG = String(describing: UpdateOCVersionOperation.self)
    private static let STATUS_PATH = "/status.php"
    
    private let user: User
    private var mContext: Context
    private var mOwnCloudVersion: OwnCloudVersion?
    
    init(user: User, context: Context) {
        self.user = user
        self.mContext = context
        self.mOwnCloudVersion = nil
    }
    
    override func run(client: OwnCloudClient) -> RemoteOperationResult {
        let accountMngr = AccountManager.get(mContext)
        var statUrl = accountMngr.getUserData(user.toPlatformAccount(), Constants.KEY_OC_BASE_URL)
        statUrl += UpdateOCVersionOperation.STATUS_PATH
        var result: RemoteOperationResult? = nil
        var getMethod: GetMethod? = nil
        
        let webDav = client.getFilesDavUri().absoluteString
        
        do {
            getMethod = GetMethod(statUrl)
            let status = try client.executeMethod(getMethod!)
            if status != HttpStatus.SC_OK {
                result = RemoteOperationResult(false, getMethod)
                client.exhaustResponse(getMethod!.responseBodyAsStream())
            } else {
                if let response = getMethod?.responseBodyAsString() {
                    let json = try JSONSerialization.jsonObject(with: Data(response.utf8), options: []) as! [String: Any]
                    if let versionString = json["version"] as? String {
                        mOwnCloudVersion = OwnCloudVersion(versionString)
                        if mOwnCloudVersion!.isVersionValid() {
                            accountMngr.setUserData(user.toPlatformAccount(), Constants.KEY_OC_VERSION, mOwnCloudVersion!.getVersion())
                            Log_OC.d(UpdateOCVersionOperation.TAG, "Got new OC version \(mOwnCloudVersion!)")
                            result = RemoteOperationResult(ResultCode.OK)
                        } else {
                            Log_OC.w(UpdateOCVersionOperation.TAG, "Invalid version number received from server: \(versionString)")
                            result = RemoteOperationResult(RemoteOperationResult.ResultCode.BAD_OC_VERSION)
                        }
                    }
                }
                if result == nil {
                    result = RemoteOperationResult(RemoteOperationResult.ResultCode.INSTANCE_NOT_CONFIGURED)
                }
            }
            
            Log_OC.i(UpdateOCVersionOperation.TAG, "Check for update of Nextcloud server version at \(webDav): \(result!.getLogMessage())")
            
        } catch let e as NSError {
            result = RemoteOperationResult(RemoteOperationResult.ResultCode.INSTANCE_NOT_CONFIGURED)
            Log_OC.e(UpdateOCVersionOperation.TAG, "Check for update of Nextcloud server version at \(webDav): \(result!.getLogMessage())", e)
        } catch {
            result = RemoteOperationResult(error)
            Log_OC.e(UpdateOCVersionOperation.TAG, "Check for update of Nextcloud server version at \(webDav): \(result!.getLogMessage())", error)
        } finally {
            getMethod?.releaseConnection()
        }
        return result!
    }
    
    func getOCVersion() -> OwnCloudVersion? {
        return mOwnCloudVersion
    }
}
