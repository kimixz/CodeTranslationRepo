
import Foundation
import Photos

enum FileVisitResult {
    case continueVisit
    case terminate
}

protocol FileVisitor {
    func preVisitDirectory(_ dir: URL, attributes: [FileAttributeKey: Any]?) -> FileVisitResult
    func visitFile(_ file: URL, attributes: [FileAttributeKey: Any]?)
    func visitFileFailed(_ file: URL, error: Error)
    func postVisitDirectory(_ dir: URL, error: Error?)
}

func walkFileTreeRandomly(start: URL, visitor: FileVisitor) throws {
    let file = start
    let fileManager = FileManager.default

    guard fileManager.isReadableFile(atPath: file.path) else {
        visitor.visitFileFailed(file, error: NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError, userInfo: [NSFilePathErrorKey: file.path]))
        return
    }

    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory), isDirectory.boolValue {
        let preVisitDirectoryResult = visitor.preVisitDirectory(file, attributes: try? fileManager.attributesOfItem(atPath: file.path))
        if preVisitDirectoryResult == .continueVisit {
            if let children = try? fileManager.contentsOfDirectory(at: file, includingPropertiesForKeys: nil, options: []) {
                let shuffledChildren = children.shuffled()
                for child in shuffledChildren {
                    try walkFileTreeRandomly(start: child, visitor: visitor)
                }
                visitor.postVisitDirectory(file, error: nil)
            }
        }
    } else {
        visitor.visitFile(file, attributes: try? fileManager.attributesOfItem(atPath: file.path))
    }
}

private static func insertCustomFolderIntoDB(path: URL, syncedFolder: SyncedFolder, filesystemDataProvider: FilesystemDataProvider, lastCheck: Int64) {
    let enabledTimestampMs = syncedFolder.getEnabledTimestampMs()

    do {
        try walkFileTreeRandomly(start: path) { (url, attrs) -> FileVisitResult in
            let file = url
            if syncedFolder.isExcludeHidden() && file.isHidden {
                return .continueVisit
            }

            if let lastModifiedTime = attrs?[.modificationDate] as? Date, lastModifiedTime.timeIntervalSince1970 * 1000 < lastCheck {
                return .continueVisit
            }

            if syncedFolder.isExisting() || (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0 * 1000 >= enabledTimestampMs {
                filesystemDataProvider.storeOrUpdateFileValue(path: file.absoluteString, lastModified: (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0 * 1000, isDirectory: file.isDirectory, syncedFolder: syncedFolder)
            }

            return .continueVisit
        } preVisitDirectory: { (dir, attrs) -> FileVisitResult in
            if syncedFolder.isExcludeHidden() && dir != URL(fileURLWithPath: syncedFolder.getLocalPath()) && dir.isHidden {
                return .terminate
            }
            return .continueVisit
        } visitFileFailed: { (file, error) -> FileVisitResult in
            return .continueVisit
        }
    } catch {
        print("Something went wrong while indexing files for auto upload: \(error)")
    }
}

class FilesSyncHelper {
    static let TAG = "FileSyncHelper"
    static let GLOBAL = "global"

    private init() {
        // utility class -> private constructor
    }

    static func insertAllDBEntriesForSyncedFolder(syncedFolder: SyncedFolder) {
        let context = MainApp.getAppContext()
        let contentResolver = context.contentResolver

        let enabledTimestampMs = syncedFolder.getEnabledTimestampMs()

        if syncedFolder.isEnabled() && (syncedFolder.isExisting() || enabledTimestampMs >= 0) {
            let mediaType = syncedFolder.getType()
            let lastCheckTimestampMs = syncedFolder.getLastScanTimestampMs()

            Log_OC.d(TAG, "File-sync start check folder \(syncedFolder.getLocalPath())")
            let startTime = DispatchTime.now()

            if mediaType == .image {
                FilesSyncHelper.insertContentIntoDB(uri: MediaStore.Images.Media.INTERNAL_CONTENT_URI, syncedFolder: syncedFolder, lastCheckTimestampMs: lastCheckTimestampMs)
                FilesSyncHelper.insertContentIntoDB(uri: MediaStore.Images.Media.EXTERNAL_CONTENT_URI, syncedFolder: syncedFolder, lastCheckTimestampMs: lastCheckTimestampMs)
            } else if mediaType == .video {
                FilesSyncHelper.insertContentIntoDB(uri: MediaStore.Video.Media.INTERNAL_CONTENT_URI, syncedFolder: syncedFolder, lastCheckTimestampMs: lastCheckTimestampMs)
                FilesSyncHelper.insertContentIntoDB(uri: MediaStore.Video.Media.EXTERNAL_CONTENT_URI, syncedFolder: syncedFolder, lastCheckTimestampMs: lastCheckTimestampMs)
            } else {
                let filesystemDataProvider = FilesystemDataProvider(contentResolver: contentResolver)
                let path = URL(fileURLWithPath: syncedFolder.getLocalPath())
                FilesSyncHelper.insertCustomFolderIntoDB(path: path, syncedFolder: syncedFolder, filesystemDataProvider: filesystemDataProvider, lastCheck: lastCheckTimestampMs)
            }

            let endTime = DispatchTime.now()
            let elapsedTime = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
            Log_OC.d(TAG, "File-sync finished full check for custom folder \(syncedFolder.getLocalPath()) within \(elapsedTime)ns")
        }
    }

    static func insertChangedEntries(syncedFolder: SyncedFolder, changedFiles: [String]) {
        let contentResolver = MainApp.getAppContext().contentResolver
        let filesystemDataProvider = FilesystemDataProvider(contentResolver: contentResolver)
        for changedFileURI in changedFiles {
            if let changedFile = getFileFromURI(uri: changedFileURI) {
                let file = File(path: changedFile)
                filesystemDataProvider.storeOrUpdateFileValue(filePath: changedFile, lastModified: file.lastModified, isDirectory: file.isDirectory, syncedFolder: syncedFolder)
            }
        }
    }

    private static func getFileFromURI(uri: String) -> String? {
        guard let context = MainApp.getAppContext() else { return nil }

        let projection = [kUTTypeData as String]
        let contentUri = URL(string: uri)
        var filePath: String? = nil

        if let contentUri = contentUri {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Media")
            fetchRequest.predicate = NSPredicate(format: "uri == %@", contentUri.absoluteString)
            fetchRequest.propertiesToFetch = projection

            do {
                if let results = try context.fetch(fetchRequest) as? [NSManagedObject], let firstResult = results.first {
                    filePath = firstResult.value(forKey: kUTTypeData as String) as? String
                }
            } catch {
                print("Failed to fetch file path: \(error)")
            }
        }

        return filePath
    }

    private static func insertContentIntoDB(uri: Uri, syncedFolder: SyncedFolder, lastCheckTimestampMs: Int64) {
        let context = MainApp.getAppContext()
        let contentResolver = context.contentResolver

        var cursor: Cursor?
        var column_index_data: Int
        var column_index_date_modified: Int

        let filesystemDataProvider = FilesystemDataProvider(contentResolver: contentResolver)

        var contentPath: String
        var isFolder: Bool

        let projection = [MediaStore.MediaColumns.DATA, MediaStore.MediaColumns.DATE_MODIFIED]

        var path = syncedFolder.getLocalPath()
        if !path.hasSuffix(PATH_SEPARATOR) {
            path += PATH_SEPARATOR
        }
        path += "%"

        let enabledTimestampMs = syncedFolder.getEnabledTimestampMs()

        cursor = context.contentResolver.query(uri, projection, MediaStore.MediaColumns.DATA + " LIKE ?", [path], nil)

        if let cursor = cursor {
            column_index_data = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
            column_index_date_modified = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            while cursor.moveToNext() {
                contentPath = cursor.getString(column_index_data)
                isFolder = File(contentPath).isDirectory()

                if syncedFolder.getLastScanTimestampMs() != SyncedFolder.NOT_SCANNED_YET && cursor.getLong(column_index_date_modified) < (lastCheckTimestampMs / 1000) {
                    continue
                }

                if syncedFolder.isExisting() || cursor.getLong(column_index_date_modified) >= enabledTimestampMs / 1000 {
                    filesystemDataProvider.storeOrUpdateFileValue(contentPath: contentPath, dateModified: cursor.getLong(column_index_date_modified), isFolder: isFolder, syncedFolder: syncedFolder)
                }
            }
            cursor.close()
        }
    }

    static func restartUploadsIfNeeded(uploadsStorageManager: UploadsStorageManager, accountManager: UserAccountManager, connectivityService: ConnectivityService, powerManagementService: PowerManagementService) {
        DispatchQueue.global().async {
            FileUploadHelper.instance().retryFailedUploads(uploadsStorageManager: uploadsStorageManager, connectivityService: connectivityService, accountManager: accountManager, powerManagementService: powerManagementService)
        }
    }

    static func scheduleFilesSyncForAllFoldersIfNeeded(context: Context?, syncedFolderProvider: SyncedFolderProvider, jobManager: BackgroundJobManager) {
        for syncedFolder in syncedFolderProvider.getSyncedFolders() {
            if syncedFolder.isEnabled() {
                jobManager.schedulePeriodicFilesSyncJob(syncedFolder.getId())
            }
        }
        if context != nil {
            jobManager.scheduleContentObserverJob()
        }
    }

    public static func startFilesSyncForAllFolders(syncedFolderProvider: SyncedFolderProvider, jobManager: BackgroundJobManager, overridePowerSaving: Bool, changedFiles: [String]) {
        for syncedFolder in syncedFolderProvider.getSyncedFolders() {
            if syncedFolder.isEnabled() {
                jobManager.startImmediateFilesSyncJob(syncedFolder.getId(), overridePowerSaving: overridePowerSaving, changedFiles: changedFiles)
            }
        }
    }

    static func calculateScanInterval(syncedFolder: SyncedFolder, connectivityService: ConnectivityService, powerManagementService: PowerManagementService) -> Int64 {
        let defaultInterval = BackgroundJobManagerImpl.DEFAULT_PERIODIC_JOB_INTERVAL_MINUTES * 1000 * 60
        if !connectivityService.isConnected() || connectivityService.isInternetWalled() {
            return defaultInterval * 2
        }

        if syncedFolder.isWifiOnly() && !connectivityService.getConnectivity().isWifi() {
            return defaultInterval * 4
        }

        if powerManagementService.getBattery().getLevel() < 80 {
            return defaultInterval * 2
        }

        if powerManagementService.getBattery().getLevel() < 50 {
            return defaultInterval * 4
        }

        if powerManagementService.getBattery().getLevel() < 20 {
            return defaultInterval * 8
        }

        return defaultInterval
    }
}
