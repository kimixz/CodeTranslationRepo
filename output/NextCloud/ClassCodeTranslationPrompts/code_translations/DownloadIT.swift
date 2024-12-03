
import Foundation

class DownloadIT: AbstractOnServerIT {
    private static let FOLDER = "/testUpload/"

    func after() {
        let result = RefreshFolderOperation(
            file: getStorageManager().getFileByPath("/"),
            lastModified: Int64(Date().timeIntervalSince1970),
            isUserLoggedIn: false,
            isSyncFolder: true,
            storageManager: getStorageManager(),
            user: user,
            context: targetContext
        ).execute(client: client)

        if result.isSuccess() && getStorageManager().getFileByDecryptedRemotePath(DownloadIT.FOLDER) != nil {
            RemoveFileOperation(
                file: getStorageManager().getFileByDecryptedRemotePath(DownloadIT.FOLDER),
                keepInCache: false,
                user: user,
                isFolder: false,
                context: targetContext,
                storageManager: getStorageManager()
            ).execute(client: client)
        }
    }

    func verifyDownload() {
        let ocUpload = OCUpload(
            path: FileStorageUtils.getTemporalPath(account.name) + "/nonEmpty.txt",
            remotePath: DownloadIT.FOLDER + "nonEmpty.txt",
            accountName: account.name
        )

        uploadOCUpload(ocUpload)

        let ocUpload2 = OCUpload(
            path: FileStorageUtils.getTemporalPath(account.name) + "/nonEmpty.txt",
            remotePath: DownloadIT.FOLDER + "nonEmpty2.txt",
            accountName: account.name
        )

        uploadOCUpload(ocUpload2)

        refreshFolder("/")
        refreshFolder(DownloadIT.FOLDER)

        var file1 = fileDataStorageManager.getFileByDecryptedRemotePath(DownloadIT.FOLDER + "nonEmpty.txt")
        var file2 = fileDataStorageManager.getFileByDecryptedRemotePath(DownloadIT.FOLDER + "nonEmpty2.txt")
        verifyDownload(file1: file1, file2: file2)

        assert(DownloadFileOperation(user: user, file: file1, context: targetContext).execute(client: client).isSuccess)
        assert(DownloadFileOperation(user: user, file: file2, context: targetContext).execute(client: client).isSuccess)

        refreshFolder(DownloadIT.FOLDER)

        file1 = fileDataStorageManager.getFileByDecryptedRemotePath(DownloadIT.FOLDER + "nonEmpty.txt")
        file2 = fileDataStorageManager.getFileByDecryptedRemotePath(DownloadIT.FOLDER + "nonEmpty2.txt")

        verifyDownload(file1: file1, file2: file2)
    }

    private func verifyDownload(file1: OCFile?, file2: OCFile?) {
        XCTAssertNotNil(file1)
        XCTAssertNotNil(file2)
        XCTAssertNotEqual(file1?.storagePath, file2?.storagePath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file1?.storagePath ?? ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2?.storagePath ?? ""))

        XCTAssertEqual("/storage/emulated/0/Android/media/com.nextcloud.client/nextcloud/" +
                       account.name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)! + "/testUpload/nonEmpty.txt",
                       file1?.storagePath)
        XCTAssertEqual("/storage/emulated/0/Android/media/com.nextcloud.client/nextcloud/" +
                       account.name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)! + "/testUpload/nonEmpty2.txt",
                       file2?.storagePath)
    }
}
