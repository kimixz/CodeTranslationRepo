
import Foundation

class DataHolderUtil {
    private var data = [String: WeakReference<AnyObject>]()
    private static var instance: DataHolderUtil?
    private var random = SecureRandom()

    static func getInstance() -> DataHolderUtil {
        if instance == nil {
            instance = DataHolderUtil()
        }
        return instance!
    }

    func save(id: String, object: AnyObject) {
        data[id] = WeakReference(object)
    }

    func retrieve(id: String) -> AnyObject? {
        let objectWeakReference = data[id]
        return objectWeakReference?.value
    }

    func delete(id: String?) {
        if let id = id {
            data.removeValue(forKey: id)
        }
    }

    func nextItemId() -> String {
        var nextItemId = BigInt.randomInteger(withExactWidth: 130, using: &random).toString(radix: 32)
        while data.keys.contains(nextItemId) {
            nextItemId = BigInt.randomInteger(withExactWidth: 130, using: &random).toString(radix: 32)
        }
        return nextItemId
    }
}

class WeakReference<T: AnyObject> {
    weak var value: T?

    init(_ value: T) {
        self.value = value
    }
}

class SecureRandom {
    func nextBytes(_ bytes: inout [UInt8]) {
        for i in 0..<bytes.count {
            bytes[i] = UInt8.random(in: 0...255)
        }
    }
}

struct BigInt {
    static func randomInteger(withExactWidth width: Int, using random: inout SecureRandom) -> BigInt {
        var bytes = [UInt8](repeating: 0, count: (width + 7) / 8)
        random.nextBytes(&bytes)
        return BigInt(bytes: bytes)
    }

    private var bytes: [UInt8]

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    func toString(radix: Int) -> String {
        return bytes.map { String($0, radix: radix) }.joined()
    }
}
