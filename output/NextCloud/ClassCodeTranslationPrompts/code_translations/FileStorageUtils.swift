
import Foundation

final class FileStorageUtils {
    private static let TAG = String(describing: FileStorageUtils.self)
    
    private static let PATTERN_YYYY_MM = "yyyy/MM/"
    private static let PATTERN_YYYY = "yyyy/"
    private static let PATTERN_YYYY_MM_DD = "yyyy/MM/dd/"
    private static let DEFAULT_FALLBACK_STORAGE_PATH = "/storage/sdcard0"
    
    private init() {
        // utility class -> private constructor
    }
    
    static func getSavePath(accountName: String) -> String {
        let storagePath = MainApp.getStoragePath()
        let dataFolder = MainApp.getDataFolder()
        let encodedAccountName = accountName.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? accountName
        return "\(storagePath)/\(dataFolder)/\(encodedAccountName)"
    }
    
    static func getDefaultSavePathFor(accountName: String, file: OCFile) -> String {
        return getSavePath(accountName: accountName) + file.getDecryptedRemotePath()
    }
    
    static func getTemporalPath(accountName: String) -> String {
        return MainApp.getStoragePath()
            + "/"
            + MainApp.getDataFolder()
            + "/"
            + "tmp"
            + "/"
            + accountName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
    }
    
    static func getTemporalEncryptedFolderPath(accountName: String) -> String {
        let appContext = MainApp.getAppContext()
        let filesDir = appContext.filesDir
        let path = filesDir.appendingPathComponent(accountName).appendingPathComponent("temp_encrypted_folder")
        return path.path
    }
    
    static func getInternalTemporalPath(accountName: String, context: Context) -> String {
        let filesDir = context.filesDir
        let dataFolder = MainApp.getDataFolder()
        let encodedAccountName = accountName.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? accountName
        return "\(filesDir)/\(dataFolder)/tmp/\(encodedAccountName)"
    }
    
    static func getUsableSpace() -> Int64 {
        let savePath = URL(fileURLWithPath: MainApp.getStoragePath())
        do {
            let values = try savePath.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }
    
    private static func getSubPathFromDate(date: Int64, currentLocale: Locale, subFolderRule: SubFolderRule) -> String {
        if date == 0 {
            return ""
        }
        var datePattern = ""
        switch subFolderRule {
        case .YEAR:
            datePattern = PATTERN_YYYY
        case .YEAR_MONTH:
            datePattern = PATTERN_YYYY_MM
        case .YEAR_MONTH_DAY:
            datePattern = PATTERN_YYYY_MM_DD
        }
        
        let d = Date(timeIntervalSince1970: TimeInterval(date) / 1000)
        let df = DateFormatter()
        df.dateFormat = datePattern
        df.locale = currentLocale
        df.timeZone = TimeZone.current
        
        return df.string(from: d)
    }
    
    static func getInstantUploadFilePath(file: URL, current: Locale, remotePath: String, syncedFolderLocalPath: String, dateTaken: TimeInterval, subfolderByDate: Bool, subFolderRule: SubFolderRule) -> String {
        var subfolderByDatePath = ""
        if subfolderByDate {
            subfolderByDatePath = getSubPathFromDate(date: Int64(dateTaken), currentLocale: current, subFolderRule: subFolderRule)
        }
        
        let parentFile = URL(fileURLWithPath: file.path.replacingOccurrences(of: syncedFolderLocalPath, with: "")).deletingLastPathComponent()
        
        var relativeSubfolderPath = ""
        if parentFile.path.isEmpty {
            print("AutoUpload: Parent folder does not exist!")
        } else {
            relativeSubfolderPath = parentFile.path
        }
        
        let pathSeparator = "/"
        let fullPath = remotePath + pathSeparator + subfolderByDatePath + pathSeparator + relativeSubfolderPath + pathSeparator + file.lastPathComponent
        return fullPath.replacingOccurrences(of: pathSeparator + "+", with: pathSeparator, options: .regularExpression)
    }
    
    static func getParentPath(remotePath: String) -> String? {
        let parentPath = URL(fileURLWithPath: remotePath).deletingLastPathComponent().path
        if !parentPath.isEmpty {
            return parentPath.hasSuffix(OCFile.PATH_SEPARATOR) ? parentPath : parentPath + OCFile.PATH_SEPARATOR
        }
        return nil
    }
    
    static func fillOCFile(remote: RemoteFile) -> OCFile {
        let file = OCFile(remotePath: remote.getRemotePath())
        file.setDecryptedRemotePath(remote.getRemotePath())
        file.setCreationTimestamp(remote.getCreationTimestamp())
        if MimeType.DIRECTORY.caseInsensitiveCompare(remote.getMimeType()) == .orderedSame {
            file.setFileLength(remote.getSize())
        } else {
            file.setFileLength(remote.getLength())
        }
        file.setMimeType(remote.getMimeType())
        file.setModificationTimestamp(remote.getModifiedTimestamp())
        file.setEtag(remote.getEtag())
        file.setPermissions(remote.getPermissions())
        file.setRemoteId(remote.getRemoteId())
        file.setLocalId(remote.getLocalId())
        file.setFavorite(remote.isFavorite())
        if file.isFolder() {
            file.setEncrypted(remote.isEncrypted())
        }
        file.setMountType(remote.getMountType())
        file.setPreviewAvailable(remote.isHasPreview())
        file.setUnreadCommentsCount(remote.getUnreadCommentsCount())
        file.setOwnerId(remote.getOwnerId())
        file.setOwnerDisplayName(remote.getOwnerDisplayName())
        file.setNote(remote.getNote())
        file.setSharees(Array(remote.getSharees()))
        file.setRichWorkspace(remote.getRichWorkspace())
        file.setLocked(remote.isLocked())
        file.setLockType(remote.getLockType())
        file.setLockOwnerId(remote.getLockOwner())
        file.setLockOwnerDisplayName(remote.getLockOwnerDisplayName())
        file.setLockOwnerEditor(remote.getLockOwnerEditor())
        file.setLockTimestamp(remote.getLockTimestamp())
        file.setLockTimeout(remote.getLockTimeout())
        file.setLockToken(remote.getLockToken())
        file.setTags(Array(remote.getTags()))
        file.setImageDimension(remote.getImageDimension())
        file.setGeoLocation(remote.getGeoLocation())
        file.setLivePhoto(remote.getLivePhoto())
        file.setHidden(remote.getHidden())
        
        return file
    }
    
    static func fillRemoteFile(ocFile: OCFile) -> RemoteFile {
        let file = RemoteFile(remotePath: ocFile.getRemotePath())
        file.setCreationTimestamp(ocFile.getCreationTimestamp())
        file.setLength(ocFile.getFileLength())
        file.setMimeType(ocFile.getMimeType())
        file.setModifiedTimestamp(ocFile.getModificationTimestamp())
        file.setEtag(ocFile.getEtag())
        file.setPermissions(ocFile.getPermissions())
        file.setRemoteId(ocFile.getRemoteId())
        file.setFavorite(ocFile.isFavorite())
        return file
    }
    
    static func sortOcFolderDescDateModifiedWithoutFavoritesFirst(files: [OCFile]) -> [OCFile] {
        let sortedFiles = files.sorted {
            return $0.modificationTimestamp > $1.modificationTimestamp
        }
        return sortedFiles
    }
    
    static func sortOcFolderDescDateModified(_ files: [OCFile]) -> [OCFile] {
        var sortedFiles = sortOcFolderDescDateModifiedWithoutFavoritesFirst(files: files)
        return FileSortOrder.sortCloudFilesByFavourite(sortedFiles)
    }
    
    static func getFolderSize(_ dir: URL) -> Int64 {
        var result: Int64 = 0
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) {
            for file in files {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        result += getFolderSize(file)
                    } else {
                        if let fileSize = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64 {
                            result += fileSize
                        }
                    }
                }
            }
        }
        return result
    }
    
    static func getMimeTypeFromName(_ path: String) -> String {
        let extensionStartIndex = path.lastIndex(of: ".") ?? path.endIndex
        let fileExtension = String(path[path.index(after: extensionStartIndex)...])
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension as CFString, nil)?.takeRetainedValue(),
           let mimeType = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
            return mimeType as String
        }
        return ""
    }
    
    static func searchForLocalFileInDefaultPath(file: OCFile, accountName: String) {
        if (file.storagePath == nil || !FileManager.default.fileExists(atPath: file.storagePath!)) && !file.isFolder {
            let filePath = FileStorageUtils.getDefaultSavePathFor(accountName: accountName, file: file)
            let fileURL = URL(fileURLWithPath: filePath)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                file.storagePath = fileURL.path
                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let modificationDate = attributes[.modificationDate] as? Date {
                    file.setLastSyncDateForData(modificationDate)
                }
            }
        }
    }
    
    static func copyFile(src: URL, target: URL) -> Bool {
        var ret = true
        
        do {
            let inStream = InputStream(url: src)!
            let outStream = OutputStream(url: target, append: false)!
            inStream.open()
            outStream.open()
            
            defer {
                inStream.close()
                outStream.close()
            }
            
            let bufferSize = 1024
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            
            while inStream.hasBytesAvailable {
                let bytesRead = inStream.read(&buffer, maxLength: bufferSize)
                if bytesRead > 0 {
                    outStream.write(buffer, maxLength: bytesRead)
                } else {
                    break
                }
            }
        } catch {
            ret = false
        }
        
        return ret
    }
    
    static func moveFile(sourceFile: URL, targetFile: URL) -> Bool {
        do {
            try FileManager.default.copyItem(at: sourceFile, to: targetFile)
            try FileManager.default.removeItem(at: sourceFile)
            return true
        } catch {
            return false
        }
    }
    
    static func copyDirs(sourceFolder: URL, targetFolder: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return false
        }
        
        guard let listFiles = try? FileManager.default.contentsOfDirectory(at: sourceFolder, includingPropertiesForKeys: nil, options: []) else {
            return false
        }
        
        for file in listFiles {
            let targetFile = targetFolder.appendingPathComponent(file.lastPathComponent)
            if file.hasDirectoryPath {
                if !copyDirs(sourceFolder: file, targetFolder: targetFile) {
                    return false
                }
            } else {
                if !copyFile(src: file, target: targetFile) {
                    return false
                }
            }
        }
        
        return true
    }
    
    static func deleteRecursively(file: URL, storageManager: FileDataStorageManager) {
        if let isDirectory = try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory {
            if let listFiles = try? FileManager.default.contentsOfDirectory(at: file, includingPropertiesForKeys: nil, options: []) {
                for child in listFiles {
                    deleteRecursively(file: child, storageManager: storageManager)
                }
            }
        }
        
        storageManager.deleteFileInMediaScan(file.path)
        try? FileManager.default.removeItem(at: file)
    }
    
    static func deleteRecursive(file: URL) -> Bool {
        var res = true
        
        if let isDirectory = try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory {
            if let listFiles = try? FileManager.default.contentsOfDirectory(at: file, includingPropertiesForKeys: nil, options: []) {
                for c in listFiles {
                    res = deleteRecursive(file: c) && res
                }
            } else {
                return true
            }
        }
        
        do {
            try FileManager.default.removeItem(at: file)
            return res
        } catch {
            return false
        }
    }
    
    static func checkIfFileFinishedSaving(file: OCFile) {
        var lastModified: TimeInterval = 0
        var lastSize: UInt64 = 0
        let realFile = URL(fileURLWithPath: file.getStoragePath())
        
        if let attributes = try? FileManager.default.attributesOfItem(atPath: realFile.path),
           let modificationDate = attributes[.modificationDate] as? Date,
           let fileSize = attributes[.size] as? UInt64,
           modificationDate.timeIntervalSince1970 != file.getModificationTimestamp() && fileSize != file.getFileLength() {
            
            while let currentAttributes = try? FileManager.default.attributesOfItem(atPath: realFile.path),
                  let currentModificationDate = currentAttributes[.modificationDate] as? Date,
                  let currentFileSize = currentAttributes[.size] as? UInt64,
                  currentModificationDate.timeIntervalSince1970 != lastModified && currentFileSize != lastSize {
                
                lastModified = currentModificationDate.timeIntervalSince1970
                lastSize = currentFileSize
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }
    
    static func checkEncryptionStatus(file: OCFile, storageManager: FileDataStorageManager) -> Bool {
        if file.isEncrypted() {
            return true
        }
        
        var currentFile: OCFile? = file
        while currentFile != nil && currentFile?.decryptedRemotePath != OCFile.ROOT_PATH {
            if currentFile!.isEncrypted() {
                return true
            }
            currentFile = storageManager.getFileById(currentFile!.parentId)
        }
        return false
    }
    
    static func getStorageDirectories(context: AnyObject) -> [String] {
        var rv: [String] = []
        let rawExternalStorage = ProcessInfo.processInfo.environment["EXTERNAL_STORAGE"]
        let rawSecondaryStoragesStr = ProcessInfo.processInfo.environment["SECONDARY_STORAGE"]
        let rawEmulatedStorageTarget = ProcessInfo.processInfo.environment["EMULATED_STORAGE_TARGET"]
        
        if rawEmulatedStorageTarget?.isEmpty ?? true {
            if rawExternalStorage?.isEmpty ?? true {
                let defaultFallbackStoragePath = "/storage/sdcard0"
                if FileManager.default.fileExists(atPath: defaultFallbackStoragePath) {
                    rv.append(defaultFallbackStoragePath)
                } else {
                    rv.append(NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? "")
                }
            } else {
                rv.append(rawExternalStorage!)
            }
        } else {
            let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
            let folders = path.split(separator: "/")
            let lastFolder = folders.last ?? ""
            let isDigit = Int(lastFolder) != nil
            let rawUserId = isDigit ? String(lastFolder) : ""
            
            if rawUserId.isEmpty {
                rv.append(rawEmulatedStorageTarget!)
            } else {
                rv.append(rawEmulatedStorageTarget! + "/" + rawUserId)
            }
        }
        
        if let rawSecondaryStoragesStr = rawSecondaryStoragesStr, !rawSecondaryStoragesStr.isEmpty {
            let rawSecondaryStorages = rawSecondaryStoragesStr.split(separator: ":")
            rv.append(contentsOf: rawSecondaryStorages.map { String($0) })
        }
        
        if checkStoragePermission(context: context) {
            rv.removeAll()
        }
        
        let extSdCardPaths = getExtSdCardPathsForActivity(context: context)
        for extSdCardPath in extSdCardPaths {
            let f = URL(fileURLWithPath: extSdCardPath)
            if !rv.contains(extSdCardPath) && canListFiles(file: f) {
                rv.append(extSdCardPath)
            }
        }
        
        return rv
    }
    
    static func pathToUserFriendlyDisplay(path: String, context: Context, resources: Resources) -> String {
        var storageDevice: String? = nil
        for storageDirectory in FileStorageUtils.getStorageDirectories(context: context) {
            if path.hasPrefix(storageDirectory) {
                storageDevice = storageDirectory
                break
            }
        }
        
        if storageDevice == nil {
            return path
        }
        
        var storageFolder: String
        do {
            let startIndex = path.index(path.startIndex, offsetBy: storageDevice!.count + 1)
            storageFolder = String(path[startIndex...])
        } catch {
            storageFolder = ""
        }
        
        if let standardDirectory = FileStorageUtils.StandardDirectory.fromPath(storageFolder) {
            storageFolder = " " + resources.getString(standardDirectory.getDisplayName())
        }
        
        if storageDevice!.hasPrefix(Environment.getExternalStorageDirectory().absolutePath) {
            storageDevice = resources.getString(R.string.storage_internal_storage)
        } else {
            storageDevice = URL(fileURLWithPath: storageDevice!).lastPathComponent
        }
        
        return resources.getString(R.string.local_folder_friendly_path, storageDevice!, storageFolder)
    }
    
    private static func checkStoragePermission(context: Context) -> Bool {
        return context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
    }
    
    private static func getExtSdCardPathsForActivity(context: Context) -> [String] {
        var paths: [String] = []
        if let externalFilesDirs = context.getExternalFilesDirs(type: "external") {
            for file in externalFilesDirs {
                if let file = file {
                    let pathString = file.absolutePath
                    if let index = pathString.range(of: "/Android/data")?.lowerBound {
                        var path = String(pathString[..<index])
                        do {
                            path = try FileManager.default.destinationOfSymbolicLink(atPath: path)
                        } catch {
                            // Keep non-canonical path.
                        }
                        paths.append(path)
                    } else {
                        print("Unexpected external file dir: \(pathString)")
                    }
                }
            }
        }
        if paths.isEmpty {
            paths.append("/storage/sdcard1")
        }
        return paths
    }
    
    private static func canListFiles(file: URL) -> Bool {
        return FileManager.default.isReadableFile(atPath: file.path) && (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
    
    static func checkIfEnoughSpace(file: OCFile) -> Bool {
        let availableSpaceOnDevice = FileOperationsHelper.getAvailableSpaceOnDevice()
        
        if availableSpaceOnDevice == -1 {
            fatalError("Error while computing available space")
        }
        
        return checkIfEnoughSpace(availableSpaceOnDevice: availableSpaceOnDevice, file: file)
    }
    
    static func checkIfEnoughSpace(availableSpaceOnDevice: Int64, file: OCFile) -> Bool {
        if file.isFolder() {
            return availableSpaceOnDevice > (file.getFileLength() - localFolderSize(file: file))
        } else {
            return availableSpaceOnDevice > file.getFileLength()
        }
    }
    
    private static func localFolderSize(file: OCFile) -> Int64 {
        if file.getStoragePath() == nil {
            return 0
        } else {
            return FileStorageUtils.getFolderSize(URL(fileURLWithPath: file.getStoragePath()!))
        }
    }
    
    class StandardDirectory {
        static let PICTURES = StandardDirectory(
            name: Environment.DIRECTORY_PICTURES,
            displayNameResource: R.string.storage_pictures,
            iconResource: R.drawable.ic_image_grey600
        )
        static let CAMERA = StandardDirectory(
            name: Environment.DIRECTORY_DCIM,
            displayNameResource: R.string.storage_camera,
            iconResource: R.drawable.ic_camera
        )
        
        static let DOCUMENTS: StandardDirectory? = {
            if #available(iOS 11.0, *) {
                return StandardDirectory(
                    name: Environment.DIRECTORY_DOCUMENTS,
                    displayNameResource: R.string.storage_documents,
                    iconResource: R.drawable.ic_document_grey600
                )
            }
            return nil
        }()
        
        static let DOWNLOADS = StandardDirectory(
            name: Environment.DIRECTORY_DOWNLOADS,
            displayNameResource: R.string.storage_downloads,
            iconResource: R.drawable.ic_download_grey600
        )
        static let MOVIES = StandardDirectory(
            name: Environment.DIRECTORY_MOVIES,
            displayNameResource: R.string.storage_movies,
            iconResource: R.drawable.ic_movie_grey600
        )
        static let MUSIC = StandardDirectory(
            name: Environment.DIRECTORY_MUSIC,
            displayNameResource: R.string.storage_music,
            iconResource: R.drawable.ic_music_grey600
        )
        
        private let name: String
        private let displayNameResource: Int
        private let iconResource: Int
        
        private init(name: String, displayNameResource: Int, iconResource: Int) {
            self.name = name
            self.displayNameResource = displayNameResource
            self.iconResource = iconResource
        }
        
        func getName() -> String {
            return self.name
        }
        
        func getDisplayName() -> Int {
            return self.displayNameResource
        }
        
        func getIcon() -> Int {
            return self.iconResource
        }
        
        static func getStandardDirectories() -> Set<StandardDirectory> {
            var standardDirectories: Set<StandardDirectory> = []
            standardDirectories.insert(PICTURES)
            standardDirectories.insert(CAMERA)
            if let documents = DOCUMENTS {
                standardDirectories.insert(documents)
            }
            standardDirectories.insert(DOWNLOADS)
            standardDirectories.insert(MOVIES)
            standardDirectories.insert(MUSIC)
            return standardDirectories
        }
        
        static func fromPath(_ path: String) -> StandardDirectory? {
            for directory in getStandardDirectories() {
                if directory.getName() == path {
                    return directory
                }
            }
            return nil
        }
    }
}
