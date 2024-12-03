
import Foundation

protocol ActivitiesActivity {}
protocol AuthenticatorActivity {}
protocol BaseActivity {}
protocol ConflictsResolveActivityProvider {
    func provideConflictsResolveActivity() -> ConflictsResolveActivity
}
class ConflictsResolveActivity: ConflictsResolveActivityProvider {
    func provideConflictsResolveActivity() -> ConflictsResolveActivity {
        return ConflictsResolveActivity()
    }
}
protocol ContactsPreferenceActivity {}
protocol CopyToClipboardActivity {}
protocol DeepLinkLoginActivity {}
protocol DrawerActivity {}
protocol ErrorsWhileCopyingHandlerActivity {}
protocol ExternalSiteWebView {}
protocol FileDisplayActivityProvider {
    func fileDisplayActivity() -> FileDisplayActivity
}
class FileDisplayActivity: FileDisplayActivityProvider {
    func fileDisplayActivity() -> FileDisplayActivity {
        return self
    }
}
protocol FilePickerActivity {}
protocol FirstRunActivity {}
protocol FolderPickerActivity {}
protocol LogsActivity {}
protocol ManageAccountsActivity {}
protocol ManageSpaceActivity {}
protocol NotificationsActivity {}
protocol CommunityActivity {}
protocol ComposeActivityProvider {
    func composeActivity() -> ComposeActivity
}
protocol PassCodeActivityProvider {
    func passCodeActivity() -> PassCodeActivity
}
class PassCodeActivity: NSObject {}
protocol PreviewImageActivity {}
protocol PreviewMediaActivityProvider {
    func previewMediaActivity() -> PreviewMediaActivity
}
class PreviewMediaActivity: NSObject {}
protocol ReceiveExternalFilesActivity {}
protocol RequestCredentialsActivity {}
protocol SettingsActivityProvider {
    func settingsActivity() -> SettingsActivity
}
class SettingsActivity {}
protocol ShareActivity {}
protocol SsoGrantPermissionActivity {}
protocol SyncedFoldersActivity {}
protocol TrashbinActivity {}
protocol UploadFilesActivity {}
protocol UploadListActivity {}
protocol UserInfoActivity {}
protocol WhatsNewActivityProvider {
    func provideWhatsNewActivity() -> WhatsNewActivity
}
class WhatsNewActivity {}
protocol EtmActivity {}
protocol RichDocumentsEditorWebView {}
protocol TextEditorWebView {}
protocol ExtendedListFragment {}
protocol FileDetailFragment {}
protocol LocalFileListFragmentProvider {
    func localFileListFragment() -> LocalFileListFragment
}
class LocalFileListFragment: NSObject {}
protocol OCFileListFragment {}
protocol FileDetailActivitiesFragment {}
protocol FileDetailsSharingProcessFragment {}
protocol FileDetailSharingFragment {}
protocol ChooseTemplateDialogFragmentProvider {
    func provideChooseTemplateDialogFragment() -> ChooseTemplateDialogFragment
}
protocol AccountRemovalDialog {}
protocol ChooseRichDocumentsTemplateDialogFragment {}
protocol ContactsBackupFragmentProvider {
    func contactsBackupFragment() -> BackupFragment
}
class BackupFragment {}
protocol PreviewImageFragment {}
protocol BackupListFragment {}
protocol PreviewMediaFragment {}
protocol PreviewTextFragment {}
protocol ChooseAccountDialogFragment {}
protocol SetStatusDialogFragment {}
protocol PreviewTextFileFragment {}
protocol PreviewTextStringFragment {}
protocol UnifiedSearchFragment {}
protocol GalleryFragment {}
protocol MultipleAccountsDialog {}
protocol DialogInputUploadFilename {}
@MainActor
protocol ReceiveExternalFilesActivity {
    associatedtype DialogInputUploadFilenameType: DialogInputUploadFilename
    func dialogInputUploadFilename() -> DialogInputUploadFilenameType
}
protocol BootupBroadcastReceiver {}
protocol NetworkChangeReceiver {}
protocol NotificationWorkBroadcastReceiverProvider {
    func notificationWorkBroadcastReceiver() -> NotificationWork.NotificationReceiver
}
protocol FileContentProvider {}
class FileContentProviderImpl: FileContentProvider {}
protocol UsersAndGroupsSearchProvider {}
protocol DiskLruImageCacheFileProvider {}
protocol DocumentsStorageProvider {}
protocol AccountManagerService {}
protocol OperationsService {}
protocol PlayerService {}
protocol FileTransferService {}
protocol FileSyncService {}
protocol DashboardWidgetService {}
protocol PreviewPdfFragment {}
protocol SharedListFragment {}
protocol FeatureFragment {}
protocol IndeterminateProgressDialog {}
protocol SortingOrderDialogFragment {}
protocol ConfirmationDialogFragment {}
protocol ConflictsResolveDialog {}
protocol CreateFolderDialogFragment {}
protocol ExpirationDatePickerDialogFragment {}
protocol FileActivity {}
protocol FileDownloadFragment {}
protocol LoadingDialog {}
protocol LocalStoragePathPickerDialogFragment {}
protocol LogsViewModel {}
protocol MainApp {}
protocol Migrations {}
protocol NotificationWork {}
protocol RemoveFilesDialogFragment {}
protocol RenamePublicShareDialogFragment {}
protocol SendShareDialog {}
protocol SetupEncryptionDialogFragment {}
protocol ChooseStorageLocationDialogFragment {}
protocol SharePasswordDialogFragment {}
protocol SyncedFolderPreferencesDialogFragment {}
protocol ToolbarActivity {}
protocol StoragePermissionDialogFragment {}
@objc protocol OCFileListBottomSheetDialog {}
@objc class ComponentsModule: NSObject {
    @objc func ocfileListBottomSheetDialog() -> OCFileListBottomSheetDialog {
        fatalError("This method should be overridden")
    }
}
protocol RenameFileDialogFragmentProvider {
    func renameFileDialogFragment() -> RenameFileDialogFragment
}
protocol SyncFileNotEnoughSpaceDialogFragment {}
protocol DashboardWidgetConfigurationActivity {}
protocol DashboardWidgetProvider {}
protocol GalleryFragmentBottomSheetDialog {}
protocol PreviewBitmapActivityProvider {
    func previewBitmapActivity() -> PreviewBitmapActivity
}
class PreviewBitmapActivity {}
protocol FileUploadHelper {}
protocol SslUntrustedCertDialog {}
protocol FileActionsBottomSheet {}
protocol SendFilesDialog {}
protocol DocumentScanActivityProvider {
    func documentScanActivity() -> DocumentScanActivity
}
class DocumentScanActivity {}
protocol GroupfolderListFragment {}
protocol LauncherActivity {}
protocol EditImageActivity {}
protocol ImageDetailFragment {}
protocol EtmBackgroundJobsFragment {}
protocol BackgroundJobManagerImpl {}
protocol TestJob {}
protocol InternalTwoWaySyncActivity {}
@available(*, deprecated)
protocol BackgroundPlayerService {}
