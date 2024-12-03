
import Foundation

protocol ActivitiesServiceApi {
    
    associatedtype T
    
    func onLoaded(_ activities: T, client: NextcloudClient, lastGiven: Int)
    func onError(_ error: String)
    func getAllActivities(lastGiven: Int, callback: @escaping (Result<[Any], Error>) -> Void)
}

class NextcloudClient {
    // Implementation of NextcloudClient
}

class Activity {
    // Implementation of Activity
}
