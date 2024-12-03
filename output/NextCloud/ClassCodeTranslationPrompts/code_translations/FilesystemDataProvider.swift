
import Foundation

class FilesystemDataProvider {
    
    private let TAG = "FilesystemDataProvider"
    private var contentResolver: ContentResolver
    
    init(contentResolver: ContentResolver) {
        guard contentResolver != nil else {
            fatalError("Cannot create an instance with a NULL contentResolver")
        }
        self.contentResolver = contentResolver
    }
    
    func deleteAllEntriesForSyncedFolder(syncedFolderId: String) -> Int {
        let contentUri = ProviderMeta.ProviderTableMeta.CONTENT_URI_FILESYSTEM
        let selection = "\(ProviderMeta.ProviderTableMeta.FILESYSTEM_SYNCED_FOLDER_ID) = ?"
        let selectionArgs = [syncedFolderId]
        return contentResolver.delete(contentUri, selection: selection, selectionArgs: selectionArgs)
    }
    
    func updateFilesystemFileAsSentForUpload(path: String, syncedFolderId: String) {
        var cv = [String: Any]()
        cv[ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_SENT_FOR_UPLOAD] = 1
        
        let selection = "\(ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_LOCAL_PATH) = ? and \(ProviderMeta.ProviderTableMeta.FILESYSTEM_SYNCED_FOLDER_ID) = ?"
        let selectionArgs = [path, syncedFolderId]
        
        contentResolver.update(
            ProviderMeta.ProviderTableMeta.CONTENT_URI_FILESYSTEM,
            values: cv,
            selection: selection,
            selectionArgs: selectionArgs
        )
    }
    
    func getFilesForUpload(localPath: String, syncedFolderId: String) -> Set<String> {
        var localPathsToUpload = Set<String>()
        
        let likeParam = localPath + "%"
        
        let cursor = contentResolver.query(
            ProviderMeta.ProviderTableMeta.CONTENT_URI_FILESYSTEM,
            projection: nil,
            selection: "\(ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_LOCAL_PATH) LIKE ? and " +
                       "\(ProviderMeta.ProviderTableMeta.FILESYSTEM_SYNCED_FOLDER_ID) = ? and " +
                       "\(ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_SENT_FOR_UPLOAD) = ? and " +
                       "\(ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_IS_FOLDER) = ?",
            selectionArgs: [likeParam, syncedFolderId, "0", "0"],
            sortOrder: nil
        )
        
        if let cursor = cursor {
            if cursor.moveToFirst() {
                repeat {
                    if let value = cursor.getString(cursor.getColumnIndexOrThrow(ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_LOCAL_PATH)) {
                        let file = File(value)
                        if !file.exists() {
                            Log_OC.d(TAG, "Ignoring file for upload (doesn't exist): \(value)")
                        } else if !SyncedFolderUtils.isQualifiedFolder(file.parent) {
                            Log_OC.d(TAG, "Ignoring file for upload (unqualified folder): \(value)")
                        } else if !SyncedFolderUtils.isFileNameQualifiedForAutoUpload(file.name) {
                            Log_OC.d(TAG, "Ignoring file for upload (unqualified file): \(value)")
                        } else {
                            localPathsToUpload.insert(value)
                        }
                    } else {
                        Log_OC.e(TAG, "Cannot get local path")
                    }
                } while cursor.moveToNext()
            }
            
            cursor.close()
        }
        
        return localPathsToUpload
    }
    
    func storeOrUpdateFileValue(localPath: String, modifiedAt: Int64, isFolder: Bool, syncedFolder: SyncedFolder) {
        let data = getFilesystemDataSet(localPathParam: localPath, syncedFolder: syncedFolder)
        
        let isFolderValue = isFolder ? 1 : 0
        
        var cv: [String: Any] = [:]
        cv[ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_FOUND_RECENTLY] = Date().timeIntervalSince1970 * 1000
        cv[ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_MODIFIED] = modifiedAt
        
        if data == nil {
            cv[ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_LOCAL_PATH] = localPath
            cv[ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_IS_FOLDER] = isFolderValue
            cv[ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_SENT_FOR_UPLOAD] = false
            cv[ProviderMeta.ProviderTableMeta.FILESYSTEM_SYNCED_FOLDER_ID] = syncedFolder.getId()
            
            let newCrc32 = getFileChecksum(filepath: localPath)
            if newCrc32 != -1 {
                cv[ProviderMeta.ProviderTableMeta.FILESYSTEM_CRC32] = String(newCrc32)
            }
            
            let result = contentResolver.insert(uri: ProviderMeta.ProviderTableMeta.CONTENT_URI_FILESYSTEM, values: cv)
            
            if result == nil {
                Log_OC.v(TAG, "Failed to insert filesystem data with local path: \(localPath)")
            }
        } else {
            if data!.getModifiedAt() != modifiedAt {
                let newCrc32 = getFileChecksum(filepath: localPath)
                if data!.getCrc32() == nil || (newCrc32 != -1 && data!.getCrc32() != String(newCrc32)) {
                    cv[ProviderMeta.ProviderTableMeta.FILESYSTEM_CRC32] = String(newCrc32)
                    cv[ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_SENT_FOR_UPLOAD] = 0
                }
            }
            
            let result = contentResolver.update(
                uri: ProviderMeta.ProviderTableMeta.CONTENT_URI_FILESYSTEM,
                values: cv,
                whereClause: "\(ProviderMeta.ProviderTableMeta._ID)=?",
                whereArgs: [String(data!.getId())]
            )
            
            if result == 0 {
                Log_OC.v(TAG, "Failed to update filesystem data with local path: \(localPath)")
            }
        }
    }
    
    private func getFilesystemDataSet(localPathParam: String, syncedFolder: SyncedFolder) -> FileSystemDataSet? {
        let contentUri = ProviderMeta.ProviderTableMeta.CONTENT_URI_FILESYSTEM
        let selection = "\(ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_LOCAL_PATH) = ? and \(ProviderMeta.ProviderTableMeta.FILESYSTEM_SYNCED_FOLDER_ID) = ?"
        let selectionArgs = [localPathParam, String(syncedFolder.getId())]
        
        var dataSet: FileSystemDataSet? = nil
        let cursor = contentResolver.query(contentUri, null, selection, selectionArgs, null)
        
        if let cursor = cursor {
            if cursor.moveToFirst() {
                let id = cursor.getInt(cursor.getColumnIndexOrThrow(ProviderMeta.ProviderTableMeta._ID))
                let localPath = cursor.getString(cursor.getColumnIndexOrThrow(ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_LOCAL_PATH))
                let modifiedAt = cursor.getLong(cursor.getColumnIndexOrThrow(ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_MODIFIED))
                let isFolder = cursor.getInt(cursor.getColumnIndexOrThrow(ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_IS_FOLDER)) != 0
                let foundAt = cursor.getLong(cursor.getColumnIndexOrThrow(ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_FOUND_RECENTLY))
                let isSentForUpload = cursor.getInt(cursor.getColumnIndexOrThrow(ProviderMeta.ProviderTableMeta.FILESYSTEM_FILE_SENT_FOR_UPLOAD)) != 0
                let crc32 = cursor.getString(cursor.getColumnIndexOrThrow(ProviderMeta.ProviderTableMeta.FILESYSTEM_CRC32))
                
                if id == -1 {
                    Log_OC.e(TAG, "Arbitrary value could not be created from cursor")
                } else {
                    dataSet = FileSystemDataSet(id: id, localPath: localPath, modifiedAt: modifiedAt, isFolder: isFolder, isSentForUpload: isSentForUpload, foundAt: foundAt, syncedFolderId: syncedFolder.getId(), crc32: crc32)
                }
            }
            cursor.close()
        } else {
            Log_OC.e(TAG, "DB error restoring arbitrary values.")
        }
        
        return dataSet
    }
    
    private func getFileChecksum(filepath: String) -> UInt64 {
        do {
            let fileInputStream = try FileInputStream(filepath: filepath)
            defer { fileInputStream.close() }
            let inputStream = BufferedInputStream(fileInputStream: fileInputStream)
            defer { inputStream.close() }
            
            var crc = CRC32()
            var buf = [UInt8](repeating: 0, count: 1024 * 64)
            while true {
                let size = inputStream.read(&buf, maxLength: buf.count)
                if size <= 0 { break }
                crc.update(buffer: buf, offset: 0, length: size)
            }
            
            return crc.value
        } catch {
            return UInt64.max
        }
    }
}
