
import Foundation

final class CapabilityUtils {
    private static var cachedCapabilities: [String: OCCapability] = [:]

    static func getCapability(context: Context?) -> OCCapability {
        var user: User? = nil
        if let context = context {
            // TODO: refactor when dark theme work is completed
            user = UserAccountManagerImpl.fromContext(context).getUser()
        }

        if let user = user {
            return getCapability(user: user, context: context)
        } else {
            return OCCapability()
        }
    }

    @available(*, deprecated)
    public static func getCapability(acc: Account?, context: Context?) -> OCCapability {
        var user: User? = nil

        if let acc = acc {
            user = UserAccountManagerImpl.fromContext(context).getUser(acc.name)
        } else if let context = context {
            // TODO: refactor when dark theme work is completed
            user = UserAccountManagerImpl.fromContext(context).getUser()
        }

        if let user = user {
            return getCapability(user: user, context: context)
        } else {
            return OCCapability()
        }
    }

    static func getCapability(user: User, context: Context) -> OCCapability {
        var capability = cachedCapabilities[user.accountName]

        if capability == nil {
            let storageManager = FileDataStorageManager(user: user, contentResolver: context.contentResolver)
            capability = storageManager.getCapability(accountName: user.accountName)

            if let capability = capability {
                cachedCapabilities[capability.accountName] = capability
            }
        }

        return capability
    }

    static func updateCapability(_ capability: OCCapability) {
        cachedCapabilities[capability.getAccountName()] = capability
    }

    static func checkOutdatedWarning(resources: Resources, version: OwnCloudVersion, hasExtendedSupport: Bool) -> Bool {
        return resources.getBoolean(R.bool.show_outdated_server_warning) &&
            (MainApp.OUTDATED_SERVER_VERSION.isSameMajorVersion(version) ||
                version.isOlderThan(MainApp.OUTDATED_SERVER_VERSION))
            && !hasExtendedSupport
    }
}
