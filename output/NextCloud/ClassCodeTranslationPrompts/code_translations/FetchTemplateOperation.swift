
import Foundation

class FetchTemplateOperation: RemoteOperation {
    private static let TAG = String(describing: FetchTemplateOperation.self)
    private static let SYNC_READ_TIMEOUT = 40000
    private static let SYNC_CONNECTION_TIMEOUT = 5000
    private static let TEMPLATE_URL = "/ocs/v2.php/apps/richdocuments/api/v1/templates/"
    
    private var type: ChooseRichDocumentsTemplateDialogFragment.Type
    
    // JSON node names
    private static let NODE_OCS = "ocs"
    private static let NODE_DATA = "data"
    private static let JSON_FORMAT = "?format=json"
    
    init(type: ChooseRichDocumentsTemplateDialogFragment.Type) {
        self.type = type
    }
    
    protected func run(client: OwnCloudClient) -> RemoteOperationResult {
        var result: RemoteOperationResult
        var getMethod: GetMethod? = nil
        
        do {
            getMethod = GetMethod(client.getBaseUri() + FetchTemplateOperation.TEMPLATE_URL + type.toString().lowercased(with: Locale(identifier: "en")) + FetchTemplateOperation.JSON_FORMAT)
            
            // remote request
            getMethod?.addRequestHeader(OCS_API_HEADER, OCS_API_HEADER_VALUE)
            
            let status = client.executeMethod(getMethod, FetchTemplateOperation.SYNC_READ_TIMEOUT, FetchTemplateOperation.SYNC_CONNECTION_TIMEOUT)
            
            if status == HttpStatus.SC_OK {
                let response = getMethod?.getResponseBodyAsString() ?? ""
                
                // Parse the response
                let respJSON = try JSONSerialization.jsonObject(with: Data(response.utf8), options: []) as! [String: Any]
                let templates = (respJSON[FetchTemplateOperation.NODE_OCS] as! [String: Any])[FetchTemplateOperation.NODE_DATA] as! [[String: Any]]
                
                var templateArray: [Any] = []
                
                for templateObject in templates {
                    let template = Template(
                        id: templateObject["id"] as! Int64,
                        name: templateObject["name"] as! String,
                        preview: templateObject["preview"] as? String,
                        type: Template.Type.parse((templateObject["type"] as! String).uppercased(with: Locale(identifier: "en"))),
                        extension: templateObject["extension"] as! String
                    )
                    templateArray.append(template)
                }
                
                result = RemoteOperationResult(success: true, method: getMethod)
                result.setData(templateArray)
            } else {
                result = RemoteOperationResult(success: false, method: getMethod)
                client.exhaustResponse(getMethod?.getResponseBodyAsStream())
            }
        } catch {
            result = RemoteOperationResult(error)
            Log_OC.e(FetchTemplateOperation.TAG, "Get templates for type \(type) failed: \(result.getLogMessage())", result.getException())
        } finally {
            getMethod?.releaseConnection()
        }
        return result
    }
}
