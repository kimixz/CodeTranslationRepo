
import Foundation

class RichDocumentsCreateAssetOperation: RemoteOperation {
    private static let TAG = String(describing: RichDocumentsCreateAssetOperation.self)
    private static let SYNC_READ_TIMEOUT = 40000
    private static let SYNC_CONNECTION_TIMEOUT = 5000
    private static let ASSET_URL = "/index.php/apps/richdocuments/assets"
    
    private static let NODE_URL = "url"
    private static let PARAMETER_PATH = "path"
    private static let PARAMETER_FORMAT = "format"
    private static let PARAMETER_FORMAT_VALUE = "json"
    
    private var path: String
    
    init(path: String) {
        self.path = path
    }
    
    func run(client: OwnCloudClient) -> RemoteOperationResult {
        var result: RemoteOperationResult
        var postMethod: Utf8PostMethod? = nil
        
        do {
            postMethod = Utf8PostMethod(url: client.baseUri + RichDocumentsCreateAssetOperation.ASSET_URL)
            postMethod?.setParameter(RichDocumentsCreateAssetOperation.PARAMETER_PATH, path)
            postMethod?.setParameter(RichDocumentsCreateAssetOperation.PARAMETER_FORMAT, RichDocumentsCreateAssetOperation.PARAMETER_FORMAT_VALUE)
            
            // remote request
            postMethod?.addRequestHeader(OCS_API_HEADER, OCS_API_HEADER_VALUE)
            
            let status = try client.executeMethod(postMethod!, readTimeout: RichDocumentsCreateAssetOperation.SYNC_READ_TIMEOUT, connectionTimeout: RichDocumentsCreateAssetOperation.SYNC_CONNECTION_TIMEOUT)
            
            if status == HttpStatus.SC_OK {
                if let response = postMethod?.getResponseBodyAsString() {
                    // Parse the response
                    let respJSON = try JSONSerialization.jsonObject(with: Data(response.utf8), options: []) as! [String: Any]
                    let url = respJSON[RichDocumentsCreateAssetOperation.NODE_URL] as! String
                    
                    result = RemoteOperationResult(success: true, method: postMethod)
                    result.setSingleData(url)
                } else {
                    result = RemoteOperationResult(success: false, method: postMethod)
                }
            } else {
                result = RemoteOperationResult(success: false, method: postMethod)
                client.exhaustResponse(postMethod?.getResponseBodyAsStream())
            }
        } catch {
            result = RemoteOperationResult(error: error)
            Log_OC.e(RichDocumentsCreateAssetOperation.TAG, "Create asset for richdocuments with path \(path) failed: \(result.getLogMessage())", result.getException())
        } finally {
            postMethod?.releaseConnection()
        }
        return result
    }
}
