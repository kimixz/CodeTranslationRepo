
import Foundation

class UploadsStorageManager: Observable {
    private static let TAG = String(describing: UploadsStorageManager.self)
    
    private static let IS_EQUAL = "== ?"
    private static let EQUAL = "=="
    private static let OR = " OR "
    private static let AND = " AND "
    private static let ANGLE_BRACKETS = "<>"
    private static let SINGLE_RESULT = 1
    
    private static let QUERY_PAGE_SIZE: Int64 = 100
    
    private let contentResolver: ContentResolver
    private let currentAccountProvider: CurrentAccountProvider
    private var capability: OCCapability?
    
    init(currentAccountProvider: CurrentAccountProvider, contentResolver: ContentResolver) {
        guard contentResolver != nil else {
            fatalError("Cannot create an instance with a NULL contentResolver")
        }
        self.contentResolver = contentResolver
        self.currentAccountProvider = currentAccountProvider
    }
    
    private func initOCCapability() {
        do {
            self.capability = try CapabilityUtils.getCapability(MainApp.getAppContext())
        } catch {
            Log_OC.e(UploadsStorageManager.TAG, "Failed to set OCCapability: Dependencies are not yet ready.")
        }
    }
    
    func storeUpload(_ ocUpload: OCUpload) -> Int64 {
        if let existingUpload = getPendingCurrentOrFailedUpload(ocUpload) {
            print("Will update upload in db since \(ocUpload.getLocalPath()) already exists as pending, current or failed upload")
            let existingId = existingUpload.getUploadId()
            ocUpload.setUploadId(existingId)
            updateUpload(ocUpload)
            return existingId
        }
        
        print("Inserting \(ocUpload.getLocalPath()) with status=\(ocUpload.getUploadStatus())")
        
        let cv = getContentValues(ocUpload)
        let result = getDB().insert(ProviderTableMeta.CONTENT_URI_UPLOADS, cv)
        
        print("storeUpload returns with: \(String(describing: result)) for file: \(ocUpload.getLocalPath())")
        if result == nil {
            print("Failed to insert item \(ocUpload.getLocalPath()) into upload db.")
            return -1
        } else {
            let newId = Int64(result!.pathComponents[1])!
            ocUpload.setUploadId(newId)
            notifyObserversNow()
            
            return newId
        }
    }
    
    func storeUploads(_ ocUploads: [OCUpload]) -> [Int64]? {
        Log_OC.v(UploadsStorageManager.TAG, "Inserting \(ocUploads.count) uploads")
        var operations: [ContentProviderOperation] = []
        
        for ocUpload in ocUploads {
            if let existingUpload = getPendingCurrentOrFailedUpload(ocUpload) {
                Log_OC.v(UploadsStorageManager.TAG, "Will update upload in db since \(ocUpload.localPath) already exists as pending, current or failed upload")
                ocUpload.uploadId = existingUpload.uploadId
                updateUpload(ocUpload)
                continue
            }
            
            let operation = ContentProviderOperation.newInsert(ProviderTableMeta.CONTENT_URI_UPLOADS)
                .withValues(getContentValues(ocUpload))
                .build()
            operations.append(operation)
        }
        
        do {
            let contentProviderResults = try getDB().applyBatch(MainApp.getAuthority(), operations)
            var newIds: [Int64] = Array(repeating: 0, count: ocUploads.count)
            for (i, result) in contentProviderResults.enumerated() {
                let newId = Int64(result.uri.pathSegments[1])!
                ocUploads[i].uploadId = newId
                newIds[i] = newId
            }
            notifyObserversNow()
            return newIds
        } catch {
            Log_OC.e(UploadsStorageManager.TAG, "Error inserting uploads", error)
        }
        
        return nil
    }
    
    private func getContentValues(ocUpload: OCUpload) -> [String: Any] {
        var cv = [String: Any]()
        cv[ProviderTableMeta.UPLOADS_LOCAL_PATH] = ocUpload.getLocalPath()
        cv[ProviderTableMeta.UPLOADS_REMOTE_PATH] = ocUpload.getRemotePath()
        cv[ProviderTableMeta.UPLOADS_ACCOUNT_NAME] = ocUpload.getAccountName()
        cv[ProviderTableMeta.UPLOADS_FILE_SIZE] = ocUpload.getFileSize()
        cv[ProviderTableMeta.UPLOADS_STATUS] = ocUpload.getUploadStatus().value
        cv[ProviderTableMeta.UPLOADS_LOCAL_BEHAVIOUR] = ocUpload.getLocalAction()
        cv[ProviderTableMeta.UPLOADS_NAME_COLLISION_POLICY] = ocUpload.getNameCollisionPolicy().serialize()
        cv[ProviderTableMeta.UPLOADS_IS_CREATE_REMOTE_FOLDER] = ocUpload.isCreateRemoteFolder() ? 1 : 0
        cv[ProviderTableMeta.UPLOADS_LAST_RESULT] = ocUpload.getLastResult().getValue()
        cv[ProviderTableMeta.UPLOADS_CREATED_BY] = ocUpload.getCreatedBy()
        cv[ProviderTableMeta.UPLOADS_IS_WHILE_CHARGING_ONLY] = ocUpload.isWhileChargingOnly() ? 1 : 0
        cv[ProviderTableMeta.UPLOADS_IS_WIFI_ONLY] = ocUpload.isUseWifiOnly() ? 1 : 0
        cv[ProviderTableMeta.UPLOADS_FOLDER_UNLOCK_TOKEN] = ocUpload.getFolderUnlockToken()
        return cv
    }
    
    func updateUpload(_ ocUpload: OCUpload) -> Int {
        Log_OC.v(UploadsStorageManager.TAG, "Updating \(ocUpload.localPath) with status=\(ocUpload.uploadStatus)")
        
        var cv = [String: Any]()
        cv[ProviderTableMeta.UPLOADS_LOCAL_PATH] = ocUpload.localPath
        cv[ProviderTableMeta.UPLOADS_REMOTE_PATH] = ocUpload.remotePath
        cv[ProviderTableMeta.UPLOADS_ACCOUNT_NAME] = ocUpload.accountName
        cv[ProviderTableMeta.UPLOADS_STATUS] = ocUpload.uploadStatus.value
        cv[ProviderTableMeta.UPLOADS_LAST_RESULT] = ocUpload.lastResult.getValue()
        cv[ProviderTableMeta.UPLOADS_UPLOAD_END_TIMESTAMP] = ocUpload.uploadEndTimestamp
        cv[ProviderTableMeta.UPLOADS_FILE_SIZE] = ocUpload.fileSize
        cv[ProviderTableMeta.UPLOADS_FOLDER_UNLOCK_TOKEN] = ocUpload.folderUnlockToken
        
        let result = getDB().update(ProviderTableMeta.CONTENT_URI_UPLOADS,
                                    values: cv,
                                    where: "\(ProviderTableMeta._ID)=?",
                                    whereArgs: [String(ocUpload.uploadId)]
        )
        
        Log_OC.d(UploadsStorageManager.TAG, "updateUpload returns with: \(result) for file: \(ocUpload.localPath)")
        if result != UploadsStorageManager.SINGLE_RESULT {
            Log_OC.e(UploadsStorageManager.TAG, "Failed to update item \(ocUpload.localPath) into upload db.")
        } else {
            notifyObserversNow()
        }
        
        return result
    }
    
    private func updateUploadInternal(cursor: Cursor, status: UploadStatus, result: UploadResult?, remotePath: String, localPath: String?) -> Int {
        var r = 0
        while cursor.moveToNext() {
            // read upload object and update
            let upload = createOCUploadFromCursor(cursor: cursor)
            
            let path = cursor.getString(cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_LOCAL_PATH))
            Log_OC.v(UploadsStorageManager.TAG, "Updating \(path) with status: \(status) and result: \(result?.description ?? "null") (old: \(upload.toFormattedString()))")
            
            upload.setUploadStatus(status: status)
            upload.setLastResult(result: result)
            upload.setRemotePath(remotePath: remotePath)
            if let localPath = localPath {
                upload.setLocalPath(localPath: localPath)
            }
            if status == .UPLOAD_SUCCEEDED {
                upload.setUploadEndTimestamp(timestamp: Calendar.current.timeInMillis())
            }
            
            // store update upload object to db
            r = updateUpload(upload: upload)
        }
        
        return r
    }
    
    private func updateUploadStatus(id: Int64, status: UploadStatus, result: UploadResult, remotePath: String, localPath: String) -> Int {
        var returnValue = 0
        let db = getDB()
        let query = ProviderTableMeta.CONTENT_URI_UPLOADS
        let selection = "\(ProviderTableMeta._ID)=?"
        let selectionArgs = [String(id)]
        
        if let cursor = db.query(query, selection: selection, selectionArgs: selectionArgs, groupBy: nil, having: nil, orderBy: nil) {
            if cursor.count != UploadsStorageManager.SINGLE_RESULT {
                Log_OC.e(UploadsStorageManager.TAG, "\(cursor.count) items for id=\(id) available in UploadDb. Expected 1. Failed to update upload db.")
            } else {
                returnValue = updateUploadInternal(cursor, status: status, result: result, remotePath: remotePath, localPath: localPath)
            }
            cursor.close()
        } else {
            Log_OC.e(UploadsStorageManager.TAG, "Cursor is null")
        }
        
        return returnValue
    }
    
    func notifyObserversNow() {
        Log_OC.d(UploadsStorageManager.TAG, "notifyObserversNow")
        setChanged()
        notifyObservers()
    }
    
    func removeUpload(_ upload: OCUpload?) -> Int {
        if upload == nil {
            return 0
        } else {
            return removeUpload(upload!.getUploadId())
        }
    }
    
    func removeUpload(id: Int64) -> Int {
        let result = getDB().delete(
            ProviderTableMeta.CONTENT_URI_UPLOADS,
            where: "\(ProviderTableMeta._ID)=?",
            args: [String(id)]
        )
        Log_OC.d(UploadsStorageManager.TAG, "delete returns \(result) for upload with id \(id)")
        if result > 0 {
            notifyObserversNow()
        }
        return result
    }
    
    func removeUpload(accountName: String, remotePath: String) -> Int {
        let result = getDB().delete(
            ProviderTableMeta.CONTENT_URI_UPLOADS,
            where: "\(ProviderTableMeta.UPLOADS_ACCOUNT_NAME)=? AND \(ProviderTableMeta.UPLOADS_REMOTE_PATH)=?",
            args: [accountName, remotePath]
        )
        Log_OC.d(UploadsStorageManager.TAG, "delete returns \(result) for file \(remotePath) in \(accountName)")
        if result > 0 {
            notifyObserversNow()
        }
        return result
    }
    
    func removeUploads(accountName: String) -> Int {
        let result = getDB().delete(
            ProviderTableMeta.CONTENT_URI_UPLOADS,
            where: "\(ProviderTableMeta.UPLOADS_ACCOUNT_NAME)=?",
            args: [accountName]
        )
        Log_OC.d(UploadsStorageManager.TAG, "delete returns \(result) for uploads in \(accountName)")
        if result > 0 {
            notifyObserversNow()
        }
        return result
    }
    
    func getAllStoredUploads() -> [OCUpload] {
        return getUploads(nil, nil)
    }
    
    func getPendingCurrentOrFailedUpload(upload: OCUpload) -> OCUpload? {
        let db = getDB()
        let query = ProviderTableMeta.CONTENT_URI_UPLOADS
        let selection = "\(ProviderTableMeta.UPLOADS_REMOTE_PATH)=? AND \(ProviderTableMeta.UPLOADS_LOCAL_PATH)=? AND \(ProviderTableMeta.UPLOADS_ACCOUNT_NAME)=? AND (\(ProviderTableMeta.UPLOADS_STATUS)=? OR \(ProviderTableMeta.UPLOADS_STATUS)=?)"
        let selectionArgs = [
            upload.getRemotePath(),
            upload.getLocalPath(),
            upload.getAccountName(),
            String(UploadStatus.UPLOAD_IN_PROGRESS.rawValue),
            String(UploadStatus.UPLOAD_FAILED.rawValue)
        ]
        let sortOrder = "\(ProviderTableMeta.UPLOADS_REMOTE_PATH) ASC"
        
        if let cursor = db.query(query, selection: selection, selectionArgs: selectionArgs, sortOrder: sortOrder) {
            defer { cursor.close() }
            if cursor.moveToFirst() {
                return createOCUploadFromCursor(cursor)
            }
        }
        return nil
    }
    
    func getUploadByRemotePath(remotePath: String) -> OCUpload? {
        var result: OCUpload? = nil
        let db = getDB()
        let query = ProviderTableMeta.UPLOADS_REMOTE_PATH + "=?"
        let sortOrder = ProviderTableMeta.UPLOADS_REMOTE_PATH + " ASC"
        let cursor = db.query(ProviderTableMeta.CONTENT_URI_UPLOADS, selection: query, selectionArgs: [remotePath], sortOrder: sortOrder)
        
        if let cursor = cursor {
            if cursor.moveToFirst() {
                result = createOCUploadFromCursor(cursor)
            }
        }
        Log_OC.d(UploadsStorageManager.TAG, "Retrieve job \(String(describing: result)) for remote path \(remotePath)")
        return result
    }
    
    func getUploadById(id: Int64) -> OCUpload? {
        var result: OCUpload? = nil
        let db = getDB()
        let query = "SELECT * FROM \(ProviderTableMeta.CONTENT_URI_UPLOADS) WHERE \(ProviderTableMeta._ID) = ? ORDER BY _id ASC"
        let args: [String] = [String(id)]
        
        if let cursor = db.rawQuery(query, args) {
            if cursor.moveToFirst() {
                result = createOCUploadFromCursor(cursor)
            }
            cursor.close()
        }
        Log_OC.d(UploadsStorageManager.TAG, "Retrieve job \(String(describing: result)) for id \(id)")
        return result
    }
    
    private func getUploads(selection: String? = nil, selectionArgs: String?...) -> [OCUpload] {
        var uploads: [OCUpload] = []
        var page: Int = 0
        var rowsRead: Int
        var rowsTotal: Int = 0
        var lastRowID: Int64 = -1
        
        repeat {
            let uploadsPage = getUploadPage(lastRowID: lastRowID, selection: selection, selectionArgs: selectionArgs)
            rowsRead = uploadsPage.count
            rowsTotal += rowsRead
            if !uploadsPage.isEmpty {
                lastRowID = uploadsPage.last!.getUploadId()
            }
            Log_OC.v(UploadsStorageManager.TAG, String(format: "getUploads() got %d rows from page %d, %d rows total so far, last ID %d", rowsRead, page, rowsTotal, lastRowID))
            uploads.append(contentsOf: uploadsPage)
            page += 1
        } while rowsRead > 0
        
        Log_OC.v(UploadsStorageManager.TAG, String(format: "getUploads() returning %d (%d) rows after reading %d pages", rowsTotal, uploads.count, page))
        
        return uploads
    }
    
    private func getUploadPage(afterId: Int64, selection: String? = nil, selectionArgs: String?...) -> [OCUpload] {
        return getUploadPage(QUERY_PAGE_SIZE, afterId: afterId, true, selection: selection, selectionArgs: selectionArgs)
    }
    
    private func getInProgressAndDelayedUploadsSelection() -> String {
        return "( " + ProviderTableMeta.UPLOADS_STATUS + UploadsStorageManager.EQUAL + UploadStatus.UPLOAD_IN_PROGRESS.value +
            UploadsStorageManager.OR + ProviderTableMeta.UPLOADS_LAST_RESULT +
            UploadsStorageManager.EQUAL + UploadResult.DELAYED_FOR_WIFI.getValue() +
            UploadsStorageManager.OR + ProviderTableMeta.UPLOADS_LAST_RESULT +
            UploadsStorageManager.EQUAL + UploadResult.LOCK_FAILED.getValue() +
            UploadsStorageManager.OR + ProviderTableMeta.UPLOADS_LAST_RESULT +
            UploadsStorageManager.EQUAL + UploadResult.DELAYED_FOR_CHARGING.getValue() +
            UploadsStorageManager.OR + ProviderTableMeta.UPLOADS_LAST_RESULT +
            UploadsStorageManager.EQUAL + UploadResult.DELAYED_IN_POWER_SAVE_MODE.getValue() +
            " ) AND " + ProviderTableMeta.UPLOADS_ACCOUNT_NAME + UploadsStorageManager.IS_EQUAL
    }
    
    func getTotalUploadSize(selectionArgs: [String]?) -> Int {
        let selection = "\(ProviderTableMeta.UPLOADS_STATUS) = \(UploadStatus.UPLOAD_IN_PROGRESS.rawValue) AND \(ProviderTableMeta.UPLOADS_ACCOUNT_NAME) = ?"
        var totalSize = 0
        
        if let db = getDB() {
            let cursor = db.query(
                ProviderTableMeta.CONTENT_URI_UPLOADS,
                columns: ["COUNT(*) AS count"],
                selection: selection,
                selectionArgs: selectionArgs
            )
            
            if let cursor = cursor {
                if cursor.moveToFirst() {
                    totalSize = cursor.getInt(cursor.getColumnIndexOrThrow("count"))
                }
                cursor.close()
            }
        }
        
        return totalSize
    }
    
    private func getUploadPage(limit: Int64, afterId: Int64, descending: Bool, selection: String?, selectionArgs: [String]?) -> [OCUpload] {
        var uploads = [OCUpload]()
        var pageSelection = selection
        var pageSelectionArgs = selectionArgs
        
        let idComparator: String
        let sortDirection: String
        if descending {
            sortDirection = "DESC"
            idComparator = "<"
        } else {
            sortDirection = "ASC"
            idComparator = ">"
        }
        
        if afterId >= 0 {
            if let selection = selection {
                pageSelection = "(\(selection)) AND _id \(idComparator) ?"
            } else {
                pageSelection = "_id \(idComparator) ?"
            }
            if let selectionArgs = selectionArgs {
                pageSelectionArgs = selectionArgs + [String(afterId)]
            } else {
                pageSelectionArgs = [String(afterId)]
            }
            Log_OC.d(UploadsStorageManager.TAG, String(format: "QUERY: %@ ROWID: %d", pageSelection ?? "", afterId))
        } else {
            Log_OC.d(UploadsStorageManager.TAG, String(format: "QUERY: %@ ROWID: %d", selection ?? "", afterId))
        }
        
        let sortOrder: String
        if limit > 0 {
            sortOrder = String(format: "_id \(sortDirection) LIMIT %d", limit)
        } else {
            sortOrder = "_id \(sortDirection)"
        }
        
        let c = getDB().query(
            ProviderTableMeta.CONTENT_URI_UPLOADS,
            columns: nil,
            selection: pageSelection,
            selectionArgs: pageSelectionArgs,
            sortOrder: sortOrder
        )
        
        if let cursor = c {
            if cursor.moveToFirst() {
                repeat {
                    if let upload = createOCUploadFromCursor(cursor) {
                        uploads.append(upload)
                    } else {
                        Log_OC.e(UploadsStorageManager.TAG, "OCUpload could not be created from cursor")
                    }
                } while cursor.moveToNext() && !cursor.isAfterLast
            }
            cursor.close()
        }
        return uploads
    }
    
    private func createOCUploadFromCursor(_ c: Cursor?) -> OCUpload? {
        initOCCapability()
        
        var upload: OCUpload? = nil
        if let cursor = c {
            let localPath = cursor.getString(cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_LOCAL_PATH))
            
            var remotePath = cursor.getString(cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_REMOTE_PATH))
            if let capability = capability {
                remotePath = AutoRename.INSTANCE.rename(remotePath, capability, true)
            }
            
            let accountName = cursor.getString(cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_ACCOUNT_NAME))
            upload = OCUpload(localPath: localPath, remotePath: remotePath, accountName: accountName)
            
            upload?.setFileSize(cursor.getLong(cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_FILE_SIZE)))
            upload?.setUploadId(cursor.getLong(cursor.getColumnIndexOrThrow(ProviderTableMeta._ID)))
            upload?.setUploadStatus(
                UploadStatus.fromValue(cursor.getInt(cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_STATUS)))
            )
            upload?.setLocalAction(cursor.getInt(cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_LOCAL_BEHAVIOUR)))
            upload?.setNameCollisionPolicy(NameCollisionPolicy.deserialize(cursor.getInt(
                cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_NAME_COLLISION_POLICY))))
            upload?.setCreateRemoteFolder(cursor.getInt(
                cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_IS_CREATE_REMOTE_FOLDER)) == 1)
            upload?.setUploadEndTimestamp(cursor.getLong(cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_UPLOAD_END_TIMESTAMP)))
            upload?.setLastResult(UploadResult.fromValue(
                cursor.getInt(cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_LAST_RESULT))))
            upload?.setCreatedBy(cursor.getInt(cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_CREATED_BY)))
            upload?.setUseWifiOnly(cursor.getInt(cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_IS_WIFI_ONLY)) == 1)
            upload?.setWhileChargingOnly(cursor.getInt(cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_IS_WHILE_CHARGING_ONLY))
                                         == 1)
            upload?.setFolderUnlockToken(cursor.getString(cursor.getColumnIndexOrThrow(ProviderTableMeta.UPLOADS_FOLDER_UNLOCK_TOKEN)))
        }
        return upload
    }
    
    func getCurrentAndPendingUploadsForCurrentAccount() -> [OCUpload] {
        let user = currentAccountProvider.getUser()
        return getCurrentAndPendingUploadsForAccount(user.getAccountName())
    }
    
    func getCurrentAndPendingUploadsForAccount(accountName: String) -> [OCUpload] {
        let inProgressUploadsSelection = getInProgressAndDelayedUploadsSelection()
        return getUploads(selection: inProgressUploadsSelection, accountName: accountName)
    }
    
    func getCurrentUploadsForAccount(accountName: String) -> [OCUpload] {
        return getUploads(condition: "\(ProviderTableMeta.UPLOADS_STATUS) = \(UploadStatus.UPLOAD_IN_PROGRESS.rawValue) AND \(ProviderTableMeta.UPLOADS_ACCOUNT_NAME) = ?", accountName: accountName)
    }
    
    func getCurrentUploadsForAccountPageAscById(afterId: Int64, accountName: String) -> [OCUpload] {
        let selection = "\(ProviderTableMeta.UPLOADS_STATUS) = \(UploadStatus.UPLOAD_IN_PROGRESS.rawValue) AND \(ProviderTableMeta.UPLOADS_ACCOUNT_NAME) = ?"
        return getUploadPage(pageSize: QUERY_PAGE_SIZE, afterId: afterId, ascending: false, selection: selection, accountName: accountName)
    }
    
    func getCurrentAndPendingUploadsForAccountPageAscById(afterId: Int64, accountName: String) -> [OCUpload] {
        let selection = getInProgressAndDelayedUploadsSelection()
        return getUploadPage(queryPageSize: QUERY_PAGE_SIZE, afterId: afterId, ascending: false, selection: selection, accountName: accountName)
    }
    
    func getFailedUploads() -> [OCUpload] {
        return getUploads("(" + ProviderTableMeta.UPLOADS_STATUS + UploadsStorageManager.IS_EQUAL +
                          UploadsStorageManager.OR + ProviderTableMeta.UPLOADS_LAST_RESULT +
                          UploadsStorageManager.EQUAL + UploadResult.DELAYED_FOR_WIFI.rawValue +
                          UploadsStorageManager.OR + ProviderTableMeta.UPLOADS_LAST_RESULT +
                          UploadsStorageManager.EQUAL + UploadResult.LOCK_FAILED.rawValue +
                          UploadsStorageManager.OR + ProviderTableMeta.UPLOADS_LAST_RESULT +
                          UploadsStorageManager.EQUAL + UploadResult.DELAYED_FOR_CHARGING.rawValue +
                          UploadsStorageManager.OR + ProviderTableMeta.UPLOADS_LAST_RESULT +
                          UploadsStorageManager.EQUAL + UploadResult.DELAYED_IN_POWER_SAVE_MODE.rawValue +
                          " ) AND " + ProviderTableMeta.UPLOADS_LAST_RESULT +
                          "!= " + UploadResult.VIRUS_DETECTED.rawValue,
                          String(UploadStatus.UPLOAD_FAILED.rawValue))
    }
    
    func getUploadsForAccount(accountName: String) -> [OCUpload] {
        return getUploads(predicate: "\(ProviderTableMeta.UPLOADS_ACCOUNT_NAME) == \(accountName)")
    }
    
    func getFinishedUploadsForCurrentAccount() -> [OCUpload] {
        let user = currentAccountProvider.getUser()
        return getUploads("\(ProviderTableMeta.UPLOADS_STATUS) = \(UploadStatus.UPLOAD_SUCCEEDED.rawValue) AND \(ProviderTableMeta.UPLOADS_ACCOUNT_NAME) = ?", user.getAccountName())
    }
    
    func getCancelledUploadsForCurrentAccount() -> [OCUpload] {
        let user = currentAccountProvider.getUser()
        return getUploads("\(ProviderTableMeta.UPLOADS_STATUS) = \(UploadStatus.UPLOAD_CANCELLED.rawValue) AND \(ProviderTableMeta.UPLOADS_ACCOUNT_NAME) = ?", user.getAccountName())
    }
    
    func getFinishedUploads() -> [OCUpload] {
        return getUploads(condition: "\(ProviderTableMeta.UPLOADS_STATUS) = \(UploadStatus.UPLOAD_SUCCEEDED.rawValue)", args: nil)
    }
    
    func getFailedButNotDelayedUploadsForCurrentAccount() -> [OCUpload] {
        guard let user = currentAccountProvider.getUser() else {
            return []
        }
        
        return getUploads(
            "\(ProviderTableMeta.UPLOADS_STATUS) = \(UploadStatus.UPLOAD_FAILED.rawValue) AND " +
            "\(ProviderTableMeta.UPLOADS_LAST_RESULT) > \(UploadResult.DELAYED_FOR_WIFI.rawValue) AND " +
            "\(ProviderTableMeta.UPLOADS_LAST_RESULT) > \(UploadResult.LOCK_FAILED.rawValue) AND " +
            "\(ProviderTableMeta.UPLOADS_LAST_RESULT) > \(UploadResult.DELAYED_FOR_CHARGING.rawValue) AND " +
            "\(ProviderTableMeta.UPLOADS_LAST_RESULT) > \(UploadResult.DELAYED_IN_POWER_SAVE_MODE.rawValue) AND " +
            "\(ProviderTableMeta.UPLOADS_ACCOUNT_NAME) = '\(user.getAccountName())'"
        )
    }
    
    func getFailedButNotDelayedUploads() -> [OCUpload] {
        return getUploads(
            "\(ProviderTableMeta.UPLOADS_STATUS) = \(UploadStatus.UPLOAD_FAILED.rawValue) AND " +
            "\(ProviderTableMeta.UPLOADS_LAST_RESULT) > \(UploadResult.LOCK_FAILED.rawValue) AND " +
            "\(ProviderTableMeta.UPLOADS_LAST_RESULT) > \(UploadResult.DELAYED_FOR_WIFI.rawValue) AND " +
            "\(ProviderTableMeta.UPLOADS_LAST_RESULT) > \(UploadResult.DELAYED_FOR_CHARGING.rawValue) AND " +
            "\(ProviderTableMeta.UPLOADS_LAST_RESULT) > \(UploadResult.DELAYED_IN_POWER_SAVE_MODE.rawValue)",
            nil
        )
    }
    
    private func getDB() -> ContentResolver {
        return contentResolver
    }
    
    func clearFailedButNotDelayedUploads() -> Int64 {
        guard let user = currentAccountProvider.getUser() else { return 0 }
        let deleted = getDB().delete(
            ProviderTableMeta.CONTENT_URI_UPLOADS,
            selection: "\(ProviderTableMeta.UPLOADS_STATUS) = \(UploadStatus.UPLOAD_FAILED.rawValue) AND " +
                       "\(ProviderTableMeta.UPLOADS_LAST_RESULT) > \(UploadResult.LOCK_FAILED.rawValue) AND " +
                       "\(ProviderTableMeta.UPLOADS_LAST_RESULT) > \(UploadResult.DELAYED_FOR_WIFI.rawValue) AND " +
                       "\(ProviderTableMeta.UPLOADS_LAST_RESULT) > \(UploadResult.DELAYED_FOR_CHARGING.rawValue) AND " +
                       "\(ProviderTableMeta.UPLOADS_LAST_RESULT) > \(UploadResult.DELAYED_IN_POWER_SAVE_MODE.rawValue) AND " +
                       "\(ProviderTableMeta.UPLOADS_ACCOUNT_NAME) = ?",
            selectionArgs: [user.getAccountName()]
        )
        Log_OC.d(UploadsStorageManager.TAG, "delete all failed uploads but those delayed for Wifi")
        if deleted > 0 {
            notifyObserversNow()
        }
        return deleted
    }
    
    func clearCancelledUploadsForCurrentAccount() {
        guard let user = currentAccountProvider.getUser() else { return }
        let deleted = getDB().delete(
            ProviderTableMeta.CONTENT_URI_UPLOADS,
            where: "\(ProviderTableMeta.UPLOADS_STATUS) = ? AND \(ProviderTableMeta.UPLOADS_ACCOUNT_NAME) = ?",
            args: [UploadStatus.UPLOAD_CANCELLED.rawValue, user.getAccountName()]
        )
        
        Log_OC.d(UploadsStorageManager.TAG, "delete all cancelled uploads")
        if deleted > 0 {
            notifyObserversNow()
        }
    }
    
    func clearSuccessfulUploads() -> Int64 {
        guard let user = currentAccountProvider.getUser() else { return 0 }
        let deleted = getDB().delete(
            ProviderTableMeta.CONTENT_URI_UPLOADS,
            where: "\(ProviderTableMeta.UPLOADS_STATUS) = ? AND \(ProviderTableMeta.UPLOADS_ACCOUNT_NAME) = ?",
            args: [UploadStatus.UPLOAD_SUCCEEDED.value, user.getAccountName()]
        )
        
        Log_OC.d(UploadsStorageManager.TAG, "delete all successful uploads")
        if deleted > 0 {
            notifyObserversNow()
        }
        return deleted
    }
    
    func updateDatabaseUploadResult(uploadResult: RemoteOperationResult, upload: UploadFileOperation) {
        // result: success or fail notification
        Log_OC.d(UploadsStorageManager.TAG, "updateDatabaseUploadResult uploadResult: \(uploadResult) upload: \(upload)")
        
        if uploadResult.isCancelled() {
            removeUpload(
                accountName: upload.getUser().getAccountName(),
                remotePath: upload.getRemotePath()
            )
        } else {
            let localPath = (FileUploadWorker.LOCAL_BEHAVIOUR_MOVE == upload.getLocalBehaviour()) ? upload.getStoragePath() : nil
            
            if uploadResult.isSuccess() {
                updateUploadStatus(
                    ocUploadId: upload.getOCUploadId(),
                    status: .UPLOAD_SUCCEEDED,
                    result: .UPLOADED,
                    remotePath: upload.getRemotePath(),
                    localPath: localPath
                )
            } else if uploadResult.getCode() == .SYNC_CONFLICT &&
                FileUploadHelper().isSameFileOnRemote(
                    user: upload.getUser(), 
                    file: File(upload.getStoragePath()), 
                    remotePath: upload.getRemotePath(), 
                    context: upload.getContext()) {
                
                updateUploadStatus(
                    ocUploadId: upload.getOCUploadId(),
                    status: .UPLOAD_SUCCEEDED,
                    result: .SAME_FILE_CONFLICT,
                    remotePath: upload.getRemotePath(),
                    localPath: localPath
                )
            } else if uploadResult.getCode() == .LOCAL_FILE_NOT_FOUND {
                updateUploadStatus(
                    ocUploadId: upload.getOCUploadId(),
                    status: .UPLOAD_SUCCEEDED,
                    result: .FILE_NOT_FOUND,
                    remotePath: upload.getRemotePath(),
                    localPath: localPath
                )
            } else {
                updateUploadStatus(
                    ocUploadId: upload.getOCUploadId(),
                    status: .UPLOAD_FAILED,
                    result: UploadResult.fromOperationResult(uploadResult),
                    remotePath: upload.getRemotePath(),
                    localPath: localPath
                )
            }
        }
    }
    
    func updateDatabaseUploadStart(upload: UploadFileOperation) {
        let localPath = (upload.getLocalBehaviour() == FileUploadWorker.LOCAL_BEHAVIOUR_MOVE) ? upload.getStoragePath() : nil
        
        updateUploadStatus(
            ocUploadId: upload.getOCUploadId(),
            status: .uploadInProgress,
            result: .unknown,
            remotePath: upload.getRemotePath(),
            localPath: localPath
        )
    }
    
    func failInProgressUploads(fail: UploadResult?) -> Int {
        Log_OC.v(UploadsStorageManager.TAG, "Updating state of any killed upload")
        
        var cv = [String: Any]()
        cv[ProviderTableMeta.UPLOADS_STATUS] = UploadStatus.UPLOAD_FAILED.rawValue
        cv[ProviderTableMeta.UPLOADS_LAST_RESULT] = fail?.rawValue ?? UploadResult.UNKNOWN.rawValue
        cv[ProviderTableMeta.UPLOADS_UPLOAD_END_TIMESTAMP] = Date().timeIntervalSince1970 * 1000
        
        let result = getDB().update(
            ProviderTableMeta.CONTENT_URI_UPLOADS,
            values: cv,
            where: "\(ProviderTableMeta.UPLOADS_STATUS)=?",
            whereArgs: [String(UploadStatus.UPLOAD_IN_PROGRESS.rawValue)]
        )
        
        if result == 0 {
            Log_OC.v(UploadsStorageManager.TAG, "No upload was killed")
        } else {
            Log_OC.w(UploadsStorageManager.TAG, "\(result) uploads where abruptly interrupted")
            notifyObserversNow()
        }
        
        return result
    }
    
    func removeAllUploads() -> Int {
        OCLog.v(UploadsStorageManager.TAG, "Delete all uploads!")
        return getDB().delete(ProviderTableMeta.CONTENT_URI_UPLOADS, where: "", args: [])
    }
    
    func removeUserUploads(user: User) -> Int {
        Log_OC.v(UploadsStorageManager.TAG, "Delete all uploads for account \(user.getAccountName())")
        return getDB().delete(
            ProviderTableMeta.CONTENT_URI_UPLOADS,
            where: "\(ProviderTableMeta.UPLOADS_ACCOUNT_NAME)=?",
            args: [user.getAccountName()]
        )
    }
    
    enum UploadStatus: Int {
        case uploadInProgress = 0
        case uploadFailed = 1
        case uploadSucceeded = 2
        case uploadCancelled = 3
        
        static func fromValue(_ value: Int) -> UploadStatus? {
            switch value {
            case 0:
                return .uploadInProgress
            case 1:
                return .uploadFailed
            case 2:
                return .uploadSucceeded
            case 3:
                return .uploadCancelled
            default:
                return nil
            }
        }
    }
}
