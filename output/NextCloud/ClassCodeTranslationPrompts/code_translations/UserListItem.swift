
import Foundation

class UserListItem {
    static let TYPE_ACCOUNT = 0
    static let TYPE_ACTION_ADD = 1

    private var user: User?
    private var type: Int
    private var enabled: Bool

    init(user: User) {
        self.user = user
        self.type = UserListItem.TYPE_ACCOUNT
        self.enabled = true
    }

    init(user: User, enabled: Bool) {
        self.user = user
        self.type = UserListItem.TYPE_ACCOUNT
        self.enabled = enabled
    }

    init() {
        self.type = UserListItem.TYPE_ACTION_ADD
        self.enabled = false
    }

    func getUser() -> User? {
        return user
    }

    func getType() -> Int {
        return type
    }

    func setEnabled(_ bool: Bool) {
        enabled = bool
    }

    func isEnabled() -> Bool {
        return enabled
    }
}
