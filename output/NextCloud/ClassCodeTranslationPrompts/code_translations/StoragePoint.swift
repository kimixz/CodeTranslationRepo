
class StoragePoint: Comparable {
    private var description: String
    private var path: String
    private var storageType: StorageType
    private var privacyType: PrivacyType

    init(description: String, path: String, storageType: StorageType, privacyType: PrivacyType) {
        self.description = description
        self.path = path
        self.storageType = storageType
        self.privacyType = privacyType
    }

    init() {
        self.description = ""
        self.path = ""
        self.storageType = .INTERNAL
        self.privacyType = .PRIVATE
    }

    func getDescription() -> String {
        return self.description
    }

    func getPath() -> String {
        return self.path
    }

    func getStorageType() -> StorageType {
        return self.storageType
    }

    func getPrivacyType() -> PrivacyType {
        return self.privacyType
    }

    func setDescription(_ description: String) {
        self.description = description
    }

    func setPath(_ path: String) {
        self.path = path
    }

    func setStorageType(storageType: StorageType) {
        self.storageType = storageType
    }

    func setPrivacyType(_ privacyType: PrivacyType) {
        self.privacyType = privacyType
    }

    enum StorageType {
        case INTERNAL, EXTERNAL
    }

    enum PrivacyType {
        case PRIVATE, PUBLIC
    }

    static func < (lhs: StoragePoint, rhs: StoragePoint) -> Bool {
        return lhs.path < rhs.path
    }

    static func == (lhs: StoragePoint, rhs: StoragePoint) -> Bool {
        return lhs.path == rhs.path
    }
}
