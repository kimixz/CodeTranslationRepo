
import Foundation

class ArbitraryDataProviderImpl: ArbitraryDataProvider {
    
    private static let TRUE = "true"
    
    private let arbitraryDataDao: ArbitraryDataDao
    
    @available(*, deprecated, message: "inject interface instead")
    init(context: Context) {
        self.arbitraryDataDao = NextcloudDatabase.getInstance(context).arbitraryDataDao()
    }
    
    init(dao: ArbitraryDataDao) {
        self.arbitraryDataDao = dao
    }
    
    func deleteKeyForAccount(account: String, key: String) {
        arbitraryDataDao.deleteValue(account: account, key: key)
    }
    
    func storeOrUpdateKeyValue(accountName: String, key: String, newValue: Int64) {
        storeOrUpdateKeyValue(accountName: accountName, key: key, newValue: String(newValue))
    }
    
    func incrementValue(accountName: String, key: String) {
        let oldValue = getIntegerValue(accountName: accountName, key: key)
        
        var value = 1
        if oldValue > 0 {
            value = oldValue + 1
        }
        storeOrUpdateKeyValue(accountName: accountName, key: key, newValue: value)
    }
    
    func storeOrUpdateKeyValue(accountName: String, key: String, newValue: Bool) {
        storeOrUpdateKeyValue(accountName: accountName, key: key, newValue: String(newValue))
    }
    
    func storeOrUpdateKeyValue(accountName: String, key: String, newValue: String?) {
        if let currentValue = arbitraryDataDao.getByAccountAndKey(accountName: accountName, key: key) {
            arbitraryDataDao.updateValue(accountName: accountName, key: key, newValue: newValue)
        } else {
            arbitraryDataDao.insertValue(accountName: accountName, key: key, newValue: newValue)
        }
    }
    
    func storeOrUpdateKeyValue(user: User, key: String, newValue: String) {
        storeOrUpdateKeyValue(accountName: user.getAccountName(), key: key, newValue: newValue)
    }
    
    func getLongValue(accountName: String, key: String) -> Int64 {
        let value = getValue(accountName: accountName, key: key)
        
        if value.isEmpty {
            return -1
        } else {
            return Int64(value) ?? -1
        }
    }
    
    func getLongValue(user: User, key: String) -> Int64 {
        return getLongValue(accountName: user.getAccountName(), key: key)
    }
    
    func getBooleanValue(accountName: String, key: String) -> Bool {
        return getValue(accountName: accountName, key: key).caseInsensitiveCompare(ArbitraryDataProviderImpl.TRUE) == .orderedSame
    }
    
    func getBooleanValue(user: User, key: String) -> Bool {
        return getBooleanValue(accountName: user.getAccountName(), key: key)
    }
    
    func getIntegerValue(accountName: String, key: String) -> Int {
        let value = getValue(accountName: accountName, key: key)
        
        if value.isEmpty {
            return -1
        } else {
            return Int(value) ?? -1
        }
    }
    
    func getValue(user: User?, key: String) -> String {
        return user != nil ? getValue(accountName: user!.getAccountName(), key: key) : ""
    }
    
    func getValue(accountName: String, key: String) -> String {
        guard let entity = arbitraryDataDao.getByAccountAndKey(accountName: accountName, key: key), let value = entity.getValue() else {
            return ""
        }
        return value
    }
}
