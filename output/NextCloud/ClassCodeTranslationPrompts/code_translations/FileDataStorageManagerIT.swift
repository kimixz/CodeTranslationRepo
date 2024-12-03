
import XCTest

class FileDataStorageManagerIT: XCTestCase {
    var sut: FileDataStorageManager!
    var capability: OCCapability!

    override func setUp() {
        super.setUp()
        // make sure everything is removed
        sut.deleteAllFiles()
        sut.deleteVirtuals(type: .gallery)

        XCTAssertEqual(0, sut.getAllFiles().count)

        capability = GetCapabilitiesRemoteOperation(nil)
            .execute(client)
            .getSingleData() as? OCCapability
    }

    override func tearDown() {
        super.tearDown()

        sut.deleteAllFiles()
        sut.deleteVirtuals(type: .gallery)
    }

    func simpleTest() {
        let file = sut.getFileByDecryptedRemotePath("/")
        XCTAssertNotNil(file)
        XCTAssertTrue(file.fileExists())
        XCTAssertNil(sut.getFileByDecryptedRemotePath("/123123"))
    }

    func testGetAllFiles_NoAvailable() {
        XCTAssertEqual(0, sut.getAllFiles().count)
    }

    func testFolderContent() throws {
        XCTAssertEqual(0, sut.getAllFiles().count)
        XCTAssertTrue(CreateFolderRemoteOperation("/1/1/", true).execute(client).isSuccess)

        XCTAssertTrue(CreateFolderRemoteOperation("/1/2/", true).execute(client).isSuccess)

        XCTAssertTrue(UploadFileRemoteOperation(getDummyFile("chunkedFile.txt").path,
                                                "/1/1/chunkedFile.txt",
                                                "text/plain",
                                                Date().timeIntervalSince1970)
                        .execute(client).isSuccess)

        XCTAssertTrue(UploadFileRemoteOperation(getDummyFile("chunkedFile.txt").path,
                                                "/1/1/chunkedFile2.txt",
                                                "text/plain",
                                                Date().timeIntervalSince1970)
                        .execute(client).isSuccess)

        let imageFile = getFile("imageFile.png")
        XCTAssertTrue(UploadFileRemoteOperation(imageFile.path,
                                                "/1/1/imageFile.png",
                                                "image/png",
                                                Date().timeIntervalSince1970)
                        .execute(client).isSuccess)

        XCTAssertNil(sut.getFileByDecryptedRemotePath("/1/1/"))

        XCTAssertTrue(RefreshFolderOperation(sut.getFileByDecryptedRemotePath("/"),
                                             Date().timeIntervalSince1970,
                                             false,
                                             false,
                                             sut,
                                             user,
                                             targetContext).execute(client).isSuccess)

        XCTAssertTrue(RefreshFolderOperation(sut.getFileByDecryptedRemotePath("/1/"),
                                             Date().timeIntervalSince1970,
                                             false,
                                             false,
                                             sut,
                                             user,
                                             targetContext).execute(client).isSuccess)

        XCTAssertTrue(RefreshFolderOperation(sut.getFileByDecryptedRemotePath("/1/1/"),
                                             Date().timeIntervalSince1970,
                                             false,
                                             false,
                                             sut,
                                             user,
                                             targetContext).execute(client).isSuccess)

        XCTAssertEqual(3, sut.getFolderContent(sut.getFileByDecryptedRemotePath("/1/1/"), false).count)
    }

    func testPhotoSearch() throws {
        let remotePath = "/imageFile.png"
        let virtualType = VirtualFolderType.gallery

        XCTAssertEqual(0, sut.getFolderContent(sut.getFileByDecryptedRemotePath("/"), false).count)
        XCTAssertEqual(1, sut.getAllFiles().count)

        let imageFile = getFile("imageFile.png")
        XCTAssertTrue(UploadFileRemoteOperation(filePath: imageFile.absolutePath,
                                                remotePath: remotePath,
                                                mimeType: "image/png",
                                                lastModified: Date().timeIntervalSince1970 / 1000)
                        .execute(client).isSuccess)

        XCTAssertNil(sut.getFileByDecryptedRemotePath(remotePath))

        let searchRemoteOperation = SearchRemoteOperation(query: "image/%",
                                                          searchType: .photoSearch,
                                                          isCaseSensitive: false,
                                                          capability: capability)

        let searchResult = searchRemoteOperation.execute(client)
        XCTAssertTrue(searchResult.isSuccess)
        XCTAssertEqual(1, searchResult.resultData.count)

        let ocFile = FileStorageUtils.fillOCFile(searchResult.resultData[0])
        sut.saveFile(ocFile)

        var contentValues = [ContentValues]()
        var cv = ContentValues()
        cv.put(ProviderMeta.ProviderTableMeta.virtualType, virtualType.rawValue)
        cv.put(ProviderMeta.ProviderTableMeta.virtualOCFileId, ocFile.fileId)

        contentValues.append(cv)

        sut.saveVirtuals(contentValues)

        XCTAssertEqual(remotePath, ocFile.remotePath)

        XCTAssertEqual(0, sut.getFolderContent(sut.getFileByDecryptedRemotePath("/"), false).count)

        XCTAssertEqual(1, sut.getVirtualFolderContent(virtualType, false).count)
        XCTAssertEqual(2, sut.getAllFiles().count)

        XCTAssertTrue(RefreshFolderOperation(folder: sut.getFileByDecryptedRemotePath("/"),
                                             lastModified: Date().timeIntervalSince1970 / 1000,
                                             isRecursive: false,
                                             isForceRefresh: false,
                                             fileDataStorageManager: sut,
                                             user: user,
                                             context: targetContext).execute(client).isSuccess)

        XCTAssertEqual(1, sut.getFolderContent(sut.getFileByDecryptedRemotePath("/"), false).count)
        XCTAssertEqual(1, sut.getVirtualFolderContent(virtualType, false).count)
        XCTAssertEqual(2, sut.getAllFiles().count)

        XCTAssertEqual(sut.getVirtualFolderContent(virtualType, false)[0],
                       sut.getFolderContent(sut.getFileByDecryptedRemotePath("/"), false)[0])
    }

    func testGallerySearch() throws {
        sut = FileDataStorageManager(user: user, contentProviderClient: targetContext.contentResolver.acquireContentProviderClient(ProviderMeta.ProviderTableMeta.CONTENT_URI))

        let imagePath = "/imageFile.png"
        let virtualType = VirtualFolderType.GALLERY

        XCTAssertEqual(0, sut.getFolderContent(sut.getFileByDecryptedRemotePath("/"), false).count)
        XCTAssertEqual(1, sut.getAllFiles().count)

        let imageFile = getFile("imageFile.png")
        XCTAssertTrue(UploadFileRemoteOperation(filePath: imageFile.absolutePath, remotePath: imagePath, mimeType: "image/png", lastModified: (Date().timeIntervalSince1970 - 10000) / 1000).execute(client: client).isSuccess)

        XCTAssertNil(sut.getFileByDecryptedRemotePath(imagePath))

        let videoPath = "/videoFile.mp4"
        let videoFile = getFile("videoFile.mp4")
        XCTAssertTrue(UploadFileRemoteOperation(filePath: videoFile.absolutePath, remotePath: videoPath, mimeType: "video/mpeg", lastModified: (Date().timeIntervalSince1970 + 10000) / 1000).execute(client: client).isSuccess)

        XCTAssertNil(sut.getFileByDecryptedRemotePath(videoPath))

        let searchRemoteOperation = SearchRemoteOperation(query: "", searchType: GALLERY_SEARCH, isCaseSensitive: false, capability: capability)
        let searchResult = searchRemoteOperation.execute(client: client)
        XCTAssertTrue(searchResult.isSuccess)
        XCTAssertEqual(2, searchResult.resultData.count)

        let ocFile = FileStorageUtils.fillOCFile(remoteFile: searchResult.resultData[0])
        sut.saveFile(ocFile)
        XCTAssertEqual(videoPath, ocFile.remotePath)

        var contentValues: [ContentValues] = []
        var cv = ContentValues()
        cv.put(ProviderMeta.ProviderTableMeta.VIRTUAL_TYPE, virtualType.rawValue)
        cv.put(ProviderMeta.ProviderTableMeta.VIRTUAL_OCFILE_ID, ocFile.fileId)
        contentValues.append(cv)

        let ocFile2 = FileStorageUtils.fillOCFile(remoteFile: searchResult.resultData[1])
        sut.saveFile(ocFile2)
        XCTAssertEqual(imagePath, ocFile2.remotePath)

        var cv2 = ContentValues()
        cv2.put(ProviderMeta.ProviderTableMeta.VIRTUAL_TYPE, virtualType.rawValue)
        cv2.put(ProviderMeta.ProviderTableMeta.VIRTUAL_OCFILE_ID, ocFile2.fileId)
        contentValues.append(cv2)

        sut.saveVirtuals(contentValues)

        XCTAssertEqual(0, sut.getFolderContent(sut.getFileByDecryptedRemotePath("/"), false).count)
        XCTAssertEqual(2, sut.getVirtualFolderContent(virtualType, false).count)
        XCTAssertEqual(3, sut.getAllFiles().count)

        XCTAssertTrue(RefreshFolderOperation(folder: sut.getFileByDecryptedRemotePath("/"), lastModified: Date().timeIntervalSince1970 / 1000, isRecursive: false, isForceRefresh: false, storageManager: sut, user: user, context: targetContext).execute(client: client).isSuccess)

        XCTAssertEqual(2, sut.getFolderContent(sut.getFileByDecryptedRemotePath("/"), false).count)
        XCTAssertEqual(2, sut.getVirtualFolderContent(virtualType, false).count)
        XCTAssertEqual(3, sut.getAllFiles().count)

        XCTAssertEqual(sut.getVirtualFolderContent(virtualType, false)[0], sut.getFolderContent(sut.getFileByDecryptedRemotePath("/"), false)[0])
    }

    func testSaveNewFile() {
        XCTAssertTrue(CreateFolderRemoteOperation("/1/1/", true).execute(client).isSuccess())

        XCTAssertTrue(RefreshFolderOperation(sut.getFileByDecryptedRemotePath("/"),
                                             Date().timeIntervalSince1970,
                                             false,
                                             false,
                                             sut,
                                             user,
                                             targetContext).execute(client).isSuccess())

        XCTAssertTrue(RefreshFolderOperation(sut.getFileByDecryptedRemotePath("/1/"),
                                             Date().timeIntervalSince1970,
                                             false,
                                             false,
                                             sut,
                                             user,
                                             targetContext).execute(client).isSuccess())

        XCTAssertTrue(RefreshFolderOperation(sut.getFileByDecryptedRemotePath("/1/1/"),
                                             Date().timeIntervalSince1970,
                                             false,
                                             false,
                                             sut,
                                             user,
                                             targetContext).execute(client).isSuccess())

        let newFile = OCFile("/1/1/1.txt")
        newFile.setRemoteId("12345678")

        sut.saveNewFile(newFile)
    }

    func testSaveNewFile_NonExistingParent() {
        XCTAssertTrue(CreateFolderRemoteOperation("/1/1/", true).execute(client).isSuccess())

        let newFile = OCFile("/1/1/1.txt")

        XCTAssertThrowsError(try sut.saveNewFile(newFile)) { error in
            XCTAssertTrue(error is IllegalArgumentException)
        }
    }

    func testOCCapability() {
        let capability = OCCapability()
        capability.setUserStatus(.true)

        sut.saveCapabilities(capability)

        let newCapability = sut.getCapability(user)

        XCTAssertEqual(capability.getUserStatus(), newCapability.getUserStatus())
    }
}
