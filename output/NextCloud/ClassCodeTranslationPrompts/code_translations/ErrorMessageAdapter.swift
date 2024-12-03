
import Foundation

final class ErrorMessageAdapter {

    private init() {
        // utility class -> private constructor
    }

    static func getErrorCauseMessage(result: RemoteOperationResult, operation: RemoteOperation, res: Resources) -> String {
        var message = getMessageForResultAndOperation(result: result, operation: operation, res: res)

        if message.isEmpty {
            message = getMessageForResult(result: result, res: res)
        }

        if message.isEmpty {
            message = getMessageForOperation(operation: operation, res: res)
        }

        if message.isEmpty {
            if result.isSuccess {
                message = res.getString(R.string.common_ok)
            } else {
                message = res.getString(R.string.common_error_unknown)
            }
        }

        return message
    }

    private static func getMessageForResultAndOperation(result: RemoteOperationResult, operation: RemoteOperation, res: Resources) -> String? {
        var message: String? = nil

        if let uploadOperation = operation as? UploadFileOperation {
            message = getMessageForUploadFileOperation(result: result, operation: uploadOperation, res: res)

        } else if let downloadOperation = operation as? DownloadFileOperation {
            message = getMessageForDownloadFileOperation(result: result, operation: downloadOperation, res: res)

        } else if operation is RemoveFileOperation {
            message = getMessageForRemoveFileOperation(result: result, res: res)

        } else if operation is RenameFileOperation {
            message = getMessageForRenameFileOperation(result: result, res: res)

        } else if let syncOperation = operation as? SynchronizeFileOperation {
            if !syncOperation.transferWasRequested() {
                message = res.getString(R.string.sync_file_nothing_to_do_msg)
            }

        } else if operation is CreateFolderOperation {
            message = getMessageForCreateFolderOperation(result: result, res: res)

        } else if operation is CreateShareViaLinkOperation || operation is CreateShareWithShareeOperation {
            message = getMessageForCreateShareOperations(result: result, res: res)

        } else if operation is UnshareOperation {
            message = getMessageForUnshareOperation(result: result, res: res)

        } else if operation is UpdateShareViaLinkOperation || operation is UpdateSharePermissionsOperation {
            message = getMessageForUpdateShareOperations(result: result, res: res)

        } else if operation is MoveFileOperation {
            message = getMessageForMoveFileOperation(result: result, res: res)

        } else if let syncFolderOperation = operation as? SynchronizeFolderOperation {
            message = getMessageForSynchronizeFolderOperation(result: result, operation: syncFolderOperation, res: res)

        } else if operation is CopyFileOperation {
            message = getMessageForCopyFileOperation(result: result, res: res)
        }

        return message
    }

    private static func getMessageForSynchronizeFolderOperation(result: RemoteOperationResult, operation: SynchronizeFolderOperation, res: Resources) -> String? {
        if !result.isSuccess() && result.getCode() == .fileNotFound {
            return String(format: res.getString(R.string.sync_current_folder_was_removed), URL(fileURLWithPath: operation.getFolderPath()).lastPathComponent)
        }
        return nil
    }

    private static func getMessageForMoveFileOperation(result: RemoteOperationResult, res: Resources) -> String? {
        switch result.code {
        case .fileNotFound:
            return res.getString(R.string.move_file_not_found)
        case .invalidMoveIntoDescendant:
            return res.getString(R.string.move_file_invalid_into_descendent)
        case .invalidOverwrite:
            return res.getString(R.string.move_file_invalid_overwrite)
        case .forbidden:
            return String(format: res.getString(R.string.forbidden_permissions), res.getString(R.string.forbidden_permissions_move))
        case .invalidCharacterDetectInServer:
            return res.getString(R.string.filename_forbidden_charaters_from_server)
        default:
            return nil
        }
    }

    private static func getMessageForUpdateShareOperations(result: RemoteOperationResult, res: Resources) -> String? {
        if !result.getMessage().isEmpty {
            return result.getMessage() // share API sends its own error messages
        } else if result.getCode() == .SHARE_NOT_FOUND {
            return res.getString(R.string.update_link_file_no_exist)
        } else if result.getCode() == .SHARE_FORBIDDEN {
            // Error --> No permissions
            return String(format: res.getString(R.string.forbidden_permissions), res.getString(R.string.update_link_forbidden_permissions))
        }
        return nil
    }

    private static func getMessageForUnshareOperation(result: RemoteOperationResult, res: Resources) -> String? {
        if !result.getMessage().isEmpty {
            return result.getMessage() // share API sends its own error messages
        } else if result.getCode() == .SHARE_NOT_FOUND {
            return res.getString(R.string.unshare_link_file_no_exist)
        } else if result.getCode() == .SHARE_FORBIDDEN {
            // Error --> No permissions
            return String(format: res.getString(R.string.forbidden_permissions), res.getString(R.string.unshare_link_forbidden_permissions))
        }
        return nil
    }

    private static func getMessageForCopyFileOperation(result: RemoteOperationResult, res: Resources) -> String? {
        if result.getCode() == .fileNotFound {
            return res.getString(R.string.copy_file_not_found)
        } else if result.getCode() == .invalidCopyIntoDescendant {
            return res.getString(R.string.copy_file_invalid_into_descendent)
        } else if result.getCode() == .invalidOverwrite {
            return res.getString(R.string.copy_file_invalid_overwrite)
        } else if result.getCode() == .forbidden {
            return String(format: res.getString(R.string.forbidden_permissions), res.getString(R.string.forbidden_permissions_copy))
        }
        return nil
    }

    private static func getMessageForCreateShareOperations(result: RemoteOperationResult, res: Resources) -> String? {
        if !result.getMessage().isEmpty {
            return result.getMessage() // share API sends its own error messages
        } else if result.getCode() == .SHARE_NOT_FOUND {
            return res.getString(R.string.share_link_file_no_exist)
        } else if result.getCode() == .SHARE_FORBIDDEN {
            // Error --> No permissions
            return String(format: res.getString(R.string.forbidden_permissions), res.getString(R.string.share_link_forbidden_permissions))
        }
        return nil
    }

    private static func getMessageForCreateFolderOperation(result: RemoteOperationResult, res: Resources) -> String? {
        if result.getCode() == .invalidCharacterInName {
            return res.getString(R.string.filename_forbidden_characters)
        } else if result.getCode() == .forbidden {
            return String(format: res.getString(R.string.forbidden_permissions), res.getString(R.string.forbidden_permissions_create))
        } else if result.getCode() == .invalidCharacterDetectInServer {
            return res.getString(R.string.filename_forbidden_charaters_from_server)
        }
        return nil
    }

    private static func getMessageForRenameFileOperation(result: RemoteOperationResult, res: Resources) -> String? {
        if result.getCode() == .invalidLocalFileName {
            return res.getString(R.string.rename_local_fail_msg)
        } else if result.getCode() == .forbidden {
            // Error --> No permissions
            return String(format: res.getString(R.string.forbidden_permissions), res.getString(R.string.forbidden_permissions_rename))
        } else if result.getCode() == .invalidCharacterInName {
            return res.getString(R.string.filename_forbidden_characters)
        } else if result.getCode() == .invalidCharacterDetectInServer {
            return res.getString(R.string.filename_forbidden_charaters_from_server)
        }
        return nil
    }

    private static func getMessageForRemoveFileOperation(result: RemoteOperationResult, res: Resources) -> String? {
        if result.isSuccess() {
            return res.getString(R.string.remove_success_msg)
        } else {
            if result.getCode() == ResultCode.FORBIDDEN {
                return String(format: res.getString(R.string.forbidden_permissions), res.getString(R.string.forbidden_permissions_delete))
            } else if result.getCode() == ResultCode.LOCKED {
                return res.getString(R.string.preview_media_unhandled_http_code_message)
            }
        }
        return nil
    }

    private static func getMessageForDownloadFileOperation(result: RemoteOperationResult, operation: DownloadFileOperation, res: Resources) -> String? {
        if result.isSuccess() {
            return String(format: res.getString(R.string.downloader_download_succeeded_content), URL(fileURLWithPath: operation.getSavePath()).lastPathComponent)
        } else {
            switch result.getCode() {
            case .FILE_NOT_FOUND:
                return res.getString(R.string.downloader_download_file_not_found)
            case .CANNOT_CREATE_FILE:
                return res.getString(R.string.download_cannot_create_file)
            case .INVALID_LOCAL_FILE_NAME:
                return res.getString(R.string.download_download_invalid_local_file_name)
            default:
                return nil
            }
        }
    }

    private static func getMessageForUploadFileOperation(result: RemoteOperationResult, operation: UploadFileOperation, res: Resources) -> String? {
        if result.isSuccess() {
            return String(format: res.getString(R.string.uploader_upload_succeeded_content_single), operation.getFileName())
        } else {
            switch result.getCode() {
            case .LOCAL_STORAGE_FULL, .LOCAL_STORAGE_NOT_COPIED:
                return String(format: res.getString(R.string.error__upload__local_file_not_copied), operation.getFileName(), res.getString(R.string.app_name))
            case .FORBIDDEN:
                return String(format: res.getString(R.string.forbidden_permissions), res.getString(R.string.uploader_upload_forbidden_permissions))
            case .INVALID_CHARACTER_DETECT_IN_SERVER:
                return res.getString(R.string.filename_forbidden_charaters_from_server)
            case .SYNC_CONFLICT:
                return String(format: res.getString(R.string.uploader_upload_failed_sync_conflict_error_content), operation.getFileName())
            default:
                return nil
            }
        }
    }

    private static func getMessageForResult(result: RemoteOperationResult, res: Resources) -> String? {
        var message: String? = nil

        if !result.isSuccess() {
            switch result.getCode() {
            case .WRONG_CONNECTION:
                message = res.getString(R.string.network_error_socket_exception)
            case .TIMEOUT:
                message = res.getString(R.string.network_error_socket_exception)
                if result.getException() is SocketTimeoutException {
                    message = res.getString(R.string.network_error_socket_timeout_exception)
                } else if result.getException() is ConnectTimeoutException {
                    message = res.getString(R.string.network_error_connect_timeout_exception)
                }
            case .HOST_NOT_AVAILABLE:
                message = res.getString(R.string.network_host_not_available)
            case .MAINTENANCE_MODE:
                message = res.getString(R.string.maintenance_mode)
            case .SSL_RECOVERABLE_PEER_UNVERIFIED:
                message = res.getString(R.string.uploads_view_upload_status_failed_ssl_certificate_not_trusted)
            case .BAD_OC_VERSION:
                message = res.getString(R.string.auth_bad_oc_version_title)
            case .INCORRECT_ADDRESS:
                message = res.getString(R.string.auth_incorrect_address_title)
            case .SSL_ERROR:
                message = res.getString(R.string.auth_ssl_general_error_title)
            case .UNAUTHORIZED:
                message = res.getString(R.string.auth_unauthorized)
            case .INSTANCE_NOT_CONFIGURED:
                message = res.getString(R.string.auth_not_configured_title)
            case .FILE_NOT_FOUND:
                message = res.getString(R.string.file_not_found)
            case .OAUTH2_ERROR:
                message = res.getString(R.string.auth_oauth_error)
            case .OAUTH2_ERROR_ACCESS_DENIED:
                message = res.getString(R.string.auth_oauth_error_access_denied)
            case .ACCOUNT_NOT_NEW:
                message = res.getString(R.string.auth_account_not_new)
            case .ACCOUNT_NOT_THE_SAME:
                message = res.getString(R.string.auth_account_not_the_same)
            case .QUOTA_EXCEEDED:
                message = res.getString(R.string.upload_quota_exceeded)
            default:
                break
            }

            if message == nil, !result.getHttpPhrase().isEmpty {
                message = result.getHttpPhrase()
            }
        }

        return message
    }

    private static func getMessageForOperation(_ operation: RemoteOperation, _ res: Resources) -> String? {
        var message: String? = nil

        if let uploadOperation = operation as? UploadFileOperation {
            message = String(format: res.getString(R.string.uploader_upload_failed_content_single), uploadOperation.getFileName())

        } else if let downloadOperation = operation as? DownloadFileOperation {
            let fileName = URL(fileURLWithPath: downloadOperation.getSavePath()).lastPathComponent
            message = String(format: res.getString(R.string.downloader_download_failed_content), fileName)

        } else if operation is RemoveFileOperation {
            message = res.getString(R.string.remove_fail_msg)

        } else if operation is RenameFileOperation {
            message = res.getString(R.string.rename_server_fail_msg)

        } else if operation is CreateFolderOperation {
            message = res.getString(R.string.create_dir_fail_msg)

        } else if operation is CreateShareViaLinkOperation || operation is CreateShareWithShareeOperation {
            message = res.getString(R.string.share_link_file_error)

        } else if operation is UnshareOperation {
            message = res.getString(R.string.unshare_link_file_error)

        } else if operation is UpdateShareViaLinkOperation || operation is UpdateSharePermissionsOperation {
            message = res.getString(R.string.update_link_file_error)

        } else if operation is MoveFileOperation {
            message = res.getString(R.string.move_file_error)

        } else if let syncOperation = operation as? SynchronizeFolderOperation {
            let folderPathName = URL(fileURLWithPath: syncOperation.getFolderPath()).lastPathComponent
            message = String(format: res.getString(R.string.sync_folder_failed_content), folderPathName)

        } else if operation is CopyFileOperation {
            message = res.getString(R.string.copy_file_error)
        }

        return message
    }
}
