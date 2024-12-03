
import Foundation

class RemoteActivitiesRepository: ActivitiesRepository {

    private let activitiesServiceApi: ActivitiesServiceApi

    init(activitiesServiceApi: ActivitiesServiceApi) {
        self.activitiesServiceApi = activitiesServiceApi
    }

    func getActivities(lastGiven: Int, callback: @escaping LoadActivitiesCallback) {
        activitiesServiceApi.getAllActivities(lastGiven: lastGiven) { (result: Result<([Any], NextcloudClient, Int), String>) in
            switch result {
            case .success(let (activities, client, lastGiven)):
                callback.onActivitiesLoaded(activities: activities, client: client, lastGiven: lastGiven)
            case .failure(let error):
                callback.onActivitiesLoadedError(error: error)
            }
        }
    }
}
