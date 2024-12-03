
import Foundation

class FileMenuFilter {
    private static let SINGLE_SELECT_ITEMS = 1
    private static let EMPTY_FILE_LENGTH = 0
    public static let SEND_OFF = "off"

    private let numberOfAllFiles: Int
    private let files: [OCFile]
    private let componentsGetter: ComponentsGetter
    private let context: Context
    private let overflowMenu: Bool
    private let user: User
    private let userId: String
    private let storageManager: FileDataStorageManager
    private let editorUtils: EditorUtils

    class Factory {
        private let storageManager: FileDataStorageManager
        private let context: Context
        private let editorUtils: EditorUtils

        init(storageManager: FileDataStorageManager, context: Context, editorUtils: EditorUtils) {
            self.storageManager = storageManager
            self.context = context
            self.editorUtils = editorUtils
        }

        func newInstance(numberOfAllFiles: Int, files: [OCFile], componentsGetter: ComponentsGetter, overflowMenu: Bool, user: User) -> FileMenuFilter {
            return FileMenuFilter(storageManager: storageManager, editorUtils: editorUtils, numberOfAllFiles: numberOfAllFiles, files: files, componentsGetter: componentsGetter, context: context, overflowMenu: overflowMenu, user: user)
        }

        func newInstance(file: OCFile, componentsGetter: ComponentsGetter, overflowMenu: Bool, user: User) -> FileMenuFilter {
            return newInstance(numberOfAllFiles: 1, files: [file], componentsGetter: componentsGetter, overflowMenu: overflowMenu, user: user)
        }
    }

    private init(storageManager: FileDataStorageManager, editorUtils: EditorUtils, numberOfAllFiles: Int, files: [OCFile], componentsGetter: ComponentsGetter, context: Context, overflowMenu: Bool, user: User) {
        self.storageManager = storageManager
        self.editorUtils = editorUtils
        self.numberOfAllFiles = numberOfAllFiles
        self.files = files
        self.componentsGetter = componentsGetter
        self.context = context
        self.overflowMenu = overflowMenu
        self.user = user
        self.userId = AccountManager.get(context).getUserData(user.toPlatformAccount(), com.owncloud.android.lib.common.accounts.AccountUtils.Constants.KEY_USER_ID)
    }

    func getToHide(inSingleFileFragment: Bool) -> [Int]? {
        if !files.isEmpty {
            return filter(inSingleFileFragment: inSingleFileFragment)
        }
        return nil
    }

    private func filter(inSingleFileFragment: Bool) -> [Int] {
        let synchronizing = anyFileSynchronizing()
        let capability = storageManager.getCapability(user.getAccountName())
        let endToEndEncryptionEnabled = capability.getEndToEndEncryption().isTrue()
        let fileLockingEnabled = capability.getFilesLockingVersion() != nil

        var toHide: [Int] = []

        filterEdit(&toHide, capability: capability)
        filterDownload(&toHide, synchronizing: synchronizing)
        filterExport(&toHide)
        filterRename(&toHide, synchronizing: synchronizing)
        filterMoveOrCopy(&toHide, synchronizing: synchronizing)
        filterRemove(&toHide, synchronizing: synchronizing)
        filterSelectAll(&toHide, inSingleFileFragment: inSingleFileFragment)
        filterDeselectAll(&toHide, inSingleFileFragment: inSingleFileFragment)
        filterOpenWith(&toHide, synchronizing: synchronizing)
        filterCancelSync(&toHide, synchronizing: synchronizing)
        filterSync(&toHide, synchronizing: synchronizing)
        filterShareFile(&toHide, capability: capability)
        filterSendFiles(&toHide, inSingleFileFragment: inSingleFileFragment)
        filterDetails(&toHide)
        filterFavorite(&toHide, synchronizing: synchronizing)
        filterUnfavorite(&toHide, synchronizing: synchronizing)
        filterEncrypt(&toHide, endToEndEncryptionEnabled: endToEndEncryptionEnabled)
        filterUnsetEncrypted(&toHide, endToEndEncryptionEnabled: endToEndEncryptionEnabled)
        filterSetPictureAs(&toHide)
        filterStream(&toHide)
        filterLock(&toHide, fileLockingEnabled: fileLockingEnabled)
        filterUnlock(&toHide, fileLockingEnabled: fileLockingEnabled)
        filterPinToHome(&toHide)
        filterRetry(&toHide)

        return toHide
    }

    private func filterShareFile(toHide: inout [Int], capability: OCCapability) {
        if !isSingleSelection() || containsEncryptedFile() || hasEncryptedParent() || (!isShareViaLinkAllowed() && !isShareWithUsersAllowed()) || !isShareApiEnabled(capability) || !(files.first?.canReshare() ?? false) {
            toHide.append(R.id.action_send_share_file)
        }
    }

    private func filterSendFiles(toHide: inout [Int], inSingleFileFragment: Bool) {
        let sendFilesNotSupported = context != nil && !MDMConfig.INSTANCE.sendFilesSupport(context)
        let hasEncryptedFile = containsEncryptedFile()
        let isSingleSelection = isSingleSelection()
        let allFilesNotDown = !allFileDown()

        if sendFilesNotSupported {
            toHide.append(R.id.action_send_file)
            return
        }

        if overflowMenu || hasEncryptedFile {
            toHide.append(R.id.action_send_file)
            return
        }

        if !inSingleFileFragment && (isSingleSelection || allFilesNotDown) {
            toHide.append(R.id.action_send_file)
        } else if !toHide.contains(R.id.action_send_share_file) {
            toHide.append(R.id.action_send_file)
        }
    }

    private func filterDetails(toHide: inout [Int]) {
        if !isSingleSelection() {
            toHide.append(R.id.action_see_details)
        }
    }

    private func filterFavorite(toHide: inout [Int], synchronizing: Bool) {
        if files.isEmpty || synchronizing || allFavorites() {
            toHide.append(R.id.action_favorite)
        }
    }

    private func filterUnfavorite(toHide: inout [Int], synchronizing: Bool) {
        if files.isEmpty || synchronizing || allNotFavorites() {
            toHide.append(R.id.action_unset_favorite)
        }
    }

    private func filterLock(toHide: inout [Int], fileLockingEnabled: Bool) {
        if files.isEmpty || !isSingleSelection() || !fileLockingEnabled || containsEncryptedFile() || containsEncryptedFolder() {
            toHide.append(R.id.action_lock_file)
        } else {
            if let file = files.first {
                if file.isLocked || file.isFolder {
                    toHide.append(R.id.action_lock_file)
                }
            }
        }
    }

    private func filterUnlock(toHide: inout [Int], fileLockingEnabled: Bool) {
        if files.isEmpty || !isSingleSelection() || !fileLockingEnabled {
            toHide.append(R.id.action_unlock_file)
        } else {
            if let file = files.first, !FileLockingHelper.canUserUnlockFile(userId: userId, file: file) {
                toHide.append(R.id.action_unlock_file)
            }
        }
    }

    private func filterEncrypt(toHide: inout [Int], endToEndEncryptionEnabled: Bool) {
        if files.isEmpty || !isSingleSelection() || isSingleFile() || isEncryptedFolder() || isGroupFolder() || !endToEndEncryptionEnabled || !isEmptyFolder() || isShared() {
            toHide.append(R.id.action_encrypted)
        }
    }

    private func filterUnsetEncrypted(toHide: inout [Int], endToEndEncryptionEnabled: Bool) {
        if !endToEndEncryptionEnabled || files.isEmpty || !isSingleSelection() || isSingleFile() || !isEncryptedFolder() || hasEncryptedParent() || !isEmptyFolder() || !FileOperationsHelper.isEndToEndEncryptionSetup(context: context, user: user) {
            toHide.append(R.id.action_unset_encrypted)
        }
    }

    private func filterSetPictureAs(toHide: inout [Int]) {
        if !isSingleImage() || MimeTypeUtil.isSVG(files.first!) {
            toHide.append(R.id.action_set_as_wallpaper)
        }
    }

    private func filterPinToHome(toHide: inout [Int]) {
        if !isSingleSelection() || !ShortcutManagerCompat.isRequestPinShortcutSupported(context) {
            toHide.append(R.id.action_pin_to_homescreen)
        }
    }

    private func filterRetry(toHide: inout [Int]) {
        if !files.first!.isOfflineOperation() {
            toHide.append(R.id.action_retry)
        }
    }

    private func filterEdit(toHide: inout [Int], capability: OCCapability) {
        if files.first?.isEncrypted() == true {
            toHide.append(R.id.action_edit)
            return
        }

        let mimeType = files.first?.getMimeType() ?? ""

        if !isRichDocumentEditingSupported(capability: capability, mimeType: mimeType) && !editorUtils.isEditorAvailable(user: user, mimeType: mimeType) && !(isSingleImage() && EditImageActivity.canBePreviewed(file: files.first!)) {
            toHide.append(R.id.action_edit)
        }
    }

    private func isRichDocumentEditingSupported(capability: OCCapability, mimeType: String) -> Bool {
        return isSingleFile() && (capability.getRichDocumentsMimeTypeList().contains(mimeType) || capability.getRichDocumentsOptionalMimeTypeList().contains(mimeType)) && capability.getRichDocumentsDirectEditing().isTrue()
    }

    private func filterSync(toHide: inout [Int], synchronizing: Bool) {
        if files.isEmpty || (!anyFileDown() && !containsFolder()) || synchronizing || containsEncryptedFile() || containsEncryptedFolder() {
            toHide.append(R.id.action_sync_file)
        }
    }

    private func filterCancelSync(toHide: inout [Int], synchronizing: Bool) {
        if files.isEmpty || !synchronizing {
            toHide.append(R.id.action_cancel_sync)
        }
    }

    private func filterOpenWith(toHide: inout [Int], synchronizing: Bool) {
        if !isSingleFile() || !anyFileDown() || synchronizing {
            toHide.append(R.id.action_open_file_with)
        }
    }

    private func filterDeselectAll(toHide: inout [Int], inSingleFileFragment: Bool) {
        if inSingleFileFragment {
            toHide.append(R.id.action_deselect_all_action_menu)
        } else {
            if files.isEmpty || overflowMenu {
                toHide.append(R.id.action_deselect_all_action_menu)
            }
        }
    }

    private func filterSelectAll(toHide: inout [Int], inSingleFileFragment: Bool) {
        if !inSingleFileFragment {
            if files.count >= numberOfAllFiles || overflowMenu {
                toHide.append(R.id.action_select_all_action_menu)
            }
        } else {
            toHide.append(R.id.action_select_all_action_menu)
        }
    }

    private func filterRemove(toHide: inout [Int], synchronizing: Bool) {
        if files.isEmpty || synchronizing || containsLockedFile() || containsEncryptedFolder() || isFolderAndContainsEncryptedFile() {
            toHide.append(R.id.action_remove_file)
        }
    }

    private func filterMoveOrCopy(toHide: inout [Int], synchronizing: Bool) {
        if files.isEmpty || synchronizing || containsEncryptedFile() || containsEncryptedFolder() || containsLockedFile() {
            toHide.append(R.id.action_move_or_copy)
        }
    }

    private func filterRename(toHide: inout [Int], synchronizing: Bool) {
        if !isSingleSelection() || synchronizing || containsEncryptedFile() || containsEncryptedFolder() || containsLockedFile() {
            toHide.append(R.id.action_rename_file)
        }
    }

    private func filterDownload(toHide: inout [Int], synchronizing: Bool) {
        if files.isEmpty || containsFolder() || anyFileDown() || synchronizing {
            toHide.append(R.id.action_download_file)
        }
    }

    private func filterExport(toHide: inout [Int]) {
        if files.isEmpty || containsFolder() {
            toHide.append(R.id.action_export_file)
        }
    }

    private func filterStream(toHide: inout [Int]) {
        if files.isEmpty || !isSingleFile() || !isSingleMedia() || containsEncryptedFile() {
            toHide.append(R.id.action_stream_media)
        }
    }

    private func anyFileSynchronizing() -> Bool {
        var synchronizing = false
        if let componentsGetter = componentsGetter, !files.isEmpty, user != nil {
            if let opsBinder = componentsGetter.getOperationsServiceBinder() {
                synchronizing = anyFileSynchronizing(opsBinder: opsBinder) || anyFileDownloading() || anyFileUploading()
            }
        }
        return synchronizing
    }

    private func anyFileSynchronizing(opsBinder: OperationsServiceBinder?) -> Bool {
        var synchronizing = false
        if let opsBinder = opsBinder {
            for file in files where !synchronizing {
                synchronizing = opsBinder.isSynchronizing(user: user, file: file)
            }
        }
        return synchronizing
    }

    private func anyFileDownloading() -> Bool {
        let fileDownloadHelper = FileDownloadHelper.instance()

        for file in files {
            if fileDownloadHelper.isDownloading(user: user, file: file) {
                return true
            }
        }

        return false
    }

    private func anyFileUploading() -> Bool {
        for file in files {
            if FileUploadHelper.instance().isUploading(user: user, file: file) {
                return true
            }
        }
        return false
    }

    private func isShareApiEnabled(capability: OCCapability?) -> Bool {
        return capability != nil && (capability!.getFilesSharingApiEnabled().isTrue() || capability!.getFilesSharingApiEnabled().isUnknown())
    }

    private func isShareWithUsersAllowed() -> Bool {
        return context != nil && MDMConfig.INSTANCE.shareViaUser(context)
    }

    private func isShareViaLinkAllowed() -> Bool {
        return context != nil && MDMConfig.INSTANCE.shareViaLink(context)
    }

    private func isSingleSelection() -> Bool {
        return files.count == FileMenuFilter.SINGLE_SELECT_ITEMS
    }

    private func isSingleFile() -> Bool {
        return isSingleSelection() && !(files.first?.isFolder ?? true)
    }

    private func isEncryptedFolder() -> Bool {
        if isSingleSelection() {
            if let file = files.first {
                return file.isFolder && file.isEncrypted
            }
        }
        return false
    }

    private func isEmptyFolder() -> Bool {
        if isSingleSelection() {
            let file = files.first!

            let noChildren = storageManager.getFolderContent(file, false).count == FileMenuFilter.EMPTY_FILE_LENGTH

            return file.isFolder && file.getFileLength() == FileMenuFilter.EMPTY_FILE_LENGTH && noChildren
        } else {
            return false
        }
    }

    private func isGroupFolder() -> Bool {
        return files.first?.isGroupFolder() ?? false
    }

    private func hasEncryptedParent() -> Bool {
        guard let folder = files.first else { return false }
        if let parent = storageManager.getFileById(folder.getParentId()) {
            return parent.isEncrypted
        }
        return false
    }

    private func isSingleImage() -> Bool {
        return isSingleSelection() && MimeTypeUtil.isImage(files.first!)
    }

    private func isSingleMedia() -> Bool {
        let file = files.first!
        return isSingleSelection() && (MimeTypeUtil.isVideo(file) || MimeTypeUtil.isAudio(file))
    }

    private func isFolderAndContainsEncryptedFile() -> Bool {
        for file in files {
            if !file.isFolder {
                continue
            }
            if file.isFolder {
                let children = storageManager.getFolderContent(file, false)
                for child in children {
                    if child.isEncrypted {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func containsEncryptedFile() -> Bool {
        for file in files {
            if !file.isFolder && file.isEncrypted {
                return true
            }
        }
        return false
    }

    private func containsLockedFile() -> Bool {
        for file in files {
            if file.isLocked {
                return true
            }
        }
        return false
    }

    private func containsEncryptedFolder() -> Bool {
        for file in files {
            if file.isFolder && file.isEncrypted {
                return true
            }
        }
        return false
    }

    private func containsFolder() -> Bool {
        for file in files {
            if file.isFolder {
                return true
            }
        }
        return false
    }

    private func anyFileDown() -> Bool {
        for file in files {
            if file.isDown {
                return true
            }
        }
        return false
    }

    private func allFileDown() -> Bool {
        for file in files {
            if !file.isDown {
                return false
            }
        }
        return true
    }

    private func allFavorites() -> Bool {
        for file in files {
            if !file.isFavorite {
                return false
            }
        }
        return true
    }

    private func allNotFavorites() -> Bool {
        for file in files {
            if file.isFavorite {
                return false
            }
        }
        return true
    }

    private func isShared() -> Bool {
        for file in files {
            if file.isSharedWithMe || file.isSharedViaLink || file.isSharedWithSharee {
                return true
            }
        }
        return false
    }
}
