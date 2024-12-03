
import Foundation

// Assuming SimpleTarget is a class or protocol in Swift
class MenuSimpleTarget<Z>: SimpleTarget<Z> {
    
    private let mIdMenuItem: Int
    
    init(idMenuItem: Int) {
        self.mIdMenuItem = idMenuItem
        super.init()
    }
    
    func getIdMenuItem() -> Int {
        return mIdMenuItem
    }
}
