
import Foundation

class MountCommandStoragePointProvider: AbstractCommandLineStoragePoint {
    
    private static let sCommand = ["mount"]
    
    private static let sPattern = try! NSRegularExpression(pattern: "(?i).*vold.*(vfat|ntfs|exfat|fat32|ext3|ext4).*rw.*", options: [])
    
    override func getCommand() -> [String] {
        return MountCommandStoragePointProvider.sCommand
    }
    
    override func getAvailableStoragePoint() -> [StoragePoint] {
        var result: [StoragePoint] = []
        
        for p in getPotentialPaths(getCommandLineResult()) {
            if canBeAddedToAvailableList(result, p) {
                result.append(StoragePoint(path: p, name: p, type: .external, privacy: .public))
            }
        }
        
        return result
    }
    
    private func getPotentialPaths(_ mounted: String) -> [String] {
        var result: [String] = []
        
        for line in mounted.split(separator: "\n") {
            if !line.lowercased().contains("asec") && MountCommandStoragePointProvider.sPattern.matches(String(line)) {
                let parts = line.split(separator: " ")
                for path in parts {
                    if path.count > 0 && path.first == "/" && !path.lowercased().contains("vold") {
                        result.append(String(path))
                    }
                }
            }
        }
        return result
    }
}

extension NSRegularExpression {
    func matches(_ string: String) -> Bool {
        let range = NSRange(location: 0, length: string.utf16.count)
        return firstMatch(in: string, options: [], range: range) != nil
    }
}
