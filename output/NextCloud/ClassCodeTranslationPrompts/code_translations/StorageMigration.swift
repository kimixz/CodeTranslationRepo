
import UIKit

class StorageMigration {
    private static let TAG = String(describing: StorageMigration.self)

    private let mContext: Context
    private let user: User
    private let mSourceStoragePath: String
    private let mTargetStoragePath: String
    private let viewThemeUtils: ViewThemeUtils

    private var mListener: StorageMigrationProgressListener?

    init(context: Context, user: User, sourcePath: String, targetPath: String, viewThemeUtils: ViewThemeUtils) {
        self.mContext = context
        self.user = user
        self.mSourceStoragePath = sourcePath
        self.mTargetStoragePath = targetPath
        self.viewThemeUtils = viewThemeUtils
    }

    func setStorageMigrationProgressListener(listener: StorageMigrationProgressListener?) {
        mListener = listener
    }

    func migrate() {
        if storageFolderAlreadyExists() {
            askToOverride()
        } else {
            let progressDialog = createMigrationProgressDialog()
            progressDialog.show()
            let fileMigrationTask = FileMigrationTask(
                context: mContext,
                user: user,
                sourceStoragePath: mSourceStoragePath,
                targetStoragePath: mTargetStoragePath,
                progressDialog: progressDialog,
                listener: mListener,
                viewThemeUtils: viewThemeUtils)
            fileMigrationTask.execute()

            progressDialog.button(for: .positive)?.isHidden = true
        }
    }

    private func storageFolderAlreadyExists() -> Bool {
        let fileManager = FileManager.default
        let folderPath = mTargetStoragePath.appendingPathComponent(MainApp.getDataFolder())
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: folderPath.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func a(viewThemeUtils: ViewThemeUtils, context: UIViewController) {
        let alertController = UIAlertController(
            title: nil,
            message: NSLocalizedString("file_migration_directory_already_exists", comment: ""),
            preferredStyle: .alert
        )

        let cancelAction = UIAlertAction(
            title: NSLocalizedString("common_cancel", comment: ""),
            style: .cancel,
            handler: nil
        )

        let useDataFolderAction = UIAlertAction(
            title: NSLocalizedString("file_migration_use_data_folder", comment: ""),
            style: .default,
            handler: nil
        )

        let overrideDataFolderAction = UIAlertAction(
            title: NSLocalizedString("file_migration_override_data_folder", comment: ""),
            style: .default,
            handler: nil
        )

        alertController.addAction(cancelAction)
        alertController.addAction(useDataFolderAction)
        alertController.addAction(overrideDataFolderAction)

        viewThemeUtils.dialog.colorMaterialAlertDialogBackground(context: context, alertController: alertController)

        context.present(alertController, animated: true, completion: nil)
    }

    private func askToOverride() {
        let builder = UIAlertController(title: nil, message: NSLocalizedString("file_migration_directory_already_exists", comment: ""), preferredStyle: .alert)
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("common_cancel", comment: ""), style: .cancel) { _ in
            self.mListener?.onCancelMigration()
        }
        
        let neutralAction = UIAlertAction(title: NSLocalizedString("file_migration_use_data_folder", comment: ""), style: .default) { _ in
            let progressDialog = self.createMigrationProgressDialog()
            progressDialog.show()
            let task = StoragePathSwitchTask(
                context: self.mContext,
                user: self.user,
                sourceStoragePath: self.mSourceStoragePath,
                targetStoragePath: self.mTargetStoragePath,
                progressDialog: progressDialog,
                listener: self.mListener,
                viewThemeUtils: self.viewThemeUtils)
            task.execute()
            
            progressDialog.button(for: .positive)?.isHidden = true
        }
        
        let positiveAction = UIAlertAction(title: NSLocalizedString("file_migration_override_data_folder", comment: ""), style: .default) { _ in
            let progressDialog = self.createMigrationProgressDialog()
            progressDialog.show()
            let task = FileMigrationTask(
                context: self.mContext,
                user: self.user,
                sourceStoragePath: self.mSourceStoragePath,
                targetStoragePath: self.mTargetStoragePath,
                progressDialog: progressDialog,
                listener: self.mListener,
                viewThemeUtils: self.viewThemeUtils)
            task.execute()
            
            progressDialog.button(for: .positive)?.isHidden = true
        }
        
        builder.addAction(cancelAction)
        builder.addAction(neutralAction)
        builder.addAction(positiveAction)
        
        viewThemeUtils.dialog.colorMaterialAlertDialogBackground(context: mContext, builder: builder)
        mContext.present(builder, animated: true, completion: nil)
    }

    private func createMigrationProgressDialog() -> UIAlertController {
        let alertController = UIAlertController(title: NSLocalizedString("file_migration_dialog_title", comment: ""), message: NSLocalizedString("file_migration_preparing", comment: ""), preferredStyle: .alert)
        let closeAction = UIAlertAction(title: NSLocalizedString("drawer_close", comment: ""), style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
        }
        alertController.addAction(closeAction)
        return alertController
    }

    private class FileMigrationTaskBase: AsyncTask<Void, Int, Int> {
        var mStorageSource: String
        var mStorageTarget: String
        var mContext: Context
        var user: User
        var mProgressDialog: ProgressDialog
        var mListener: StorageMigrationProgressListener?

        var mAuthority: String
        var mOcAccounts: [Account]
        var viewThemeUtils: ViewThemeUtils

        init(context: Context,
             user: User,
             source: String,
             target: String,
             progressDialog: ProgressDialog,
             listener: StorageMigrationProgressListener?,
             viewThemeUtils: ViewThemeUtils) throws {
            self.mContext = context
            self.user = user
            self.mStorageSource = source
            self.mStorageTarget = target
            self.mProgressDialog = progressDialog
            self.mListener = listener
            self.viewThemeUtils = viewThemeUtils
            self.mAuthority = mContext.getString(R.string.authority)
            self.mOcAccounts = AccountManager.get(mContext).getAccountsByType(MainApp.getAccountType(context))
        }

        override func onProgressUpdate(_ progress: Int...) {
            if progress.count > 1 && progress[0] != 0 {
                mProgressDialog.message = mContext.getString(progress[0])
            }
        }

        override func onPostExecute(_ code: Int) {
            if code != 0 {
                mProgressDialog.message = mContext.getString(code)
            } else {
                mProgressDialog.message = mContext.getString(R.string.file_migration_ok_finished)
            }

            let succeed = code == 0
            if succeed {
                mProgressDialog.hide()
            } else {
                if code == R.string.file_migration_failed_not_readable {
                    mProgressDialog.hide()
                    askToStillMove()
                } else {
                    mProgressDialog.button(for: .positive)?.isHidden = false
                    mProgressDialog.indeterminateDrawable = ResourcesCompat.getDrawable(mContext.resources, R.drawable.image_fail, nil)
                }
            }

            if let listener = mListener {
                listener.onStorageMigrationFinished(succeed ? mStorageTarget : mStorageSource, succeed)
            }
        }

        private func askToStillMove() {
            let alertController = UIAlertController(
                title: NSLocalizedString("file_migration_source_not_readable_title", comment: ""),
                message: String(format: NSLocalizedString("file_migration_source_not_readable", comment: ""), mStorageTarget),
                preferredStyle: .alert
            )
            
            let noAction = UIAlertAction(
                title: NSLocalizedString("common_no", comment: ""),
                style: .cancel,
                handler: { _ in
                    alertController.dismiss(animated: true, completion: nil)
                }
            )
            
            let yesAction = UIAlertAction(
                title: NSLocalizedString("common_yes", comment: ""),
                style: .default,
                handler: { _ in
                    if let listener = self.mListener {
                        listener.onStorageMigrationFinished(mStorageTarget, true)
                    }
                }
            )
            
            alertController.addAction(noAction)
            alertController.addAction(yesAction)
            
            viewThemeUtils.dialog.colorMaterialAlertDialogBackground(mContext, alertController)
            mContext.present(alertController, animated: true, completion: nil)
        }

        func saveAccountsSyncStatus() -> [Bool] {
            var syncs = [Bool](repeating: false, count: mOcAccounts.count)
            for i in 0..<mOcAccounts.count {
                syncs[i] = ContentResolver.getSyncAutomatically(mOcAccounts[i], mAuthority)
            }
            return syncs
        }

        func stopAccountsSyncing() {
            for ocAccount in mOcAccounts {
                ContentResolver.setSyncAutomatically(account: ocAccount, authority: mAuthority, sync: false)
            }
        }

        func waitForUnfinishedSynchronizations() {
            for ocAccount in mOcAccounts {
                while ContentResolver.isSyncActive(ocAccount, mAuthority) {
                    do {
                        try Thread.sleep(forTimeInterval: 1.0)
                    } catch {
                        print("Thread interrupted while waiting for account to end syncing")
                        Thread.current.cancel()
                    }
                }
            }
        }

        func restoreAccountsSyncStatus(_ oldSync: Bool?...) {
            guard let oldSync = oldSync else {
                return
            }
            for i in 0..<mOcAccounts.count {
                ContentResolver.setSyncAutomatically(account: mOcAccounts[i], authority: mAuthority, sync: oldSync[i])
            }
        }
    }

    private class StoragePathSwitchTask: FileMigrationTaskBase {
        override func doInBackground(_ voids: Void...) -> Int {
            publishProgress(R.string.file_migration_preparing)

            var syncStates: [Bool]? = nil
            do {
                publishProgress(R.string.file_migration_saving_accounts_configuration)
                syncStates = saveAccountsSyncStatus()

                publishProgress(R.string.file_migration_waiting_for_unfinished_sync)
                stopAccountsSyncing()
                waitForUnfinishedSynchronizations()
            } finally {
                publishProgress(R.string.file_migration_restoring_accounts_configuration)
                restoreAccountsSyncStatus(syncStates)
            }

            return 0
        }
    }

    private class FileMigrationTask: FileMigrationTaskBase {
        private class MigrationException: Error {
            private let mResId: Int

            init(resId: Int) {
                self.mResId = resId
            }

            init(resId: Int, _ t: Error) {
                self.mResId = resId
            }

            private func getResId() -> Int { return mResId }
        }

        override func doInBackground(_ args: Void...) -> Int {
            publishProgress(R.string.file_migration_preparing)

            var syncState: [Bool]? = nil

            do {
                let dstFile = File(mStorageTarget + File.separator + MainApp.getDataFolder())
                deleteRecursive(dstFile)
                dstFile.delete()

                let srcFile = File(mStorageSource + File.separator + MainApp.getDataFolder())
                srcFile.mkdirs()

                publishProgress(R.string.file_migration_checking_destination)

                try checkDestinationAvailability()

                publishProgress(R.string.file_migration_saving_accounts_configuration)
                syncState = saveAccountsSyncStatus()

                publishProgress(R.string.file_migration_waiting_for_unfinished_sync)
                stopAccountsSyncing()
                waitForUnfinishedSynchronizations()

                publishProgress(R.string.file_migration_migrating)
                try copyFiles()

                publishProgress(R.string.file_migration_updating_index)
                updateIndex(mContext)

                publishProgress(R.string.file_migration_cleaning)
                cleanup()

            } catch let e as MigrationException {
                rollback()
                return e.getResId()
            } finally {
                publishProgress(R.string.file_migration_restoring_accounts_configuration)
                restoreAccountsSyncStatus(syncState)
            }

            publishProgress(R.string.file_migration_ok_finished)

            return 0
        }

        private func checkDestinationAvailability() throws {
            let srcFile = URL(fileURLWithPath: mStorageSource)
            let dstFile = URL(fileURLWithPath: mStorageTarget)

            guard FileManager.default.isReadableFile(atPath: dstFile.path) && FileManager.default.isReadableFile(atPath: srcFile.path) else {
                throw MigrationException(R.string.file_migration_failed_not_readable)
            }

            guard FileManager.default.isWritableFile(atPath: dstFile.path) && FileManager.default.isWritableFile(atPath: srcFile.path) else {
                throw MigrationException(R.string.file_migration_failed_not_writable)
            }

            if FileManager.default.fileExists(atPath: dstFile.appendingPathComponent(MainApp.getDataFolder()).path) {
                throw MigrationException(R.string.file_migration_failed_dir_already_exists)
            }

            do {
                let srcFolderSize = try FileStorageUtils.getFolderSize(srcFile.appendingPathComponent(MainApp.getDataFolder()))
                if try dstFile.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0 < srcFolderSize {
                    throw MigrationException(R.string.file_migration_failed_not_enough_space)
                }
            } catch {
                throw RuntimeException(error)
            }
        }

        private func copyFiles() throws {
            let srcFile = URL(fileURLWithPath: mStorageSource).appendingPathComponent(MainApp.getDataFolder())
            let dstFile = URL(fileURLWithPath: mStorageTarget).appendingPathComponent(MainApp.getDataFolder())

            try copyDirs(srcFile, dstFile)
        }

        private func copyDirs(src: URL, dst: URL) throws {
            do {
                try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true, attributes: nil)
            } catch {
                throw MigrationException("file_migration_failed_while_coping")
            }

            guard let files = try? FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: nil, options: []) else {
                throw MigrationException("file_migration_failed_while_coping")
            }

            for file in files {
                let destination = dst.appendingPathComponent(file.lastPathComponent)
                if file.hasDirectoryPath {
                    try copyDirs(src: file, dst: destination)
                } else {
                    do {
                        try FileManager.default.copyItem(at: file, to: destination)
                    } catch {
                        throw MigrationException("file_migration_failed_while_coping")
                    }
                }
            }
        }

        private func updateIndex(context: Context) throws {
            let manager = FileDataStorageManager(user: user, contentResolver: context.contentResolver)

            do {
                try manager.migrateStoredFiles(from: mStorageSource, to: mStorageTarget)
            } catch {
                Log_OC.e(TAG, error.localizedDescription, error)
                throw MigrationException(R.string.file_migration_failed_while_updating_index, error)
            }
        }

        private func cleanup() {
            let srcFile = URL(fileURLWithPath: mStorageSource).appendingPathComponent(MainApp.getDataFolder())
            if !deleteRecursive(srcFile) {
                Log_OC.w(TAG, "Migration cleanup step failed")
            }
            try? FileManager.default.removeItem(at: srcFile)
        }

        private func deleteRecursive(_ file: URL) -> Bool {
            var result = true
            if let directoryContents = try? FileManager.default.contentsOfDirectory(at: file, includingPropertiesForKeys: nil, options: []) {
                for content in directoryContents {
                    result = deleteRecursive(content) && result
                }
            }
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                result = false
            }
            return result
        }

        private func rollback() {
            let dstFile = FileManager.default.temporaryDirectory.appendingPathComponent(mStorageTarget).appendingPathComponent(MainApp.getDataFolder())
            if FileManager.default.fileExists(atPath: dstFile.path) {
                do {
                    try FileManager.default.removeItem(at: dstFile)
                } catch {
                    NSLog("Rollback step failed")
                }
            }
        }
    }
}
