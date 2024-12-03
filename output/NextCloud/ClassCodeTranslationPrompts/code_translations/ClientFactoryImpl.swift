
import Foundation

class ClientFactoryImpl: ClientFactory {
    private var context: Context

    init(context: Context) {
        self.context = context
    }

    override func create(user: User) throws -> OwnCloudClient {
        do {
            return try OwnCloudClientManagerFactory.getDefaultSingleton().getClientFor(user.toOwnCloudAccount(), context: context)
        } catch {
            throw CreationException(error)
        }
    }

    func createNextcloudClient(user: User) throws -> NextcloudClient {
        do {
            return try OwnCloudClientFactory.createNextcloudClient(user: user, context: context)
        } catch AccountUtils.AccountNotFoundException {
            throw CreationException(error)
        }
    }

    override func create(account: Account) throws -> OwnCloudClient {
        return try OwnCloudClientFactory.createOwnCloudClient(account: account, context: context)
    }

    func create(account: Account, currentActivity: Activity) throws -> OwnCloudClient {
        return try OwnCloudClientFactory.createOwnCloudClient(account: account, context: context, currentActivity: currentActivity)
    }

    func create(uri: URL, followRedirects: Bool, useNextcloudUserAgent: Bool) -> OwnCloudClient {
        return OwnCloudClientFactory.createOwnCloudClient(uri: uri, context: context, followRedirects: followRedirects)
    }

    func create(uri: URL, followRedirects: Bool) -> OwnCloudClient {
        return OwnCloudClientFactory.createOwnCloudClient(uri: uri, context: context, followRedirects: followRedirects)
    }

    func createPlainClient() -> PlainClient {
        return PlainClient(context: context)
    }
}
