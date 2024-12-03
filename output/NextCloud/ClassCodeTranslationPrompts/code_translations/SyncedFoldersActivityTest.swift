
import XCTest

class SyncedFoldersActivityTest: XCTestCase {

    func testRegular() {
        let sortedArray = [
            create(folderName: "Folder1", enabled: true),
            create(folderName: "Folder2", enabled: true)
        ]

        XCTAssertTrue(sortAndTest(sortedList: sortedArray))
    }

    func testWithNull() {
        let sortedArray: [SyncedFolderDisplayItem?] = [
            nil,
            nil,
            create(folderName: "Folder1", enabled: true),
            create(folderName: "Folder2", enabled: true)
        ]

        XCTAssertTrue(sortAndTest(sortedList: sortedArray.compactMap { $0 }))
    }

    func testWithNullAndEnableStatus() {
        let sortedArray: [SyncedFolderDisplayItem?] = [
            nil,
            nil,
            create(folderName: "Folder1", enabled: true),
            create(folderName: "Folder2", enabled: true),
            create(folderName: "Folder3", enabled: true),
            create(folderName: "Folder4", enabled: true),
            create(folderName: "Folder5", enabled: false),
            create(folderName: "Folder6", enabled: false),
            create(folderName: "Folder7", enabled: false),
            create(folderName: "Folder8", enabled: false),
        ]

        XCTAssertTrue(sortAndTest(sortedList: sortedArray.compactMap { $0 }))
    }

    func testWithNullFolderName() {
        let sortedArray: [SyncedFolderDisplayItem?] = [
            nil,
            nil,
            create(folderName: "Folder1", enabled: true),
            create(folderName: nil, enabled: false),
            create(folderName: "Folder2", enabled: false),
            create(folderName: "Folder3", enabled: false),
            create(folderName: "Folder4", enabled: false),
            create(folderName: "Folder5", enabled: false),
        ]

        XCTAssertTrue(sortAndTest(sortedList: sortedArray.compactMap { $0 }))
    }

    func testWithNullFolderNameAllEnabled() {
        let sortedArray: [SyncedFolderDisplayItem?] = [
            nil,
            nil,
            create(folderName: nil, enabled: true),
            create(folderName: "Folder1", enabled: true),
            create(folderName: "Folder2", enabled: true),
            create(folderName: "Folder3", enabled: true),
            create(folderName: "Folder4", enabled: true),
        ]

        XCTAssertTrue(sortAndTest(sortedList: sortedArray.compactMap { $0 }))
    }

    private func shuffle(_ list: [SyncedFolderDisplayItem]) -> [SyncedFolderDisplayItem] {
        var shuffled = list
        shuffled.shuffle()
        return shuffled
    }

    private func sortAndTest(sortedList: [SyncedFolderDisplayItem]) -> Bool {
        let unsortedList = shuffle(sortedList)
        return test(target: sortedList, actual: SyncedFoldersActivity.sortSyncedFolderItems(unsortedList))
    }

    private func test(target: [SyncedFolderDisplayItem], actual: [SyncedFolderDisplayItem]) -> Bool {
        for i in 0..<target.count {
            let compare = target[i] === actual[i]

            if !compare {
                print("target:")
                for item in target {
                    if item == nil {
                        print("null")
                    } else {
                        print("\(item.getFolderName()) \(item.isEnabled())")
                    }
                }

                print()
                print("actual:")
                for item in actual {
                    if item == nil {
                        print("null")
                    } else {
                        print("\(item.getFolderName()) \(item.isEnabled())")
                    }
                }

                return false
            }
        }

        return true
    }

    private func create(folderName: String?, enabled: Bool) -> SyncedFolderDisplayItem {
        return SyncedFolderDisplayItem(
            id: 1,
            localPath: "localPath",
            remotePath: "remotePath",
            isEnabled: true,
            isSyncEnabled: true,
            isSyncing: true,
            isSyncFolder: true,
            accountName: "test@nextcloud.com",
            localBehaviour: FileUploadWorker.LOCAL_BEHAVIOUR_MOVE,
            nameCollisionPolicy: NameCollisionPolicy.ASK_USER.serialize(),
            isEnabled: enabled,
            lastSync: Date().timeIntervalSince1970,
            excludedFiles: [String](),
            folderName: folderName,
            syncInterval: 2,
            mediaFolderType: .IMAGE,
            isMediaFolder: false,
            subFolderRule: .YEAR_MONTH,
            isSubFolderSyncEnabled: true,
            syncStatus: .NOT_SCANNED_YET
        )
    }
}
