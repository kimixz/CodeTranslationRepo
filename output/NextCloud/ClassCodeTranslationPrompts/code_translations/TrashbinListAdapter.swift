
import UIKit

class TrashbinListAdapter: NSObject, UICollectionViewDataSource {
    private static let TRASHBIN_ITEM = 100
    private static let TRASHBIN_FOOTER = 101
    private static let TAG = String(describing: TrashbinListAdapter.self)

    private let trashbinActivityInterface: TrashbinActivityInterface
    private var files: [TrashbinFile]
    private let context: Context
    private let user: User
    private let storageManager: FileDataStorageManager
    private let preferences: AppPreferences
    private var asyncTasks: [ThumbnailsCacheManager.ThumbnailGenerationTask] = []
    private let viewThemeUtils: ViewThemeUtils

    init(trashbinActivityInterface: TrashbinActivityInterface,
         storageManager: FileDataStorageManager,
         preferences: AppPreferences,
         context: Context,
         user: User,
         viewThemeUtils: ViewThemeUtils) {
        self.files = []
        self.trashbinActivityInterface = trashbinActivityInterface
        self.user = user
        self.storageManager = storageManager
        self.preferences = preferences
        self.context = context
        self.viewThemeUtils = viewThemeUtils
    }

    func setTrashbinFiles(_ trashbinFiles: [TrashbinFile], clear: Bool) {
        if clear {
            files.removeAll()
        }

        files.append(contentsOf: trashbinFiles)

        files = preferences.getSortOrderByType(type: .trashBinView, order: .sortNewToOld).sortTrashbinFiles(files)

        notifyDataSetChanged()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return files.count + 1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let viewType = self.getItemViewType(position: indexPath.row)
        if viewType == TrashbinListAdapter.TRASHBIN_ITEM {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TrashbinFileViewHolder", for: indexPath) as! TrashbinFileViewHolder
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TrashbinFooterViewHolder", for: indexPath) as! TrashbinFooterViewHolder
            return cell
        }
    }

    func onBindViewHolder(_ holder: UICollectionViewCell, position: Int) {
        if let trashbinFileViewHolder = holder as? TrashbinFileViewHolder {
            let file = files[position]

            // layout
            trashbinFileViewHolder.binding.listItemLayout.setOnClickListener { _ in
                trashbinActivityInterface.onItemClicked(file)
            }

            // thumbnail
            trashbinFileViewHolder.binding.thumbnail.tag = file.remoteId
            setThumbnail(file: file, thumbnailView: trashbinFileViewHolder.binding.thumbnail)

            // fileName
            trashbinFileViewHolder.binding.filename.text = file.fileName

            // fileSize
            trashbinFileViewHolder.binding.fileSize.text = DisplayUtils.bytesToHumanReadable(file.fileLength)

            // originalLocation
            let location: String
            let lastIndex = file.originalLocation.lastIndex(of: "/") ?? file.originalLocation.startIndex
            if lastIndex != file.originalLocation.startIndex {
                location = ROOT_PATH + file.originalLocation[..<lastIndex] + PATH_SEPARATOR
            } else {
                location = ROOT_PATH
            }
            trashbinFileViewHolder.binding.originalLocation.text = location

            // deletion time
            trashbinFileViewHolder.binding.deletionTimestamp.text = DisplayUtils.getRelativeTimestamp(context, timestamp: file.deletionTimestamp * 1000)

            // checkbox
            trashbinFileViewHolder.binding.customCheckbox.isHidden = true

            // overflow menu
            trashbinFileViewHolder.binding.overflowMenu.setOnClickListener { v in
                trashbinActivityInterface.onOverflowIconClicked(file, v)
            }

            // restore button
            trashbinFileViewHolder.binding.restore.setOnClickListener { v in
                trashbinActivityInterface.onRestoreIconClicked(file, v)
            }

        } else if let trashbinFooterViewHolder = holder as? TrashbinFooterViewHolder {
            trashbinFooterViewHolder.binding.footerText.text = getFooterText()
        }
    }

    func removeFile(file: TrashbinFile) {
        if let index = files.firstIndex(of: file) {
            files.remove(at: index)
            notifyDataSetChanged() // needs to be used to also update footer
        }
    }

    func removeAllFiles() {
        files.removeAll()
        notifyDataSetChanged()
    }

    private func getFooterText() -> String {
        var filesCount = 0
        var foldersCount = 0
        let count = files.count
        for i in 0..<count {
            let file = files[i]
            if file.isFolder() {
                foldersCount += 1
            } else {
                if !file.isHidden() {
                    filesCount += 1
                }
            }
        }
        return generateFooterText(filesCount: filesCount, foldersCount: foldersCount)
    }

    private func generateFooterText(filesCount: Int, foldersCount: Int) -> String {
        var output: String
        let resources = context.resources

        if filesCount + foldersCount <= 0 {
            output = ""
        } else if foldersCount <= 0 {
            output = resources.localizedStringWithFormat(NSLocalizedString("file_list__footer__file", comment: ""), filesCount)
        } else if filesCount <= 0 {
            output = resources.localizedStringWithFormat(NSLocalizedString("file_list__footer__folder", comment: ""), foldersCount)
        } else {
            output = resources.localizedStringWithFormat(NSLocalizedString("file_list__footer__file", comment: ""), filesCount) + ", " +
                     resources.localizedStringWithFormat(NSLocalizedString("file_list__footer__folder", comment: ""), foldersCount)
        }

        return output
    }

    private func setThumbnail(file: TrashbinFile, thumbnailView: UIImageView) {
        if file.isFolder() {
            thumbnailView.image = MimeTypeUtil.getDefaultFolderIcon(context: context, viewThemeUtils: viewThemeUtils)
        } else {
            if (MimeTypeUtil.isImage(file) || MimeTypeUtil.isVideo(file)), let remoteId = file.getRemoteId() {
                // Thumbnail in cache?
                if let thumbnail = ThumbnailsCacheManager.getBitmapFromDiskCache(key: ThumbnailsCacheManager.PREFIX_THUMBNAIL + remoteId) {
                    if MimeTypeUtil.isVideo(file) {
                        let withOverlay = ThumbnailsCacheManager.addVideoOverlay(thumbnail: thumbnail, context: context)
                        thumbnailView.image = withOverlay
                    } else {
                        thumbnailView.image = thumbnail
                    }
                } else {
                    thumbnailView.image = MimeTypeUtil.getFileTypeIcon(mimeType: file.getMimeType(), fileName: file.getFileName(), context: context, viewThemeUtils: viewThemeUtils)

                    // generate new thumbnail
                    if ThumbnailsCacheManager.cancelPotentialThumbnailWork(file: file, imageView: thumbnailView) {
                        do {
                            let task = ThumbnailsCacheManager.ThumbnailGenerationTask(thumbnailView: thumbnailView, storageManager: storageManager, user: user, asyncTasks: asyncTasks)

                            let asyncDrawable = ThumbnailsCacheManager.AsyncThumbnailDrawable(resources: context.resources, placeholder: thumbnail, task: task)
                            thumbnailView.image = asyncDrawable
                            asyncTasks.append(task)
                            task.execute(ThumbnailsCacheManager.ThumbnailGenerationTaskObject(file: file, remoteId: remoteId))
                        } catch let e as IllegalArgumentException {
                            Log_OC.d(TrashbinListAdapter.TAG, "ThumbnailGenerationTask : \(e.message)")
                        }
                    }
                }

                if file.getMimeType().caseInsensitiveCompare("image/png") == .orderedSame {
                    thumbnailView.backgroundColor = UIColor(named: "bg_default")
                }
            } else {
                thumbnailView.image = MimeTypeUtil.getFileTypeIcon(mimeType: file.getMimeType(), fileName: file.getFileName(), context: context, viewThemeUtils: viewThemeUtils)
            }
        }
    }

    func getItemViewType(position: Int) -> Int {
        if position == files.count {
            return TrashbinListAdapter.TRASHBIN_FOOTER
        } else {
            return TrashbinListAdapter.TRASHBIN_ITEM
        }
    }

    func cancelAllPendingTasks() {
        for task in asyncTasks {
            task.cancel(true)
            if let getMethod = task.getGetMethod() {
                print("\(TrashbinListAdapter.TAG): cancel: abort get method directly")
                getMethod.abort()
            }
        }
        asyncTasks.removeAll()
    }

    func setSortOrder(_ sortOrder: FileSortOrder) {
        preferences.setSortOrder(type: .trashBinView, sortOrder: sortOrder)
        files = sortOrder.sortTrashbinFiles(files)
        notifyDataSetChanged()
    }
}

class TrashbinFileViewHolder: UICollectionViewCell {
    var binding: TrashbinItemBinding!

    override init(frame: CGRect) {
        super.init(frame: frame)
        // todo action mode
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class TrashbinFooterViewHolder: UICollectionViewCell {
    var binding: ListFooterBinding!

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
