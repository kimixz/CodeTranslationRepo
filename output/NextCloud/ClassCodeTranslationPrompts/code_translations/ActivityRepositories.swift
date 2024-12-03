
final class ActivityRepositories {

    private init() {
        // No instance
    }

    static func getRepository(activitiesServiceApi: ActivitiesServiceApi) -> ActivitiesRepository {
        return RemoteActivitiesRepository(activitiesServiceApi: activitiesServiceApi)
    }
}
