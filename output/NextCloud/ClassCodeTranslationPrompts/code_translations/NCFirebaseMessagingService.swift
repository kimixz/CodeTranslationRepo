
import UIKit
import FirebaseMessaging

class NCFirebaseMessagingService: MessagingDelegate {
    var preferences: AppPreferences!
    var accountManager: UserAccountManager!
    var backgroundJobManager: BackgroundJobManager!

    static let TAG = "NCFirebaseMessagingService"
    static let ENABLE_NOTIFICATION_OLD = MessageNotificationKeys.NOTIFICATION_PREFIX_OLD + "e"
    static let ENABLE_NOTIFICATION_NEW = MessageNotificationKeys.ENABLE_NOTIFICATION

    override func onCreate() {
        super.onCreate()
        AndroidInjection.inject(self)
    }

    override func handleIntent(_ intent: Intent) {
        Log_OC.d(TAG, "handleIntent - extras: " +
            "\(ENABLE_NOTIFICATION_NEW): \(intent.extras?.getString(ENABLE_NOTIFICATION_NEW) ?? ""), " +
            "\(ENABLE_NOTIFICATION_OLD): \(intent.extras?.getString(ENABLE_NOTIFICATION_OLD) ?? "")")

        intent.removeExtra(ENABLE_NOTIFICATION_OLD)
        intent.removeExtra(ENABLE_NOTIFICATION_NEW)
        intent.putExtra(ENABLE_NOTIFICATION_NEW, "0")

        super.handleIntent(intent)
    }

    override func didReceive(_ remoteMessage: MessagingRemoteMessage) {
        print("onMessageReceived")
        let data = remoteMessage.appData
        if let subject = data[NotificationWork.KEY_NOTIFICATION_SUBJECT] as? String,
           let signature = data[NotificationWork.KEY_NOTIFICATION_SIGNATURE] as? String {
            backgroundJobManager.startNotificationJob(subject: subject, signature: signature)
        }
    }

    override func didReceiveRegistrationToken(_ fcmToken: String) {
        print("onNewToken")
        super.didReceiveRegistrationToken(fcmToken)

        if !getResources().getString(R.string.push_server_url).isEmpty {
            preferences.setPushToken(fcmToken)
            PushUtils.pushRegistrationToServer(accountManager, preferences.getPushToken())
        }
    }
}
