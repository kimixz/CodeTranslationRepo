
import Foundation

class ActivitiesServiceApiImpl: ActivitiesServiceApi {
    
    private static let TAG = String(describing: ActivitiesServiceApiImpl.self)
    private let accountManager: UserAccountManager
    
    init(accountManager: UserAccountManager) {
        self.accountManager = accountManager
    }
    
    func getAllActivities(lastGiven: Int, callback: @escaping (Result<[Any], Error>) -> Void) {
        let getActivityListTask = GetActivityListTask(user: accountManager.getUser(), lastGiven: lastGiven, callback: callback)
        getActivityListTask.execute()
    }
    
    private class GetActivityListTask: AsyncTask<Void, Void, Bool> {
        
        private let callback: (Result<[Any], Error>) -> Void
        private var activities: [Any] = []
        private let user: User
        private var lastGiven: Int
        private var errorMessage: String?
        private var client: NextcloudClient?
        
        init(user: User, lastGiven: Int, callback: @escaping (Result<[Any], Error>) -> Void) {
            self.user = user
            self.lastGiven = lastGiven
            self.callback = callback
        }
        
        override func doInBackground() -> Bool {
            let context = MainApp.getAppContext()
            do {
                let ocAccount = try user.toOwnCloudAccount()
                client = OwnCloudClientManagerFactory.getDefaultSingleton().getNextcloudClientFor(ocAccount, MainApp.getAppContext())
                
                let getRemoteActivitiesOperation: GetActivitiesRemoteOperation
                if lastGiven > 0 {
                    getRemoteActivitiesOperation = GetActivitiesRemoteOperation(lastGiven: lastGiven)
                } else {
                    getRemoteActivitiesOperation = GetActivitiesRemoteOperation()
                }
                
                let result = getRemoteActivitiesOperation.execute(client: client!)
                
                if result.isSuccess, let data = result.getData() as? [Any] {
                    activities = data[0] as? [Any] ?? []
                    lastGiven = data[1] as? Int ?? 0
                    return true
                } else {
                    Log_OC.d(ActivitiesServiceApiImpl.TAG, result.getLogMessage())
                    errorMessage = result.getLogMessage()
                    if result.getHttpCode() == HttpStatus.SC_NOT_MODIFIED {
                        errorMessage = context.getString(R.string.file_list_empty_headline_server_search)
                    }
                    return false
                }
            } catch let e as IOException {
                Log_OC.e(ActivitiesServiceApiImpl.TAG, "IO error", e)
                errorMessage = "IO error"
            } catch let e as OperationCanceledException {
                Log_OC.e(ActivitiesServiceApiImpl.TAG, "Operation has been canceled", e)
                errorMessage = "Operation has been canceled"
            } catch let e as AuthenticatorException {
                Log_OC.e(ActivitiesServiceApiImpl.TAG, "Authentication Exception", e)
                errorMessage = "Authentication Exception"
            } catch {
                return false
            }
            
            return false
        }
        
        override func onPostExecute(success: Bool) {
            super.onPostExecute(success: success)
            if success {
                callback(.success(activities))
            } else {
                callback(.failure(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: errorMessage ?? "Unknown error"])))
            }
        }
    }
}
