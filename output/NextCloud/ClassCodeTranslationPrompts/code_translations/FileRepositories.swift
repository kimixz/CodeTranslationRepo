
final class FileRepositories {

    private init() {
        // No instance
    }

    static func getRepository(filesServiceApi: FilesServiceApi) -> FilesRepository {
        return RemoteFilesRepository(filesServiceApi: filesServiceApi)
    }
}
