
import Foundation

class SystemDefaultStoragePointProvider: AbstractStoragePointProvider {
    override func canProvideStoragePoints() -> Bool {
        return true
    }
    
    override func getAvailableStoragePoint() -> [StoragePoint] {
        var result: [StoragePoint] = []
        
        let defaultStringDesc = MainApp.string(R.string.storage_description_default)
        // Add private internal storage data directory.
        result.append(StoragePoint(description: defaultStringDesc,
                                   path: MainApp.getAppContext().filesDir.path,
                                   storageType: .internal,
                                   privacyType: .private))
        
        return result
    }
}
