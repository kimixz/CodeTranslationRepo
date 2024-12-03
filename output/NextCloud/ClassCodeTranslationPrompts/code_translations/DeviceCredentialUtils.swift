
import UIKit

final class DeviceCredentialUtils {

    private init() {
        // utility class -> private constructor
    }

    static func areCredentialsAvailable() -> Bool {
        if let keyguardManager = UIApplication.shared.delegate?.window??.windowScene?.keyWindow?.windowScene?.keyguardManager {
            return keyguardManager.isKeyguardSecure
        } else {
            print("Keyguard manager is null")
            return false
        }
    }
}
