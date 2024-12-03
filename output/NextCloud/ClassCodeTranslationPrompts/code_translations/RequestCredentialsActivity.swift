
import UIKit
import LocalAuthentication

class RequestCredentialsActivity: UIViewController {

    private static let TAG = String(describing: RequestCredentialsActivity.self)

    public static let KEY_CHECK_RESULT = "KEY_CHECK_RESULT"
    public static let KEY_CHECK_RESULT_TRUE = 1
    public static let KEY_CHECK_RESULT_FALSE = 0
    public static let KEY_CHECK_RESULT_CANCEL = -1
    private static let REQUEST_CODE_CONFIRM_DEVICE_CREDENTIALS = 1

    override func viewDidLoad() {
        super.viewDidLoad()
        PassCodeManager.setSecureFlag(self, true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(handleActivityResult(_:)), name: .activityResult, object: nil)
    }

    @objc func handleActivityResult(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let requestCode = userInfo["requestCode"] as? Int,
              let resultCode = userInfo["resultCode"] as? Int else { return }

        if requestCode == RequestCredentialsActivity.REQUEST_CODE_CONFIRM_DEVICE_CREDENTIALS {
            if resultCode == Activity.RESULT_OK {
                AppPreferencesImpl.fromContext(self).setLockTimestamp(ProcessInfo.processInfo.systemUptime)
                finishWithResult(RequestCredentialsActivity.KEY_CHECK_RESULT_TRUE)
            } else if resultCode == Activity.RESULT_CANCELED {
                finishWithResult(RequestCredentialsActivity.KEY_CHECK_RESULT_CANCEL)
            } else {
                let alert = UIAlertController(title: nil, message: NSLocalizedString("default_credentials_wrong", comment: ""), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.present(alert, animated: true, completion: nil)
                requestCredentials()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if DeviceCredentialUtils.areCredentialsAvailable(self) {
            requestCredentials()
        } else {
            DisplayUtils.showSnackMessage(self, message: NSLocalizedString("prefs_lock_device_credentials_not_setup", comment: ""))
            finishWithResult(RequestCredentialsActivity.KEY_CHECK_RESULT_CANCEL)
        }
    }

    private func requestCredentials() {
        let context = LAContext()
        let reason = "Authenticate to proceed"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            if success {
                // Handle successful authentication
            } else {
                // Handle failed authentication
                print("Keyguard manager is null")
                self.finishWithResult(RequestCredentialsActivity.KEY_CHECK_RESULT_FALSE)
            }
        }
    }

    private func finishWithResult(_ success: Int) {
        // Implementation for finishing with result
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        PassCodeManager.setSecureFlag(self, false)
    }
}
