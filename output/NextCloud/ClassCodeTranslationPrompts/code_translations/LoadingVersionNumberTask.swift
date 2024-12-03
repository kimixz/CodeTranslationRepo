
import Foundation

class LoadingVersionNumberTask {
    private let callback: VersionDevInterface
    
    init(callback: VersionDevInterface) {
        self.callback = callback
    }
    
    func doInBackground(args: String...) -> Int {
        do {
            guard let url = URL(string: args[0]) else {
                print("Malformed URL")
                return -1
            }
            let charset = String.Encoding.utf8
            do {
                let content = try String(contentsOf: url, encoding: charset)
                if let versionNumber = Int(content.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return versionNumber
                }
            } catch {
                print("Error loading version number: \(error)")
            }
        } catch {
            print("Malformed URL: \(error)")
        }
        return -1
    }
    
    func onPostExecute(_ latestVersion: Int?) {
        callback.returnVersion(latestVersion)
    }
    
    protocol VersionDevInterface {
        func returnVersion(latestVersion: Int?)
    }
}
