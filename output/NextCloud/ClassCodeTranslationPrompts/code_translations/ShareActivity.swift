
import UIKit

class ShareActivity: FileActivity {
    private static let TAG = String(describing: ShareActivity.self)
    static let TAG_SHARE_FRAGMENT = "SHARE_FRAGMENT"

    @Inject
    var syncedFolderProvider: SyncedFolderProvider!

    override func viewDidLoad() {
        super.viewDidLoad()

        let binding = ShareActivityBinding.inflate(getLayoutInflater())
        setContentView(binding.root)

        guard let file = getFile(), let user = getUser() else {
            finish()
            return
        }

        // Icon
        if file.isFolder() {
            let isAutoUploadFolder = SyncedFolderProvider.isAutoUploadFolder(syncedFolderProvider, file, user)

            let overlayIconId = file.getFileOverlayIconId(isAutoUploadFolder)
            let drawable = MimeTypeUtil.getFolderIcon(preferences.isDarkModeEnabled(), overlayIconId, self, viewThemeUtils)
            binding.shareFileIcon.setImageDrawable(drawable)
        } else {
            binding.shareFileIcon.setImageDrawable(MimeTypeUtil.getFileTypeIcon(file.getMimeType(), file.getFileName(), self, viewThemeUtils))
            if MimeTypeUtil.isImage(file) {
                let remoteId = String(file.getRemoteId())
                if let thumbnail = ThumbnailsCacheManager.getBitmapFromDiskCache(remoteId) {
                    binding.shareFileIcon.setImageBitmap(thumbnail)
                }
            }
        }

        // Name
        binding.shareFileName.text = getResources().getString(R.string.share_file, file.getFileName())

        viewThemeUtils.platform.colorViewBackground(binding.shareHeaderDivider)

        // Size
        binding.shareFileSize.text = DisplayUtils.bytesToHumanReadable(file.getFileLength())

        let activity = self
        DispatchQueue.global().async {
            let result = ReadFileRemoteOperation(getFile().getRemotePath()).execute(user, activity)

            if result.isSuccess {
                if let remoteFile = result.getData().first as? RemoteFile {
                    let length = remoteFile.getLength()

                    getFile().setFileLength(length)
                    DispatchQueue.main.async {
                        binding.shareFileSize.text = DisplayUtils.bytesToHumanReadable(length)
                    }
                }
            }
        }

        if savedInstanceState == nil {
            // Add Share fragment on first creation
            let ft = getSupportFragmentManager().beginTransaction()
            let fragment = FileDetailSharingFragment.newInstance(getFile(), user)
            ft.replace(R.id.share_fragment_container, fragment, ShareActivity.TAG_SHARE_FRAGMENT)
            ft.commit()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Load data into the list
        Log_OC.d(ShareActivity.TAG, "Refreshing lists on account set")
        refreshSharesFromStorageManager()
    }

    override func doShareWith(shareeName: String, shareType: ShareType) {
        let fragment = FileDetailsSharingProcessFragment.newInstance(getFile(), shareeName, shareType, false)
        let transaction = supportFragmentManager.beginTransaction()
        transaction.replace(R.id.share_fragment_container, fragment, FileDetailsSharingProcessFragment.TAG)
        transaction.commit()
    }

    override func onRemoteOperationFinish(_ operation: RemoteOperation, result: RemoteOperationResult) {
        super.onRemoteOperationFinish(operation, result)
        
        if result.isSuccess() || 
            (operation is GetSharesForFileOperation && 
             result.code == .shareNotFound) {
            Log_OC.d(ShareActivity.TAG, "Refreshing view on successful operation or finished refresh")
            refreshSharesFromStorageManager()
        }
    }

    private func refreshSharesFromStorageManager() {
        if let shareFileFragment = getShareFileFragment(), shareFileFragment.isAdded {
            shareFileFragment.refreshCapabilitiesFromDB()
            shareFileFragment.refreshSharesFromDB()
        }
    }

    private func getShareFileFragment() -> FileDetailSharingFragment? {
        return getSupportFragmentManager().findFragment(byTag: ShareActivity.TAG_SHARE_FRAGMENT) as? FileDetailSharingFragment
    }

    func onShareProcessClosed() {
        self.dismiss(animated: true, completion: nil)
    }
}
