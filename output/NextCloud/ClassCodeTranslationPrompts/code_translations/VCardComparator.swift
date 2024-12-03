
import Foundation

class VCardComparator: Comparator {
    func compare(_ o1: VCard, _ o2: VCard) -> Int {
        let contact1 = BackupListFragment.getDisplayName(o1)
        let contact2 = BackupListFragment.getDisplayName(o2)
        
        return contact1.caseInsensitiveCompare(contact2).rawValue
    }
}
