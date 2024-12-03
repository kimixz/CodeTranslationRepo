
import Foundation

class DetectAuthenticationMethodOperation: RemoteOperation {
    
    private static let TAG = String(describing: DetectAuthenticationMethodOperation.self)
    
    enum AuthenticationMethod {
        case unknown
        case none
        case basicHttpAuth
        case samlWebSSO
        case bearerToken
    }
    
    private var mContext: Context
    
    init(context: Context) {
        self.mContext = context
    }
    
    override func run(client: OwnCloudClient) -> RemoteOperationResult {
        var result: RemoteOperationResult? = nil
        var authMethod: AuthenticationMethod = .unknown
        
        let operation = ExistenceCheckRemoteOperation("", mContext, false)
        client.clearCredentials()
        client.setFollowRedirects(false)
        
        // try to access the root folder, following redirections but not SAML SSO redirections
        result = operation.execute(client)
        var redirectedLocation = result?.getRedirectedLocation()
        while !(redirectedLocation?.isEmpty ?? true) && !(result?.isIdPRedirection() ?? false) {
            client.setBaseUri(Uri.parse(result?.getRedirectedLocation() ?? ""))
            result = operation.execute(client)
            redirectedLocation = result?.getRedirectedLocation()
        }
        
        // analyze response
        if result?.getHttpCode() == HttpStatus.SC_UNAUTHORIZED || result?.getHttpCode() == HttpStatus.SC_FORBIDDEN {
            let authHeaders = result?.getAuthenticateHeaders() ?? []
            
            for header in authHeaders {
                // currently we only support basic auth
                if header.lowercased().contains("basic") {
                    authMethod = .basicHttpAuth
                    break
                }
            }
            // else - fall back to UNKNOWN
            
        } else if result?.isSuccess() ?? false {
            authMethod = .none
            
        } else if result?.isIdPRedirection() ?? false {
            authMethod = .samlWebSSO
        }
        // else - fall back to UNKNOWN
        Log_OC.d(DetectAuthenticationMethodOperation.TAG, "Authentication method found: \(authenticationMethodToString(authMethod))")
        
        if authMethod != .unknown {
            result = RemoteOperationResult(true, result?.getHttpCode() ?? 0, result?.getHttpPhrase() ?? "", [])
        }
        var data: [Any] = []
        data.append(authMethod)
        result?.setData(data)
        return result!
    }
    
    private func authenticationMethodToString(_ value: AuthenticationMethod) -> String {
        switch value {
        case .none:
            return "NONE"
        case .basicHttpAuth:
            return "BASIC_HTTP_AUTH"
        case .bearerToken:
            return "BEARER_TOKEN"
        case .samlWebSSO:
            return "SAML_WEB_SSO"
        default:
            return "UNKNOWN"
        }
    }
}
