
import Foundation

final class FileUtil {
    
    private init() {
        // utility class -> private constructor
    }
    
    /**
     * returns the file name of a given path.
     *
     * @param filePath (absolute) file path
     * @return the filename including its file extension, <code>empty String</code> for invalid input values
     */
    static func getFilenameFromPathString(_ filePath: String?) -> String {
        if let filePath = filePath, !filePath.isEmpty {
            let file = URL(fileURLWithPath: filePath)
            if file.hasDirectoryPath == false {
                return file.lastPathComponent
            } else {
                return ""
            }
        } else {
            return ""
        }
    }
    
    static func getCreationTimestamp(file: URL) -> Int64? {
        if #available(iOS 11.0, *) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                if let creationDate = attributes[.creationDate] as? Date {
                    return Int64(creationDate.timeIntervalSince1970)
                }
            } catch {
                print("Failed to read creation timestamp for file: \(file.lastPathComponent)")
                return nil
            }
        }
        return nil
    }
}
