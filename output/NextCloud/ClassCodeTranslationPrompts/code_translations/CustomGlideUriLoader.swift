
import Foundation

class CustomGlideUriLoader: StreamModelLoader<URL> {
    private let user: User
    private let clientFactory: ClientFactory

    init(user: User, clientFactory: ClientFactory) {
        self.user = user
        self.clientFactory = clientFactory
    }

    func getResourceFetcher(url: URL, width: Int, height: Int) -> DataFetcher<InputStream> {
        return HttpStreamFetcher(user: user, clientFactory: clientFactory, url: url.absoluteString)
    }
}
