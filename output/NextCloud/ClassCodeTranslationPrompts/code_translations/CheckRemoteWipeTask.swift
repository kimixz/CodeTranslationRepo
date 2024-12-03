
import Foundation

class CheckRemoteWipeTask: Operation {
    private var backgroundJobManager: BackgroundJobManager
    private var account: Account
    private weak var fileActivityWeakReference: FileActivity?

    init(backgroundJobManager: BackgroundJobManager, account: Account, fileActivityWeakReference: FileActivity) {
        self.backgroundJobManager = backgroundJobManager
        self.account = account
        self.fileActivityWeakReference = fileActivityWeakReference
    }

    override func main() {
        guard let fileActivity = fileActivityWeakReference else {
            Log_OC.e(self, "Check for remote wipe: no context available")
            return
        }

        let checkWipeResult = CheckRemoteWipeRemoteOperation().execute(account, fileActivity)

        if checkWipeResult.isSuccess() {
            backgroundJobManager.startAccountRemovalJob(account.name, true)
        } else {
            Log_OC.e(self, "Check for remote wipe not needed -> update credentials")
            fileActivity.performCredentialsUpdate(account, fileActivity)
        }
    }
}
