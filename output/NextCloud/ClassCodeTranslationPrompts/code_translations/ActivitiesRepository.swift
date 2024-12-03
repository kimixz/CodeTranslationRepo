
import Foundation

protocol ActivitiesRepository {
    typealias LoadActivitiesCallback = (_ activities: [Any], _ client: NextcloudClient, _ lastGiven: Int) -> Void
    typealias LoadActivitiesErrorCallback = (_ error: String) -> Void

    func getActivities(lastGiven: Int, callback: @escaping LoadActivitiesCallback)
}

class NextcloudClient {
    // Implementation of NextcloudClient
}
