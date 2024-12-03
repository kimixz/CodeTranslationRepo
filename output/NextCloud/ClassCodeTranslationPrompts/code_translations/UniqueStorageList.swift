
import Foundation

class UniqueStorageList: NSMutableArray {
    override func add(_ sp: Any) -> Bool {
        guard let sp = sp as? StoragePoint else { return false }
        do {
            for case let s as StoragePoint in self {
                let thisCanonPath = try FileManager.default.destinationOfSymbolicLink(atPath: s.getPath())
                let otherCanonPath = try FileManager.default.destinationOfSymbolicLink(atPath: sp.getPath())
                if thisCanonPath == otherCanonPath {
                    return true
                }
            }
        } catch {
            return false
        }
        super.add(sp)
        return true
    }

    override func addObjects(from collection: [Any]) {
        for case let sp as StoragePoint in collection {
            add(sp)
        }
    }
}
