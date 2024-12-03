
import Foundation

protocol CurrentAccountProvider {
    @available(*, deprecated)
    func getCurrentAccount() -> Account

    func getUser() -> User
}

extension CurrentAccountProvider {
    func getUser() -> User {
        return AnonymousUser(name: "dummy")
    }
}
