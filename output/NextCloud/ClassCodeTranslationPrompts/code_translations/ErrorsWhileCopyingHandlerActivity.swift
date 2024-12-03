
import UIKit

class ErrorsWhileCopyingHandlerActivity: UIViewController, UITableViewDelegate, UITableViewDataSource {

    private static let TAG = "ErrorsWhileCopyingHandlerActivity"

    public static let EXTRA_USER = "ErrorsWhileCopyingHandlerActivity.EXTRA_ACCOUNT"
    public static let EXTRA_LOCAL_PATHS = "ErrorsWhileCopyingHandlerActivity.EXTRA_LOCAL_PATHS"
    public static let EXTRA_REMOTE_PATHS = "ErrorsWhileCopyingHandlerActivity.EXTRA_REMOTE_PATHS"

    private static let WAIT_DIALOG_TAG = "WAIT_DIALOG"

    var user: User!
    var mStorageManager: FileDataStorageManager!
    var mLocalPaths: [String]!
    var mRemotePaths: [String]!
    var mAdapter: ErrorsWhileCopyingListAdapter!
    var mHandler: Handler!
    var mCurrentDialog: DialogFragment?

    override func viewDidLoad() {
        super.viewDidLoad()

        /// read extra parameters in intent
        let intent = self.intent
        user = intent.getParcelableArgument(EXTRA_USER, User.self)
        mRemotePaths = intent.getStringArrayListExtra(EXTRA_REMOTE_PATHS)
        mLocalPaths = intent.getStringArrayListExtra(EXTRA_LOCAL_PATHS)
        mStorageManager = FileDataStorageManager(user: user, contentResolver: contentResolver)
        mHandler = Handler()
        if mCurrentDialog != nil {
            mCurrentDialog?.dismiss()
            mCurrentDialog = nil
        }

        /// load generic layout
        setContentView(R.layout.generic_explanation)

        /// customize text message
        let textView = findViewById(R.id.message) as! TextView
        let appName = getString(R.string.app_name)
        let message = String(format: getString(R.string.sync_foreign_files_forgotten_explanation),
                             appName, appName, appName, appName, user.getAccountName())
        textView.text = message
        textView.movementMethod = ScrollingMovementMethod()

        /// load the list of local and remote files that failed
        let listView = findViewById(R.id.list) as! ListView
        if let mLocalPaths = mLocalPaths, !mLocalPaths.isEmpty {
            mAdapter = ErrorsWhileCopyingListAdapter()
            listView.adapter = mAdapter
        } else {
            listView.visibility = .gone
            mAdapter = nil
        }

        /// customize buttons
        let cancelBtn = findViewById(R.id.cancel) as! Button
        let okBtn = findViewById(R.id.ok) as! Button

        okBtn.setText(R.string.foreign_files_move)
        cancelBtn.setOnClickListener(self)
        okBtn.setOnClickListener(self)
    }

    class ErrorsWhileCopyingListAdapter: ArrayAdapter<String> {

        init() {
            super.init(context: ErrorsWhileCopyingHandlerActivity.this, resource: android.R.layout.two_line_list_item, textViewResourceId: android.R.id.text1, objects: mLocalPaths)
        }

        override func isEnabled(_ position: Int) -> Bool {
            return false
        }

        override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cellIdentifier = "TwoLineCell"
            var cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier)
            
            if cell == nil {
                cell = UITableViewCell(style: .subtitle, reuseIdentifier: cellIdentifier)
            }
            
            if let cell = cell {
                let localPath = getItem(indexPath.row)
                if let localPath = localPath {
                    cell.textLabel?.text = String(format: NSLocalizedString("foreign_files_local_text", comment: ""), localPath)
                }
                
                if let mRemotePaths = mRemotePaths, mRemotePaths.count > 0, indexPath.row >= 0, indexPath.row < mRemotePaths.count {
                    let remotePath = mRemotePaths[indexPath.row]
                    if let remotePath = remotePath {
                        cell.detailTextLabel?.text = String(format: NSLocalizedString("foreign_files_remote_text", comment: ""), remotePath)
                    }
                }
            }
            
            return cell!
        }
    }

    @IBAction func onClick(_ sender: UIButton) {
        if sender.tag == R.id.ok {
            // perform movement operation in background thread
            Log_OC.d(TAG, "Clicked MOVE, start movement")
            MoveFilesTask().execute()
            
        } else if sender.tag == R.id.cancel {
            // just finish
            Log_OC.d(TAG, "Clicked CANCEL, bye")
            self.dismiss(animated: true, completion: nil)
            
        } else {
            Log_OC.e(TAG, "Clicked phantom button, id: \(sender.tag)")
        }
    }

    private class MoveFilesTask: AsyncTask<Void, Void, Bool> {

        override func onPreExecute() {
            mCurrentDialog = IndeterminateProgressDialog.newInstance(R.string.wait_a_moment, false)
            mCurrentDialog.show(getSupportFragmentManager(), WAIT_DIALOG_TAG)
            view.viewWithTag("ok")?.isEnabled = false
        }

        override func doInBackground(_ params: Void...) -> Bool {
            while !mLocalPaths.isEmpty {
                let currentPath = mLocalPaths[0]
                let currentFile = FileManager.default.fileExists(atPath: currentPath)
                let expectedPath = FileStorageUtils.getSavePath(user.accountName) + mRemotePaths[0]
                let expectedFile = FileManager.default.fileExists(atPath: expectedPath)

                if expectedFile == currentFile || (try? FileManager.default.moveItem(atPath: currentPath, toPath: expectedPath)) != nil {
                    // SUCCESS
                    if let file = mStorageManager.getFileByPath(mRemotePaths[0]) {
                        file.storagePath = expectedPath
                        mStorageManager.saveFile(file)
                        mRemotePaths.remove(at: 0)
                        mLocalPaths.remove(at: 0)
                    }
                } else {
                    // FAIL
                    return false
                }
            }
            return true
        }

        override func onPostExecute(_ result: Bool) {
            mAdapter.notifyDataSetChanged()
            mCurrentDialog.dismiss()
            mCurrentDialog = nil
            findViewById(R.id.ok).isEnabled = true

            if result {
                // nothing else to do in this activity
                DisplayUtils.showSnackMessage(findViewById(android.R.id.content), R.string.foreign_files_success)
                finish()
            } else {
                DisplayUtils.showSnackMessage(findViewById(android.R.id.content), R.string.foreign_files_fail)
            }
        }
    }
}
