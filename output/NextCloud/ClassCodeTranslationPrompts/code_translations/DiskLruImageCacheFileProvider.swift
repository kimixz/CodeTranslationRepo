
import Foundation
import UIKit

class DiskLruImageCacheFileProvider: NSObject {
    static let TAG = String(describing: DiskLruImageCacheFileProvider.self)
    
    var accountManager: UserAccountManager!
    
    override init() {
        super.init()
        AndroidInjection.inject(self)
    }
    
    private func getFile(uri: URL) -> OCFile? {
        let user = accountManager.getUser()
        let fileDataStorageManager = FileDataStorageManager(user: user, contentResolver: MainApp.getAppContext().contentResolver)
        
        return fileDataStorageManager.getFileByPath(path: uri.path)
    }
    
    func openFile(uri: URL, mode: String) throws -> FileHandle {
        return try DiskLruImageCacheFileProvider.getFileDescriptorForOCFile(ocFile: getFile(uri: uri)!)
    }
    
    static func getFileDescriptorForOCFile(ocFile: OCFile) throws -> FileHandle {
        var thumbnail: UIImage? = ThumbnailsCacheManager.getBitmapFromDiskCache(key: ThumbnailsCacheManager.PREFIX_RESIZED_IMAGE + ocFile.getRemoteId())
        
        if thumbnail == nil {
            thumbnail = ThumbnailsCacheManager.getBitmapFromDiskCache(key: ThumbnailsCacheManager.PREFIX_THUMBNAIL + ocFile.getRemoteId())
        }
        
        if thumbnail == nil {
            thumbnail = ThumbnailsCacheManager.mDefaultImg
        }
        
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fileURL = cacheDir.appendingPathComponent(ocFile.getFileName())
        
        do {
            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
            }
            
            if let thumbnail = thumbnail, let data = thumbnail.pngData() {
                try data.write(to: fileURL)
            } else {
                throw NSError(domain: "Error converting image to data", code: 0, userInfo: nil)
            }
        } catch {
            print("Error opening file: \(error.localizedDescription)")
            throw error
        }
        
        return try FileHandle(forReadingFrom: fileURL)
    }
    
    func getType(for uri: URL) -> String {
        let ocFile = getFile(uri: uri)
        return ocFile?.getMimeType() ?? ""
    }
    
    func query(uri: URL, arg1: [String]?, arg2: String?, arg3: [String]?, arg4: String?) -> [[String: Any]]? {
        var cursor: [[String: Any]]? = nil
        
        let ocFile = getFile(uri: uri)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(ocFile!.fileName)
        if FileManager.default.fileExists(atPath: file.path) {
            cursor = []
            let row: [String: Any] = [
                "DISPLAY_NAME": uri.lastPathComponent,
                "SIZE": try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64 ?? 0
            ]
            cursor?.append(row)
        }
        
        return cursor
    }
    
    func insert(_ uri: URL, values: [String: Any]) -> URL? {
        return nil
    }
    
    func delete(uri: URL, selection: String?, selectionArgs: [String]?) -> Int {
        return 0
    }
    
    func update(_ uri: URL, values: [String: Any], selection: String?, selectionArgs: [String]?) -> Int {
        return 0
    }
}
