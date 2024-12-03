
enum UploadResult: Int {
    case unknown = -1
    case uploaded = 0
    case networkConnection = 1
    case credentialError = 2
    case folderError = 3
    case conflictError = 4
    case fileError = 5
    case privilegesError = 6
    case cancelled = 7
    case fileNotFound = 8
    case delayedForWifi = 9
    case serviceInterrupted = 10
    case delayedForCharging = 11
    case maintenanceMode = 12
    case lockFailed = 13
    case delayedInPowerSaveMode = 14
    case sslRecoverablePeerUnverified = 15
    case virusDetected = 16
    case localStorageFull = 17
    case oldAndroidApi = 18
    case syncConflict = 19
    case cannotCreateFile = 20
    case localStorageNotCopied = 21
    case quotaExceeded = 22
    case sameFileConflict = 23

    func getValue() -> Int {
        return self.rawValue
    }

    static func fromValue(_ value: Int) -> UploadResult {
        return UploadResult(rawValue: value) ?? .unknown
    }

    static func fromOperationResult(_ result: RemoteOperationResult) -> UploadResult {
        switch result.code {
        case .ok:
            return .uploaded
        case .noNetworkConnection, .hostNotAvailable, .timeout, .wrongConnection, .incorrectAddress, .sslError:
            return .networkConnection
        case .accountException, .unauthorized:
            return .credentialError
        case .fileNotFound:
            return .folderError
        case .localFileNotFound:
            return .fileNotFound
        case .conflict:
            return .conflictError
        case .localStorageNotCopied:
            return .localStorageNotCopied
        case .localStorageFull:
            return .localStorageFull
        case .oldAndroidApi:
            return .oldAndroidApi
        case .syncConflict:
            return .syncConflict
        case .forbidden:
            return .privilegesError
        case .cancelled:
            return .cancelled
        case .delayedForWifi:
            return .delayedForWifi
        case .delayedForCharging:
            return .delayedForCharging
        case .delayedInPowerSaveMode:
            return .delayedInPowerSaveMode
        case .maintenanceMode:
            return .maintenanceMode
        case .sslRecoverablePeerUnverified:
            return .sslRecoverablePeerUnverified
        case .unknownError:
            if result.exception is FileNotFoundException {
                return .fileError
            }
            return .unknown
        case .lockFailed:
            return .lockFailed
        case .virusDetected:
            return .virusDetected
        case .cannotCreateFile:
            return .cannotCreateFile
        case .quotaExceeded:
            return .quotaExceeded
        default:
            return .unknown
        }
    }
}
