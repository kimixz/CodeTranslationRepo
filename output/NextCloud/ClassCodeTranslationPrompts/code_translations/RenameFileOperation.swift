
import Foundation

class RenameFileOperation: SyncOperation {
    
    private static let TAG = String(describing: RenameFileOperation.self)
    
    private var file: OCFile!
    private var remotePath: String
    private var newName: String
    
    init(remotePath: String, newName: String, storageManager: FileDataStorageManager) {
        self.remotePath = remotePath
        self.newName = newName
        super.init(storageManager: storageManager)
    }
    
    override func run(client: OwnCloudClient) -> RemoteOperationResult {
        var result: RemoteOperationResult? = nil
        var newRemotePath: String? = nil
        
        file = getStorageManager().getFileByPath(remotePath)
        
        do {
            if !isValidNewName() {
                return RemoteOperationResult(resultCode: .invalidLocalFileName)
            }
            var parent = (file.remotePath as NSString).deletingLastPathComponent
            parent = parent.hasSuffix(OCFile.pathSeparator) ? parent : parent + OCFile.pathSeparator
            newRemotePath = parent + newName
            if file.isFolder {
                newRemotePath! += OCFile.pathSeparator
            }
            
            if getStorageManager().getFileByPath(newRemotePath!) != nil {
                return RemoteOperationResult(resultCode: .invalidOverwrite)
            }
            
            result = RenameFileRemoteOperation(fileName: file.fileName,
                                               remotePath: file.remotePath,
                                               newName: newName,
                                               isFolder: file.isFolder)
                .execute(client: client)
            
            if result!.isSuccess {
                if file.isFolder {
                    getStorageManager().moveLocalFile(file: file, toPath: newRemotePath!, parentPath: parent)
                } else {
                    saveLocalFile(newRemotePath: newRemotePath!)
                }
            }
            
        } catch let e as NSError {
            Log_OC.e(RenameFileOperation.TAG, "Rename \(file.remotePath) to \((newRemotePath == nil) ? newName : newRemotePath!): \(result != nil ? result!.logMessage : "")", e)
        }
        
        return result!
    }
    
    private func saveLocalFile(newRemotePath: String) {
        file.setFileName(newName)
        
        if !file.isEncrypted() {
            file.setDecryptedRemotePath(newRemotePath)
        }
        
        if file.isDown() {
            let oldPath = file.getStoragePath()
            let f = File(oldPath)
            var parentStoragePath = f.getParent()
            if !parentStoragePath.hasSuffix(File.separator) {
                parentStoragePath += File.separator
            }
            if f.renameTo(File(parentStoragePath + newName)) {
                let newPath = parentStoragePath + newName
                file.setStoragePath(newPath)
                
                getStorageManager().deleteFileInMediaScan(oldPath)
                if MimeTypeUtil.isMedia(file.getMimeType()) {
                    FileDataStorageManager.triggerMediaScan(newPath, file)
                }
            }
        }
        
        getStorageManager().saveFile(file)
    }
    
    private func isValidNewName() throws -> Bool {
        if newName.isEmpty || newName.contains(FileManager.default.pathSeparator) {
            return false
        }
        let tmpFolderName = FileStorageUtils.getTemporalPath("")
        let testFilePath = tmpFolderName + newName
        let tmpFolder = URL(fileURLWithPath: testFilePath).deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: tmpFolder.path) {
            do {
                try FileManager.default.createDirectory(at: tmpFolder, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Unable to create parent folder \(tmpFolder.path)")
            }
        }
        if !FileManager.default.fileExists(atPath: tmpFolder.path, isDirectory: nil) {
            throw NSError(domain: "Unexpected error: temporal directory could not be created", code: 0, userInfo: nil)
        }
        do {
            FileManager.default.createFile(atPath: testFilePath, contents: nil, attributes: nil)
        } catch {
            print("Test for validity of name \(newName) in the file system failed")
            return false
        }
        let result = FileManager.default.fileExists(atPath: testFilePath)
        
        try? FileManager.default.removeItem(atPath: testFilePath)
        
        return result
    }
    
    func getFile() -> OCFile {
        return self.file
    }
}
