
import Foundation

class CustomGlideStreamLoader: StreamModelLoader<String> {

    private let user: User
    private let clientFactory: ClientFactory

    init(user: User, clientFactory: ClientFactory) {
        self.user = user
        self.clientFactory = clientFactory
    }

    func getResourceFetcher(url: String, width: Int, height: Int) -> DataFetcher<InputStream> {
        return HttpStreamFetcher(user: user, clientFactory: clientFactory, url: url)
    }
}
