
import Foundation

class AbstractCommandLineStoragePoint: AbstractStoragePointProvider {
    private static let TAG = String(describing: AbstractCommandLineStoragePoint.self)
    private static let COMMAND_LINE_OK_RETURN_VALUE: Int32 = 0

    internal func getCommand() -> [String] {
        fatalError("This method must be overridden")
    }

    override func canProvideStoragePoints() -> Bool {
        var process: Process?
        do {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: getCommand().first ?? "")
            task.arguments = Array(getCommand().dropFirst())
            try task.run()
            task.waitUntilExit()
            process = task
        } catch {
            return false
        }
        return process != nil && process!.terminationStatus == AbstractCommandLineStoragePoint.COMMAND_LINE_OK_RETURN_VALUE
    }

    func getCommandLineResult() -> String {
        var result = ""
        do {
            let process = Process()
            process.launchPath = "/usr/bin/env"
            process.arguments = getCommand()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                result = output
            }
        } catch {
            print("Error retrieving command line results: \(error)")
        }
        return result
    }
}
