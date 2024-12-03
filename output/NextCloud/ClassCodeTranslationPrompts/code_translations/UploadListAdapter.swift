
import UIKit

class UploadListAdapter: SectionedRecyclerViewAdapter<SectionedViewHolder> {
    private static let TAG = String(describing: UploadListAdapter.self)

    private var progressListener: ProgressListener?
    private let parentActivity: FileActivity
    private let uploadsStorageManager: UploadsStorageManager
    private let storageManager: FileDataStorageManager
    private let connectivityService: ConnectivityService
    private let powerManagementService: PowerManagementService
    private let accountManager: UserAccountManager
    private let clock: Clock
    private let uploadGroups: [UploadGroup]
    private let showUser: Bool
    private let viewThemeUtils: ViewThemeUtils
    private var mNotificationManager: NotificationManager?

    private let uploadHelper = FileUploadHelper.instance()

    override func getSectionCount() -> Int {
        return uploadGroups.count
    }

    override func numberOfItems(inSection section: Int) -> Int {
        return uploadGroups[section].getItems().count
    }

    override func onBindHeaderViewHolder(holder: SectionedViewHolder, section: Int, expanded: Bool) {
        guard let headerViewHolder = holder as? HeaderViewHolder else { return }

        let group = uploadGroups[section]

        headerViewHolder.binding.uploadListTitle.text = String(format: parentActivity.getString(R.string.uploads_view_group_header), group.getGroupName(), group.getGroupItemCount())
        viewThemeUtils.platform.colorPrimaryTextViewElement(headerViewHolder.binding.uploadListTitle)

        headerViewHolder.binding.uploadListTitle.setOnClickListener { _ in
            self.toggleSectionExpanded(section: section)
            headerViewHolder.binding.uploadListState.image = UIImage(named: self.isSectionExpanded(section: section) ? "ic_expand_less" : "ic_expand_more")
        }

        switch group.type {
        case .CURRENT, .FINISHED:
            headerViewHolder.binding.uploadListAction.image = UIImage(named: "ic_close")
        case .CANCELLED, .FAILED:
            headerViewHolder.binding.uploadListAction.image = UIImage(named: "ic_dots_vertical")
        }

        headerViewHolder.binding.uploadListAction.setOnClickListener { _ in
            switch group.type {
            case .CURRENT:
                DispatchQueue.global().async {
                    guard let ocUpload = group.getItem(0), let accountName = ocUpload.getAccountName() else { return }
                    self.uploadHelper.cancelFileUploads(group.items, accountName: accountName)
                    DispatchQueue.main.async {
                        self.loadUploadItemsFromDb()
                    }
                }
            case .FINISHED:
                self.uploadsStorageManager.clearSuccessfulUploads()
                self.loadUploadItemsFromDb()
            case .FAILED:
                self.showFailedPopupMenu(headerViewHolder: headerViewHolder)
            case .CANCELLED:
                self.showCancelledPopupMenu(headerViewHolder: headerViewHolder)
            }
        }
    }

    private func showFailedPopupMenu(headerViewHolder: HeaderViewHolder) {
        let failedPopup = UIMenuController.shared
        let actionClear = UIAction(title: "Clear", image: nil) { _ in
            self.uploadsStorageManager.clearFailedButNotDelayedUploads()
            self.clearTempEncryptedFolder()
            self.loadUploadItemsFromDb()
        }
        let actionRetry = UIAction(title: "Retry", image: nil) { _ in
            DispatchQueue.global().async {
                self.uploadHelper.retryFailedUploads(
                    uploadsStorageManager: self.uploadsStorageManager,
                    connectivityService: self.connectivityService,
                    accountManager: self.accountManager,
                    powerManagementService: self.powerManagementService)
                DispatchQueue.main.async {
                    self.loadUploadItemsFromDb()
                }
            }
        }
        let menu = UIMenu(title: "", children: [actionClear, actionRetry])
        failedPopup.menu = menu
        failedPopup.setTargetRect(headerViewHolder.binding.uploadListAction.frame, in: headerViewHolder.binding.uploadListAction.superview!)
        failedPopup.setMenuVisible(true, animated: true)
    }

    private func showCancelledPopupMenu(headerViewHolder: HeaderViewHolder) {
        let popup = UIMenuController.shared
        let actionClear = UIAction(title: "Clear", image: nil) { _ in
            uploadsStorageManager.clearCancelledUploadsForCurrentAccount()
            loadUploadItemsFromDb()
            clearTempEncryptedFolder()
        }
        let actionResume = UIAction(title: "Resume", image: nil) { _ in
            retryCancelledUploads()
        }
        let menu = UIMenu(title: "", children: [actionClear, actionResume])
        popup.menu = menu
        popup.showMenu(from: headerViewHolder.binding.uploadListAction, rect: headerViewHolder.binding.uploadListAction.bounds)
    }

    private func clearTempEncryptedFolder() {
        if let user = parentActivity.getUser() {
            FileDataStorageManager.clearTempEncryptedFolder(user.getAccountName())
        }
    }

    private func retryCancelledUploads() {
        DispatchQueue.global().async {
            let showNotExistMessage = uploadHelper.retryCancelledUploads(
                uploadsStorageManager: uploadsStorageManager,
                connectivityService: connectivityService,
                accountManager: accountManager,
                powerManagementService: powerManagementService
            )

            DispatchQueue.main.async {
                self.loadUploadItemsFromDb()
            }
            DispatchQueue.main.async {
                if showNotExistMessage {
                    self.showNotExistMessage()
                }
            }
        }
    }

    private func showNotExistMessage() {
        DisplayUtils.showSnackMessage(parentActivity, R.string.upload_action_file_not_exist_message)
    }

    override func onBindFooterViewHolder(holder: SectionedViewHolder, section: Int) {
        // not needed
    }

    public init(fileActivity: FileActivity,
                uploadsStorageManager: UploadsStorageManager,
                storageManager: FileDataStorageManager,
                accountManager: UserAccountManager,
                connectivityService: ConnectivityService,
                powerManagementService: PowerManagementService,
                clock: Clock,
                viewThemeUtils: ViewThemeUtils) {
        Log_OC.d(UploadListAdapter.TAG, "UploadListAdapter")

        self.parentActivity = fileActivity
        self.uploadsStorageManager = uploadsStorageManager
        self.storageManager = storageManager
        self.accountManager = accountManager
        self.connectivityService = connectivityService
        self.powerManagementService = powerManagementService
        self.clock = clock
        self.viewThemeUtils = viewThemeUtils

        uploadGroups = [
            UploadGroup(type: .CURRENT, groupName: parentActivity.getString(R.string.uploads_view_group_current_uploads)) {
                self.fixAndSortItems(self.uploadsStorageManager.getCurrentAndPendingUploadsForCurrentAccount())
            },
            UploadGroup(type: .FAILED, groupName: parentActivity.getString(R.string.uploads_view_group_failed_uploads)) {
                self.fixAndSortItems(self.uploadsStorageManager.getFailedButNotDelayedUploadsForCurrentAccount())
            },
            UploadGroup(type: .CANCELLED, groupName: parentActivity.getString(R.string.uploads_view_group_manually_cancelled_uploads)) {
                self.fixAndSortItems(self.uploadsStorageManager.getCancelledUploadsForCurrentAccount())
            },
            UploadGroup(type: .FINISHED, groupName: parentActivity.getString(R.string.uploads_view_group_finished_uploads)) {
                self.fixAndSortItems(self.uploadsStorageManager.getFinishedUploadsForCurrentAccount())
            }
        ]

        showUser = accountManager.getAccounts().count > 1

        loadUploadItemsFromDb()
    }

    override func onBindViewHolder(holder: SectionedViewHolder, section: Int, relativePosition: Int, absolutePosition: Int) {
        guard uploadGroups.count > 0, section >= 0, section < uploadGroups.count else {
            return
        }

        guard let uploadGroup = uploadGroups[section] else {
            return
        }

        guard let item = uploadGroup.getItem(relativePosition) else {
            return
        }

        let itemViewHolder = holder as! ItemViewHolder
        itemViewHolder.binding.uploadName.text = item.getLocalPath()

        // local file name
        let remoteFile = File(item.getRemotePath())
        var fileName = remoteFile.name
        if fileName.isEmpty {
            fileName = File.separator
        }
        itemViewHolder.binding.uploadName.text = fileName

        // remote path to parent folder
        itemViewHolder.binding.uploadRemotePath.text = File(item.getRemotePath()).parent

        // file size
        if item.getFileSize() != 0 {
            itemViewHolder.binding.uploadFileSize.text = String(format: "%s, ", DisplayUtils.bytesToHumanReadable(item.getFileSize()))
        } else {
            itemViewHolder.binding.uploadFileSize.text = ""
        }

        // upload date
        let updateTime = item.getUploadEndTimestamp()
        let dateString = DisplayUtils.getRelativeDateTimeString(parentActivity, updateTime, DateUtils.SECOND_IN_MILLIS, DateUtils.WEEK_IN_MILLIS, 0)
        itemViewHolder.binding.uploadDate.text = dateString

        // account
        let optionalUser = accountManager.getUser(item.getAccountName())
        if showUser {
            itemViewHolder.binding.uploadAccount.isHidden = false
            if let user = optionalUser {
                itemViewHolder.binding.uploadAccount.text = DisplayUtils.getAccountNameDisplayText(user)
            } else {
                itemViewHolder.binding.uploadAccount.text = item.getAccountName()
            }
        } else {
            itemViewHolder.binding.uploadAccount.isHidden = true
        }

        // Reset fields visibility
        itemViewHolder.binding.uploadDate.isHidden = false
        itemViewHolder.binding.uploadRemotePath.isHidden = false
        itemViewHolder.binding.uploadFileSize.isHidden = false
        itemViewHolder.binding.uploadStatus.isHidden = false
        itemViewHolder.binding.uploadProgressBar.isHidden = true

        // Update information depending on upload details
        let status = getStatusText(item)
        switch item.getUploadStatus() {
        case .UPLOAD_IN_PROGRESS:
            viewThemeUtils.platform.themeHorizontalProgressBar(itemViewHolder.binding.uploadProgressBar)
            itemViewHolder.binding.uploadProgressBar.progress = 0
            itemViewHolder.binding.uploadProgressBar.isHidden = false

            if uploadHelper.isUploadingNow(item) {
                if let progressListener = progressListener {
                    let targetKey = FileUploadHelper.buildRemoteName(progressListener.getUpload().getAccountName(), progressListener.getUpload().getRemotePath())
                    uploadHelper.removeUploadTransferProgressListener(progressListener, targetKey)
                }
                progressListener = ProgressListener(item: item, progressBar: itemViewHolder.binding.uploadProgressBar)
                let targetKey = FileUploadHelper.buildRemoteName(item.getAccountName(), item.getRemotePath())
                uploadHelper.addUploadTransferProgressListener(progressListener!, targetKey)
            } else {
                if let progressListener = progressListener, progressListener.isWrapping(itemViewHolder.binding.uploadProgressBar) {
                    let targetKey = FileUploadHelper.buildRemoteName(progressListener.getUpload().getAccountName(), progressListener.getUpload().getRemotePath())
                    uploadHelper.removeUploadTransferProgressListener(progressListener, targetKey)
                    self.progressListener = nil
                }
            }

            itemViewHolder.binding.uploadDate.isHidden = true
            itemViewHolder.binding.uploadFileSize.isHidden = true
            itemViewHolder.binding.uploadProgressBar.setNeedsDisplay()

        case .UPLOAD_FAILED:
            itemViewHolder.binding.uploadDate.isHidden = true

        case .UPLOAD_SUCCEEDED, .UPLOAD_CANCELLED:
            itemViewHolder.binding.uploadStatus.isHidden = true
        }

        if (item.getUploadStatus() == .UPLOAD_SUCCEEDED && item.getLastResult() != .UPLOADED) || item.getUploadStatus() == .UPLOAD_CANCELLED {
            itemViewHolder.binding.uploadStatus.isHidden = false
            itemViewHolder.binding.uploadDate.isHidden = true
            itemViewHolder.binding.uploadFileSize.isHidden = true
        }

        itemViewHolder.binding.uploadStatus.text = status

        // bind listeners to perform actions
        if item.getUploadStatus() == .UPLOAD_IN_PROGRESS {
            itemViewHolder.binding.uploadRightButton.setImage(UIImage(named: "ic_action_cancel_grey"), for: .normal)
            itemViewHolder.binding.uploadRightButton.isHidden = false
            itemViewHolder.binding.uploadRightButton.addTarget(self, action: #selector(cancelUpload(_:)), for: .touchUpInside)
        } else if item.getUploadStatus() == .UPLOAD_FAILED {
            if item.getLastResult() == .SYNC_CONFLICT {
                itemViewHolder.binding.uploadRightButton.setImage(UIImage(named: "ic_dots_vertical"), for: .normal)
                itemViewHolder.binding.uploadRightButton.addTarget(self, action: #selector(showItemConflictPopup(_:)), for: .touchUpInside)
            } else {
                itemViewHolder.binding.uploadRightButton.setImage(UIImage(named: "ic_action_delete_grey"), for: .normal)
                itemViewHolder.binding.uploadRightButton.addTarget(self, action: #selector(removeUpload(_:)), for: .touchUpInside)
            }
            itemViewHolder.binding.uploadRightButton.isHidden = false
        } else {
            itemViewHolder.binding.uploadRightButton.isHidden = true
        }

        itemViewHolder.binding.uploadListItemLayout.addGestureRecognizer(UITapGestureRecognizer(target: self, action: nil))

        // Set icon or thumbnail
        itemViewHolder.binding.thumbnail.image = UIImage(named: "file")

        // click on item
        if item.getUploadStatus() == .UPLOAD_FAILED || item.getUploadStatus() == .UPLOAD_CANCELLED {
            let uploadResult = item.getLastResult()
            itemViewHolder.binding.uploadListItemLayout.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleUploadItemClick(_:))))
        } else if item.getUploadStatus() == .UPLOAD_SUCCEEDED {
            itemViewHolder.binding.uploadListItemLayout.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onUploadedItemClick(_:))))
        }

        // click on thumbnail to open locally
        if item.getUploadStatus() != .UPLOAD_SUCCEEDED {
            itemViewHolder.binding.thumbnail.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onUploadingItemClick(_:))))
        }

        // Thumbnail management
        let fakeFile = OCFile(remotePath: item.getRemotePath())
        fakeFile.setStoragePath(item.getLocalPath())
        fakeFile.setMimeType(item.getMimeType())

        let allowedToCreateNewThumbnail = ThumbnailsCacheManager.cancelPotentialThumbnailWork(fakeFile, itemViewHolder.binding.thumbnail)

        if MimeTypeUtil.isImage(fakeFile), let remoteId = fakeFile.getRemoteId(), item.getUploadStatus() == .UPLOAD_SUCCEEDED {
            if let thumbnail = ThumbnailsCacheManager.getBitmapFromDiskCache(String(remoteId)), !fakeFile.isUpdateThumbnailNeeded() {
                itemViewHolder.binding.thumbnail.image = thumbnail
            } else {
                if allowedToCreateNewThumbnail, let user = parentActivity.getUser() {
                    let task = ThumbnailsCacheManager.ThumbnailGenerationTask(thumbnail: itemViewHolder.binding.thumbnail, storageManager: parentActivity.getStorageManager(), user: user)
                    let asyncDrawable = ThumbnailsCacheManager.AsyncThumbnailDrawable(resources: parentActivity.resources, placeholder: ThumbnailsCacheManager.mDefaultImg, task: task)
                    itemViewHolder.binding.thumbnail.image = asyncDrawable
                    task.execute(ThumbnailsCacheManager.ThumbnailGenerationTaskObject(file: fakeFile, completion: nil))
                }
            }

            if item.getMimeType() == "image/png" {
                itemViewHolder.binding.thumbnail.backgroundColor = UIColor(named: "bg_default")
            }
        } else if MimeTypeUtil.isImage(fakeFile) {
            let file = File(item.getLocalPath())
            if let thumbnail = ThumbnailsCacheManager.getBitmapFromDiskCache(String(file.hashValue)) {
                itemViewHolder.binding.thumbnail.image = thumbnail
            } else if allowedToCreateNewThumbnail {
                getThumbnailFromFileTypeAndSetIcon(item.getLocalPath(), itemViewHolder)

                let task = ThumbnailsCacheManager.ThumbnailGenerationTask(thumbnail: itemViewHolder.binding.thumbnail)
                let asyncDrawable = ThumbnailsCacheManager.AsyncThumbnailDrawable(resources: parentActivity.resources, placeholder: ThumbnailsCacheManager.mDefaultImg, task: task)
                task.execute(ThumbnailsCacheManager.ThumbnailGenerationTaskObject(file: file, completion: nil))
                task.setListener { success in
                    if success {
                        itemViewHolder.binding.thumbnail.image = asyncDrawable
                    } else {
                        getThumbnailFromFileTypeAndSetIcon(item.getLocalPath(), itemViewHolder)
                    }
                }
            }

            if item.getMimeType().lowercased() == "image/png" {
                itemViewHolder.binding.thumbnail.backgroundColor = UIColor(named: "bg_default")
            }
        } else {
            if let user = optionalUser {
                let icon = MimeTypeUtil.getFileTypeIcon(item.getMimeType(), fileName, parentActivity, viewThemeUtils)
                itemViewHolder.binding.thumbnail.image = icon
            }
        }
    }

    private func getThumbnailFromFileTypeAndSetIcon(localPath: String, itemViewHolder: ItemViewHolder) {
        if let drawable = MimeTypeUtil.getIcon(localPath: localPath, parentActivity: parentActivity, viewThemeUtils: viewThemeUtils) {
            itemViewHolder.binding.thumbnail.image = drawable
        }
    }

    private func checkAndOpenConflictResolutionDialog(user: User, itemViewHolder: ItemViewHolder, item: OCUpload, status: String) -> Bool {
        let remotePath = item.getRemotePath()
        let localFile = storageManager.getFileByEncryptedRemotePath(remotePath)

        if localFile == nil {
            // Remote file doesn't exist, try to refresh folder
            if let folder = storageManager.getFileByEncryptedRemotePath((remotePath as NSString).deletingLastPathComponent + "/"), folder.isFolder() {
                refreshFolderAndUpdateUI(itemViewHolder: itemViewHolder, user: user, folder: folder, remotePath: remotePath, item: item, status: status)
                return true
            }

            // Destination folder doesn't exist anymore
        }

        if let localFile = localFile {
            self.openConflictActivity(localFile: localFile, item: item)
            return true
        }

        // Remote file doesn't exist anymore = there is no more conflict
        return false
    }

    private func refreshFolderAndUpdateUI(holder: ItemViewHolder, user: User, folder: OCFile, remotePath: String, item: OCUpload, status: String) {
        let context = MainApp.getAppContext()

        self.refreshFolder(context: context, holder: holder, user: user, folder: folder) { caller, result in
            holder.binding.uploadStatus.text = status

            if result.isSuccess() {
                if let fileOnServer = storageManager.getFileByEncryptedRemotePath(remotePath) {
                    openConflictActivity(fileOnServer: fileOnServer, item: item)
                } else {
                    displayFileNotFoundError(view: holder.itemView, context: context)
                }
            }
        }
    }

    private func displayFileNotFoundError(itemView: UIView, context: Context) {
        let message = context.getString(R.string.uploader_file_not_found_message)
        DisplayUtils.showSnackMessage(itemView, message)
    }

    private func showItemConflictPopup(user: User, itemViewHolder: ItemViewHolder, item: OCUpload, status: String, view: UIView) {
        let popup = UIMenuController.shared
        let resolveConflictAction = UIAction(title: "Resolve Conflict", handler: { _ in
            self.checkAndOpenConflictResolutionDialog(user: user, itemViewHolder: itemViewHolder, item: item, status: status)
        })
        let removeUploadAction = UIAction(title: "Remove Upload", handler: { _ in
            self.removeUpload(item: item)
        })
        popup.menuItems = [resolveConflictAction, removeUploadAction]
        popup.showMenu(from: view, rect: view.bounds)
    }

    func removeUpload(item: OCUpload) {
        uploadsStorageManager.removeUpload(item)
        cancelOldErrorNotification(item: item)
        loadUploadItemsFromDb()
    }

    private func refreshFolder(
        context: Context,
        view: ItemViewHolder,
        user: User,
        folder: OCFile,
        listener: OnRemoteOperationListener
    ) {
        view.binding.uploadListItemLayout.isUserInteractionEnabled = false
        view.binding.uploadStatus.text = NSLocalizedString("uploads_view_upload_status_fetching_server_version", comment: "")
        RefreshFolderOperation(
            folder: folder,
            currentTime: clock.getCurrentTime(),
            param1: false,
            param2: false,
            param3: true,
            storageManager: storageManager,
            user: user,
            context: context
        ).execute(user: user, context: context) { caller, result in
            view.binding.uploadListItemLayout.isUserInteractionEnabled = true
            listener.onRemoteOperationFinish(caller: caller, result: result)
        }
    }

    private func openConflictActivity(file: OCFile, upload: OCUpload) {
        file.setStoragePath(upload.getLocalPath())

        let context = MainApp.getAppContext()
        if let user = accountManager.getUser(upload.getAccountName()) {
            let intent = ConflictsResolveActivity.createIntent(file: file,
                                                               user: user,
                                                               uploadId: upload.getUploadId(),
                                                               flags: .newTask,
                                                               context: context)

            context.startActivity(intent)
        }
    }

    private func getStatusText(upload: OCUpload) -> String {
        var status: String
        switch upload.getUploadStatus() {
        case .UPLOAD_IN_PROGRESS:
            status = parentActivity.getString(R.string.uploads_view_later_waiting_to_upload)
            if uploadHelper.isUploadingNow(upload) {
                status = parentActivity.getString(R.string.uploader_upload_in_progress_ticker)
            }
            if parentActivity.getAppPreferences().isGlobalUploadPaused() {
                status = parentActivity.getString(R.string.upload_global_pause_title)
            }
        case .UPLOAD_SUCCEEDED:
            if upload.getLastResult() == .SAME_FILE_CONFLICT {
                status = parentActivity.getString(R.string.uploads_view_upload_status_succeeded_same_file)
            } else if upload.getLastResult() == .FILE_NOT_FOUND {
                status = getUploadFailedStatusText(upload.getLastResult())
            } else {
                status = parentActivity.getString(R.string.uploads_view_upload_status_succeeded)
            }
        case .UPLOAD_FAILED:
            status = getUploadFailedStatusText(upload.getLastResult())
        case .UPLOAD_CANCELLED:
            status = parentActivity.getString(R.string.upload_manually_cancelled)
        default:
            status = "Uncontrolled status: \(upload.getUploadStatus())"
        }
        return status
    }

    private func getUploadFailedStatusText(result: UploadResult) -> String {
        let status: String
        switch result {
        case .CREDENTIAL_ERROR:
            status = parentActivity.getString(R.string.uploads_view_upload_status_failed_credentials_error)
        case .FOLDER_ERROR:
            status = parentActivity.getString(R.string.uploads_view_upload_status_failed_folder_error)
        case .FILE_NOT_FOUND:
            status = parentActivity.getString(R.string.uploads_view_upload_status_failed_localfile_error)
        case .FILE_ERROR:
            status = parentActivity.getString(R.string.uploads_view_upload_status_failed_file_error)
        case .PRIVILEGES_ERROR:
            status = parentActivity.getString(R.string.uploads_view_upload_status_failed_permission_error)
        case .NETWORK_CONNECTION:
            status = parentActivity.getString(R.string.uploads_view_upload_status_failed_connection_error)
        case .DELAYED_FOR_WIFI:
            status = parentActivity.getString(R.string.uploads_view_upload_status_waiting_for_wifi)
        case .DELAYED_FOR_CHARGING:
            status = parentActivity.getString(R.string.uploads_view_upload_status_waiting_for_charging)
        case .CONFLICT_ERROR:
            status = parentActivity.getString(R.string.uploads_view_upload_status_conflict)
        case .SERVICE_INTERRUPTED:
            status = parentActivity.getString(R.string.uploads_view_upload_status_service_interrupted)
        case .CANCELLED:
            status = parentActivity.getString(R.string.uploads_view_upload_status_cancelled)
        case .UPLOADED:
            status = parentActivity.getString(R.string.uploads_view_upload_status_succeeded)
        case .MAINTENANCE_MODE:
            status = parentActivity.getString(R.string.maintenance_mode)
        case .SSL_RECOVERABLE_PEER_UNVERIFIED:
            status = parentActivity.getString(R.string.uploads_view_upload_status_failed_ssl_certificate_not_trusted)
        case .UNKNOWN:
            status = parentActivity.getString(R.string.uploads_view_upload_status_unknown_fail)
        case .LOCK_FAILED:
            status = parentActivity.getString(R.string.upload_lock_failed)
        case .DELAYED_IN_POWER_SAVE_MODE:
            status = parentActivity.getString(R.string.uploads_view_upload_status_waiting_exit_power_save_mode)
        case .VIRUS_DETECTED:
            status = parentActivity.getString(R.string.uploads_view_upload_status_virus_detected)
        case .LOCAL_STORAGE_FULL:
            status = parentActivity.getString(R.string.upload_local_storage_full)
        case .OLD_ANDROID_API:
            status = parentActivity.getString(R.string.upload_old_android)
        case .SYNC_CONFLICT:
            status = parentActivity.getString(R.string.upload_sync_conflict)
        case .CANNOT_CREATE_FILE:
            status = parentActivity.getString(R.string.upload_cannot_create_file)
        case .LOCAL_STORAGE_NOT_COPIED:
            status = parentActivity.getString(R.string.upload_local_storage_not_copied)
        case .QUOTA_EXCEEDED:
            status = parentActivity.getString(R.string.upload_quota_exceeded)
        default:
            status = parentActivity.getString(R.string.upload_unknown_error)
        }
        return status
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let viewType = self.viewType(for: indexPath)
        if viewType == VIEW_TYPE_HEADER {
            let headerCell = collectionView.dequeueReusableCell(withReuseIdentifier: "HeaderViewHolder", for: indexPath) as! HeaderViewHolder
            return headerCell
        } else {
            let itemCell = collectionView.dequeueReusableCell(withReuseIdentifier: "ItemViewHolder", for: indexPath) as! ItemViewHolder
            return itemCell
        }
    }

    func loadUploadItemsFromDb() {
        print("\(UploadListAdapter.TAG): loadUploadItemsFromDb")
        
        for group in uploadGroups {
            group.refresh()
        }
        
        notifyDataSetChanged()
    }

    private func onUploadingItemClick(file: OCUpload) {
        let f = FileManager.default.fileExists(atPath: file.localPath)
        if !f {
            DisplayUtils.showSnackMessage(parentActivity, R.string.local_file_not_found_message)
        } else {
            openFileWithDefault(file.localPath)
        }
    }

    private func onUploadedItemClick(upload: OCUpload) {
        guard let file = parentActivity.storageManager.getFileByEncryptedRemotePath(upload.remotePath) else {
            DisplayUtils.showSnackMessage(parentActivity, R.string.error_retrieving_file)
            Log_OC.i(UploadListAdapter.TAG, "Could not find uploaded file on remote.")
            return
        }

        if PreviewImageFragment.canBePreviewed(file) {
            // show image preview and stay in uploads tab
            let intent = FileDisplayActivity.openFileIntent(parentActivity, parentActivity.user.get(), file)
            parentActivity.startActivity(intent)
        } else {
            let intent = Intent(parentActivity, FileDisplayActivity.self)
            intent.setAction(Intent.ACTION_VIEW)
            intent.putExtra(FileDisplayActivity.KEY_FILE_PATH, upload.remotePath)
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            parentActivity.startActivity(intent)
        }
    }

    private func openFileWithDefault(localPath: String) {
        let file = URL(fileURLWithPath: localPath)
        var mimetype = MimeTypeUtil.getBestMimeTypeByFilename(localPath)
        if mimetype == "application/octet-stream" {
            mimetype = "*/*"
        }
        let documentController = UIDocumentInteractionController(url: file)
        documentController.uti = mimetype
        documentController.delegate = parentActivity as? UIDocumentInteractionControllerDelegate
        if !documentController.presentPreview(animated: true) {
            DisplayUtils.showSnackMessage(parentActivity, R.string.file_list_no_app_for_file_type)
            Log_OC.i(UploadListAdapter.TAG, "Could not find app for sending log history.")
        }
    }

    static class HeaderViewHolder: SectionedViewHolder {
        let binding: UploadListHeaderBinding

        init(binding: UploadListHeaderBinding) {
            self.binding = binding
            super.init(binding.getRoot())
        }
    }

    static class ItemViewHolder: SectionedViewHolder {
        let binding: UploadListItemBinding

        init(binding: UploadListItemBinding) {
            self.binding = binding
            super.init(binding.getRoot())
        }
    }

    enum Type {
        case CURRENT, FINISHED, FAILED, CANCELLED
    }

    class UploadGroup {
        private let type: Type
        private var items: [OCUpload]
        private let name: String

        init(type: Type, groupName: String, refresh: @escaping () -> Void) {
            self.type = type
            self.name = groupName
            self.items = []
            self.refresh = refresh
        }

        private func getGroupName() -> String {
            return name
        }

        func getItems() -> [OCUpload] {
            return items
        }

        func getItem(position: Int) -> OCUpload? {
            if items.isEmpty || position < 0 || position >= items.count {
                return nil
            }
            
            return items[position]
        }

        func setItems(_ items: OCUpload...) {
            self.items = items
        }

        func fixAndSortItems(_ array: OCUpload...) {
            for upload in array {
                upload.setDataFixed(uploadHelper)
            }
            array.sort(by: OCUploadComparator().compare)
            
            setItems(array)
        }

        private func getGroupItemCount() -> Int {
            return items == nil ? 0 : items.count
        }
    }

    func cancelOldErrorNotification(upload: OCUpload?) {
        if mNotificationManager == nil {
            mNotificationManager = parentActivity.getSystemService(name: .notification) as? NotificationManager
        }
        
        guard let upload = upload else {
            return
        }
        mNotificationManager?.cancel(NotificationUtils.createUploadNotificationTag(remotePath: upload.getRemotePath(), localPath: upload.getLocalPath()), 
                                     FileUploadWorker.NOTIFICATION_ERROR_ID)
    }
}
