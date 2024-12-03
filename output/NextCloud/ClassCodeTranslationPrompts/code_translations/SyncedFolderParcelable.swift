
import Foundation

class SyncedFolderParcelable: NSObject, NSCoding {
    private var folderName: String?
    private var localPath: String?
    private var remotePath: String?
    private var wifiOnly: Bool = false
    private var chargingOnly: Bool = false
    private var existing: Bool = true
    private var enabled: Bool = false
    private var subfolderByDate: Bool = false
    private var uploadAction: Int?
    private var nameCollisionPolicy: NameCollisionPolicy = .askUser
    private var type: MediaFolderType?
    private var hidden: Bool = false
    private var id: Int64 = 0
    private var account: String?
    private var section: Int = 0
    private var subFolderRule: SubFolderRule?
    private var excludeHidden: Bool = false

    init(syncedFolderDisplayItem: SyncedFolderDisplayItem, section: Int) {
        self.id = syncedFolderDisplayItem.getId()
        self.folderName = syncedFolderDisplayItem.getFolderName()
        self.localPath = syncedFolderDisplayItem.getLocalPath()
        self.remotePath = syncedFolderDisplayItem.getRemotePath()
        self.wifiOnly = syncedFolderDisplayItem.isWifiOnly()
        self.chargingOnly = syncedFolderDisplayItem.isChargingOnly()
        self.existing = syncedFolderDisplayItem.isExisting()
        self.enabled = syncedFolderDisplayItem.isEnabled()
        self.subfolderByDate = syncedFolderDisplayItem.isSubfolderByDate()
        self.type = syncedFolderDisplayItem.getType()
        self.account = syncedFolderDisplayItem.getAccount()
        self.uploadAction = syncedFolderDisplayItem.getUploadAction()
        self.nameCollisionPolicy = NameCollisionPolicy.deserialize(syncedFolderDisplayItem.getNameCollisionPolicyInt())
        self.section = section
        self.hidden = syncedFolderDisplayItem.isHidden()
        self.subFolderRule = syncedFolderDisplayItem.getSubfolderRule()
        self.excludeHidden = syncedFolderDisplayItem.isExcludeHidden()
    }

    required init?(coder aDecoder: NSCoder) {
        self.id = aDecoder.decodeInt64(forKey: "id")
        self.folderName = aDecoder.decodeObject(forKey: "folderName") as? String
        self.localPath = aDecoder.decodeObject(forKey: "localPath") as? String
        self.remotePath = aDecoder.decodeObject(forKey: "remotePath") as? String
        self.wifiOnly = aDecoder.decodeBool(forKey: "wifiOnly")
        self.chargingOnly = aDecoder.decodeBool(forKey: "chargingOnly")
        self.existing = aDecoder.decodeBool(forKey: "existing")
        self.enabled = aDecoder.decodeBool(forKey: "enabled")
        self.subfolderByDate = aDecoder.decodeBool(forKey: "subfolderByDate")
        self.type = MediaFolderType.getById(aDecoder.decodeInteger(forKey: "type"))
        self.account = aDecoder.decodeObject(forKey: "account") as? String
        self.uploadAction = aDecoder.decodeObject(forKey: "uploadAction") as? Int
        self.nameCollisionPolicy = NameCollisionPolicy.deserialize(aDecoder.decodeInteger(forKey: "nameCollisionPolicy"))
        self.section = aDecoder.decodeInteger(forKey: "section")
        self.hidden = aDecoder.decodeBool(forKey: "hidden")
        self.subFolderRule = SubFolderRule(rawValue: aDecoder.decodeInteger(forKey: "subFolderRule"))
        self.excludeHidden = aDecoder.decodeBool(forKey: "excludeHidden")
    }

    func encode(with aCoder: NSCoder) {
        aCoder.encode(id, forKey: "id")
        aCoder.encode(folderName, forKey: "folderName")
        aCoder.encode(localPath, forKey: "localPath")
        aCoder.encode(remotePath, forKey: "remotePath")
        aCoder.encode(wifiOnly, forKey: "wifiOnly")
        aCoder.encode(chargingOnly, forKey: "chargingOnly")
        aCoder.encode(existing, forKey: "existing")
        aCoder.encode(enabled, forKey: "enabled")
        aCoder.encode(subfolderByDate, forKey: "subfolderByDate")
        aCoder.encode(type?.id, forKey: "type")
        aCoder.encode(account, forKey: "account")
        aCoder.encode(uploadAction, forKey: "uploadAction")
        aCoder.encode(nameCollisionPolicy.serialize(), forKey: "nameCollisionPolicy")
        aCoder.encode(section, forKey: "section")
        aCoder.encode(hidden, forKey: "hidden")
        aCoder.encode(subFolderRule?.rawValue, forKey: "subFolderRule")
        aCoder.encode(excludeHidden, forKey: "excludeHidden")
    }

    func getUploadActionInteger() -> Int {
        switch uploadAction {
        case FileUploadWorker.LOCAL_BEHAVIOUR_FORGET:
            return 0
        case FileUploadWorker.LOCAL_BEHAVIOUR_MOVE:
            return 1
        case FileUploadWorker.LOCAL_BEHAVIOUR_DELETE:
            return 2
        default:
            return 0
        }
    }

    func setUploadAction(_ uploadAction: String) {
        switch uploadAction {
        case "LOCAL_BEHAVIOUR_FORGET":
            self.uploadAction = FileUploadWorker.LOCAL_BEHAVIOUR_FORGET
        case "LOCAL_BEHAVIOUR_MOVE":
            self.uploadAction = FileUploadWorker.LOCAL_BEHAVIOUR_MOVE
        case "LOCAL_BEHAVIOUR_DELETE":
            self.uploadAction = FileUploadWorker.LOCAL_BEHAVIOUR_DELETE
        default:
            break
        }
    }

    func getFolderName() -> String? {
        return self.folderName
    }

    func getLocalPath() -> String? {
        return self.localPath
    }

    func getRemotePath() -> String? {
        return self.remotePath
    }

    func isWifiOnly() -> Bool {
        return self.wifiOnly
    }

    func isChargingOnly() -> Bool {
        return self.chargingOnly
    }

    func isExisting() -> Bool {
        return self.existing
    }

    func isEnabled() -> Bool {
        return self.enabled
    }

    func isSubfolderByDate() -> Bool {
        return self.subfolderByDate
    }

    func getUploadAction() -> Int? {
        return self.uploadAction
    }

    func getNameCollisionPolicy() -> NameCollisionPolicy {
        return self.nameCollisionPolicy
    }

    func getType() -> MediaFolderType? {
        return self.type
    }

    func isHidden() -> Bool {
        return self.hidden
    }

    func getId() -> Int64 {
        return self.id
    }

    func getAccount() -> String? {
        return self.account
    }

    func getSection() -> Int {
        return self.section
    }

    func getSubFolderRule() -> SubFolderRule? {
        return self.subFolderRule
    }

    func setFolderName(_ folderName: String) {
        self.folderName = folderName
    }

    func setLocalPath(_ localPath: String) {
        self.localPath = localPath
    }

    func setRemotePath(_ remotePath: String) {
        self.remotePath = remotePath
    }

    func setWifiOnly(_ wifiOnly: Bool) {
        self.wifiOnly = wifiOnly
    }

    func setChargingOnly(_ chargingOnly: Bool) {
        self.chargingOnly = chargingOnly
    }

    func setExisting(_ existing: Bool) {
        self.existing = existing
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    func setSubfolderByDate(_ subfolderByDate: Bool) {
        self.subfolderByDate = subfolderByDate
    }

    func setNameCollisionPolicy(_ nameCollisionPolicy: NameCollisionPolicy) {
        self.nameCollisionPolicy = nameCollisionPolicy
    }

    func setType(_ type: MediaFolderType) {
        self.type = type
    }

    func setHidden(_ hidden: Bool) {
        self.hidden = hidden
    }

    func setId(_ id: Int64) {
        self.id = id
    }

    func setAccount(_ account: String) {
        self.account = account
    }

    func setSection(_ section: Int) {
        self.section = section
    }

    func setSubFolderRule(_ subFolderRule: SubFolderRule) {
        self.subFolderRule = subFolderRule
    }

    func isExcludeHidden() -> Bool {
        return excludeHidden
    }

    func setExcludeHidden(_ excludeHidden: Bool) {
        self.excludeHidden = excludeHidden
    }
}
