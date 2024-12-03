
import Foundation
import UserNotifications

public final class NotificationUtils {
    
    public static let NOTIFICATION_CHANNEL_GENERAL = "NOTIFICATION_CHANNEL_GENERAL"
    public static let NOTIFICATION_CHANNEL_DOWNLOAD = "NOTIFICATION_CHANNEL_DOWNLOAD"
    public static let NOTIFICATION_CHANNEL_UPLOAD = "NOTIFICATION_CHANNEL_UPLOAD"
    public static let NOTIFICATION_CHANNEL_MEDIA = "NOTIFICATION_CHANNEL_MEDIA"
    public static let NOTIFICATION_CHANNEL_FILE_SYNC = "NOTIFICATION_CHANNEL_FILE_SYNC"
    public static let NOTIFICATION_CHANNEL_FILE_OBSERVER = "NOTIFICATION_CHANNEL_FILE_OBSERVER"
    public static let NOTIFICATION_CHANNEL_PUSH = "NOTIFICATION_CHANNEL_PUSH"
    public static let NOTIFICATION_CHANNEL_BACKGROUND_OPERATIONS = "NOTIFICATION_CHANNEL_BACKGROUND_OPERATIONS"
    
    private init() {
        // utility class -> private constructor
    }
    
    static func newNotificationBuilder(context: UNUserNotificationCenter, channelId: String, viewThemeUtils: ViewThemeUtils) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        viewThemeUtils.themeNotificationContent(context: context, content: content)
        return content
    }
    
    static func cancelWithDelay(notificationCenter: UNUserNotificationCenter, notificationId: String, delayInMillis: TimeInterval) {
        let queue = DispatchQueue(label: "NotificationDelayerQueue_\(Int.random(in: Int.min...Int.max))", qos: .background)
        queue.asyncAfter(deadline: .now() + delayInMillis / 1000) {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationId])
        }
    }
    
    static func createUploadNotificationTag(file: OCFile) -> String {
        return createUploadNotificationTag(remotePath: file.getRemotePath(), localPath: file.getStoragePath())
    }
    
    static func createUploadNotificationTag(remotePath: String, localPath: String) -> String {
        return remotePath + localPath
    }
}
