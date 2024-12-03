
import UIKit
import Foundation

class ReceiveExternalFilesActivity: FileActivity, View.OnClickListener, CopyAndUploadContentUrisTask.OnCopyTmpFilesTaskListener, SortingOrderDialogFragment.OnSortingOrderListener, Injectable, AccountChooserInterface, ReceiveExternalFilesAdapter.OnItemClickListener {

    private static let TAG = String(describing: ReceiveExternalFilesActivity.self)

    private static let FTAG_ERROR_FRAGMENT = "ERROR_FRAGMENT"
    public static let TEXT_FILE_SUFFIX = ".txt"
    public static let URL_FILE_SUFFIX = ".url"
    public static let WEBLOC_FILE_SUFFIX = ".webloc"
    public static let DESKTOP_FILE_SUFFIX = ".desktop"
    public static let SINGLE_PARENT = 1

    @Inject var preferences: AppPreferences!
    @Inject var localBroadcastManager: LocalBroadcastManager!
    @Inject var syncedFolderProvider: SyncedFolderProvider!

    private var mAccountManager: AccountManager!
    private var mParents = Stack<String>()
    private var mStreamsToUpload: [Parcelable]?
    private var mUploadPath: String!
    private var mFile: OCFile!

    private var mSyncBroadcastReceiver: SyncBroadcastReceiver!
    private var receiveExternalFilesAdapter: ReceiveExternalFilesAdapter!
    private var mSyncInProgress: Bool = false

    private static let REQUEST_CODE__SETUP_ACCOUNT = REQUEST_CODE__LAST_SHARED + 1

    private static let KEY_PARENTS = "PARENTS"
    private static let KEY_FILE = "FILE"

    private var mUploadFromTmpFile: Bool = false
    private var mSubjectText: String!
    private var mExtraText: String!

    private static let FILENAME_ENCODING = String.Encoding.utf8

    private var mEmptyListContainer: UIView!
    private var mEmptyListMessage: UILabel!
    private var mEmptyListHeadline: UILabel!
    private var mEmptyListIcon: UIImageView!
    private var sortButton: UIButton!
    private var binding: ReceiveExternalFilesBinding!

    override func viewDidLoad() {
        super.viewDidLoad()

        if let savedInstanceState = savedInstanceState {
            if let parentPath = savedInstanceState.string(forKey: KEY_PARENTS) {
                mParents.append(contentsOf: parentPath.split(separator: OCFile.PATH_SEPARATOR).map { String($0) })
            }

            mFile = savedInstanceState.getParcelableArgument(forKey: KEY_FILE, type: OCFile.self)
        }

        mAccountManager = AccountManager()

        binding = ReceiveExternalFilesBinding.inflate(layoutInflater)
        view = binding.root

        prepareStreamsToUpload()

        let syncIntentFilter = IntentFilter(RefreshFolderOperation.EVENT_SINGLE_FOLDER_CONTENTS_SYNCED)
        syncIntentFilter.addAction(RefreshFolderOperation.EVENT_SINGLE_FOLDER_SHARES_SYNCED)
        mSyncBroadcastReceiver = SyncBroadcastReceiver()
        localBroadcastManager.registerReceiver(mSyncBroadcastReceiver, syncIntentFilter)

        let fm = supportFragmentManager
        var taskRetainerFragment = fm.findFragment(byTag: TaskRetainerFragment.FTAG_TASK_RETAINER_FRAGMENT) as? TaskRetainerFragment
        if taskRetainerFragment == nil {
            taskRetainerFragment = TaskRetainerFragment()
            fm.beginTransaction()
                .add(taskRetainerFragment!, TaskRetainerFragment.FTAG_TASK_RETAINER_FRAGMENT).commit()
        }
    }

    override func setAccount(_ account: Account, savedAccount: Bool) {
        let accounts = mAccountManager.accounts(withAccountType: MainApp.getAccountType(self))
        if accounts.isEmpty {
            Log_OC.i(TAG, "No ownCloud account is available")
            let dialog = DialogNoAccount(viewThemeUtils: viewThemeUtils)
            dialog.show(self, sender: nil)
        }

        if !somethingToUpload() {
            showErrorDialog(
                R.string.uploader_error_message_no_file_to_upload,
                R.string.uploader_error_title_no_file_to_upload
            )
        }

        super.setAccount(account, savedAccount: savedAccount)
    }

    private func showAccountChooserDialog() {
        let dialog = MultipleAccountsDialog()
        dialog.show(self, sender: nil)
    }

    private func getActivity() -> ReceiveExternalFilesActivity {
        return self
    }

    func onAccountChosen(user: User) {
        setAccount(user.toPlatformAccount(), false)
        initTargetFolder()
        populateDirectoryList()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if AccountManager.shared.accounts(ofType: MainApp.accountType(self)).isEmpty {
            let message = String(format: NSLocalizedString("uploader_wrn_no_account_text", comment: ""), NSLocalizedString("app_name", comment: ""))
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
            return
        }

        initTargetFolder()
        browseToFolderIfItExists()
    }

    private func browseToFolderIfItExists() {
        let fullPath = generatePath(mParents)
        if let fileByPath = getStorageManager().getFileByPath(fullPath) {
            startSyncFolderOperation(fileByPath)
            populateDirectoryList()
        } else {
            browseToRoot()
            preferences.setLastUploadPath(OCFile.ROOT_PATH)
        }
    }

    override func encodeRestorableState(with coder: NSCoder) {
        logFileSize(file: mFile, tag: TAG)
        super.encodeRestorableState(with: coder)
        coder.encode(generatePath(mParents), forKey: KEY_PARENTS)
        coder.encode(mFile, forKey: KEY_FILE)
        if let user = getUser() {
            coder.encode(user, forKey: FileActivity.EXTRA_USER)
        }

        Log_OC.d(TAG, "encodeRestorableState() end")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let syncBroadcastReceiver = mSyncBroadcastReceiver {
            localBroadcastManager.removeObserver(syncBroadcastReceiver)
        }
    }

    func onSortingOrderChosen(newSortOrder: FileSortOrder) {
        preferences.setSortOrder(for: mFile, newSortOrder: newSortOrder)
        sortButton.setTitle(DisplayUtils.getSortOrderStringId(newSortOrder), for: .normal)
        populateDirectoryList()
    }

    func selectFile(_ file: OCFile) {
        if file.isFolder() {
            if let filenameErrorMessage = FileNameValidator.instance.checkFileName(file.fileName, getCapabilities(), self, nil) {
                DisplayUtils.showSnackMessage(self, filenameErrorMessage)
                return
            }

            if file.isEncrypted && !FileOperationsHelper.isEndToEndEncryptionSetup(self, getUser().orElseThrow { IllegalAccessError() }) {
                DisplayUtils.showSnackMessage(self, R.string.e2e_not_yet_setup)
                return
            }

            startSyncFolderOperation(file)
            mParents.push(file.fileName)
            populateDirectoryList()
        }
    }

    public static class DialogNoAccount: DialogFragment {
        private let viewThemeUtils: ViewThemeUtils

        public init(viewThemeUtils: ViewThemeUtils) {
            self.viewThemeUtils = viewThemeUtils
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            present(createDialog(), animated: true, completion: nil)
        }

        func createDialog() -> UIAlertController {
            let alertController = UIAlertController(title: NSLocalizedString("uploader_wrn_no_account_title", comment: ""),
                                                    message: String(format: NSLocalizedString("uploader_wrn_no_account_text", comment: ""), NSLocalizedString("app_name", comment: "")),
                                                    preferredStyle: .alert)

            let setupAction = UIAlertAction(title: NSLocalizedString("uploader_wrn_no_account_setup_btn_text", comment: ""), style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }

            let quitAction = UIAlertAction(title: NSLocalizedString("uploader_wrn_no_account_quit_btn_text", comment: ""), style: .default) { _ in
                self.dismiss(animated: true, completion: nil)
            }

            alertController.addAction(setupAction)
            alertController.addAction(quitAction)

            return alertController
        }
    }

    public static class DialogInputUploadFilename: DialogFragment, Injectable {
        private static let KEY_SUBJECT_TEXT = "SUBJECT_TEXT"
        private static let KEY_EXTRA_TEXT = "EXTRA_TEXT"

        private static let CATEGORY_URL = 1
        private static let CATEGORY_MAPS_URL = 2
        private static let EXTRA_TEXT_LENGTH = 3
        private static let SINGLE_SPINNER_ENTRY = 1

        private var mFilenameBase: [String]!
        private var mFilenameSuffix: [String]!
        private var mText: [String]!
        private var mFileCategory: Int!

        private var mSpinner: Spinner!
        @Inject var preferences: AppPreferences!
        @Inject var viewThemeUtils: ViewThemeUtils!

        public static func newInstance(subjectText: String, extraText: String) -> DialogInputUploadFilename {
            let dialog = DialogInputUploadFilename()
            var args = [String: String]()
            args[KEY_SUBJECT_TEXT] = subjectText
            args[KEY_EXTRA_TEXT] = extraText
            dialog.setArguments(args)
            return dialog
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
        }

        override func onCreateDialog(_ savedInstanceState: Bundle?) -> Dialog {
            mFilenameBase = []
            mFilenameSuffix = []
            mText = []

            var subjectText = ""
            var extraText = ""
            if let arguments = self.arguments {
                if let subject = arguments[KEY_SUBJECT_TEXT] as? String {
                    subjectText = subject
                }
                if let extra = arguments[KEY_EXTRA_TEXT] as? String {
                    extraText = extra
                }
            }

            let inflater = self.layoutInflater
            let binding = UploadFileDialogBinding.inflate(inflater)

            let adapter = ArrayAdapter<String>(context: requireContext(), resource: android.R.layout.simple_spinner_item)
            adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)

            var selectPos = 0
            var filename = renameSafeFilename(subjectText) ?? ""
            adapter.add(getString(R.string.upload_file_dialog_filetype_snippet_text))
            mText.append(extraText)
            mFilenameBase.append(filename)
            mFilenameSuffix.append(TEXT_FILE_SUFFIX)

            if isIntentStartWithUrl(extraText) {
                let str = getString(R.string.upload_file_dialog_filetype_internet_shortcut)
                mText.append(internetShortcutUrlText(extraText))
                mFilenameBase.append(filename)
                mFilenameSuffix.append(URL_FILE_SUFFIX)
                adapter.add(String(format: str, URL_FILE_SUFFIX))

                mText.append(internetShortcutWeblocText(extraText))
                mFilenameBase.append(filename)
                mFilenameSuffix.append(WEBLOC_FILE_SUFFIX)
                adapter.add(String(format: str, WEBLOC_FILE_SUFFIX))

                mText.append(internetShortcutDesktopText(extraText, filename))
                mFilenameBase.append(filename)
                mFilenameSuffix.append(DESKTOP_FILE_SUFFIX)
                adapter.add(String(format: str, DESKTOP_FILE_SUFFIX))

                selectPos = preferences.getUploadUrlFileExtensionUrlSelectedPos()
                mFileCategory = CATEGORY_URL
            } else if isIntentFromGoogleMap(subjectText, extraText) {
                let str = getString(R.string.upload_file_dialog_filetype_googlemap_shortcut)
                let texts = extraText.split(separator: "\n")
                mText.append(internetShortcutUrlText(String(texts[2])))
                mFilenameBase.append(String(texts[0]))
                mFilenameSuffix.append(URL_FILE_SUFFIX)
                adapter.add(String(format: str, URL_FILE_SUFFIX))

                mText.append(internetShortcutWeblocText(String(texts[2])))
                mFilenameBase.append(String(texts[0]))
                mFilenameSuffix.append(WEBLOC_FILE_SUFFIX)
                adapter.add(String(format: str, WEBLOC_FILE_SUFFIX))

                mText.append(internetShortcutDesktopText(String(texts[2]), String(texts[0])))
                mFilenameBase.append(String(texts[0]))
                mFilenameSuffix.append(DESKTOP_FILE_SUFFIX)
                adapter.add(String(format: str, DESKTOP_FILE_SUFFIX))

                selectPos = preferences.getUploadMapFileExtensionUrlSelectedPos()
                mFileCategory = CATEGORY_MAPS_URL
            }

            setFilename(binding.userInput, selectPos)
            binding.userInput.requestFocus()
            viewThemeUtils.material.colorTextInputLayout(binding.userInputContainer)

            setupSpinner(adapter, selectPos, binding.userInput, binding.fileType)
            if adapter.count == SINGLE_SPINNER_ENTRY {
                binding.labelFileType.visibility = .gone
                binding.fileType.visibility = .gone
            }
            mSpinner = binding.fileType

            let filenameDialog = createFilenameDialog(binding.root, binding.userInput, binding.fileType)
            filenameDialog.window?.setSoftInputMode(LayoutParams.SOFT_INPUT_STATE_VISIBLE)
            return filenameDialog
        }

        func setupSpinner(adapter: [String], selectPos: Int, userInput: UITextField, spinner: UIPickerView) {
            spinner.delegate = self
            spinner.dataSource = self
            spinner.selectRow(selectPos, inComponent: 0, animated: false)
            self.selectedPosition = selectPos
            self.userInput = userInput
        }

        extension YourViewController: UIPickerViewDelegate, UIPickerViewDataSource {
            func numberOfComponents(in pickerView: UIPickerView) -> Int {
                return 1
            }

            func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
                return adapter.count
            }

            func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
                return adapter[row]
            }

            func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
                setFilename(userInput, row)
                saveSelection(row)
            }
        }

        private func createFilenameDialog(view: UIView, userInput: UITextField, spinner: UIPickerView) -> UIAlertController {
            let alertController = UIAlertController(title: NSLocalizedString("upload_file_dialog_title", comment: ""), message: nil, preferredStyle: .alert)
            alertController.setValue(view, forKey: "contentViewController")

            let okAction = UIAlertAction(title: NSLocalizedString("common_ok", comment: ""), style: .default) { _ in
                let selectPos = spinner.selectedRow(inComponent: 0)

                // verify if file name has suffix
                var filename = userInput.text ?? ""
                let suffix = self.mFilenameSuffix[selectPos]
                if !filename.hasSuffix(suffix) {
                    filename += suffix
                }

                if let file = self.createTempFile(self.mText[selectPos]) {
                    let tmpName = file.path
                    (self as? ReceiveExternalFilesActivity)?.uploadFile(tmpName, filename)
                } else {
                    self.dismiss(animated: true, completion: nil)
                }
            }
            alertController.addAction(okAction)

            let cancelAction = UIAlertAction(title: NSLocalizedString("common_cancel", comment: ""), style: .cancel) { _ in
                alertController.dismiss(animated: true, completion: nil)
            }
            alertController.addAction(cancelAction)

            return alertController
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            hideSpinnerDropDown(mSpinner)
        }

        private func saveSelection(selectPos: Int) {
            switch mFileCategory {
            case .CATEGORY_URL:
                preferences.setUploadUrlFileExtensionUrlSelectedPos(selectPos)
            case .CATEGORY_MAPS_URL:
                preferences.setUploadMapFileExtensionUrlSelectedPos(selectPos)
            default:
                Log_OC.d(TAG, "Simple text snippet only: no selection to be persisted")
            }
        }

        private func hideSpinnerDropDown(spinner: UIPickerView) {
            do {
                let method = UIPickerView.self.instanceMethod(for: Selector(("onDetachedFromWindow")))
                if let method = method {
                    let implementation = method.getImplementation()
                    typealias Function = @convention(c) (AnyObject, Selector) -> Void
                    let function = unsafeBitCast(implementation, to: Function.self)
                    function(spinner, Selector(("onDetachedFromWindow")))
                }
            } catch {
                print("Error in onDetachedFromWindow: \(error)")
            }
        }

        private func setFilename(inputText: UITextField, selectPos: Int) {
            let filename = mFilenameBase[selectPos] + mFilenameSuffix[selectPos]
            inputText.text = filename
            let selectionStart = 0
            let extensionStart = filename.lastIndex(of: ".") ?? filename.endIndex
            let selectionEnd = extensionStart != filename.endIndex ? filename.distance(from: filename.startIndex, to: extensionStart) : filename.count
            if selectionEnd >= 0 {
                let startPosition = inputText.position(from: inputText.beginningOfDocument, offset: min(selectionStart, selectionEnd))!
                let endPosition = inputText.position(from: inputText.beginningOfDocument, offset: max(selectionStart, selectionEnd))!
                inputText.selectedTextRange = inputText.textRange(from: startPosition, to: endPosition)
            }
        }

        private func isIntentFromGoogleMap(subjectText: String, extraText: String) -> Bool {
            let texts = extraText.split(separator: "\n")
            if texts.count != EXTRA_TEXT_LENGTH {
                return false
            }

            if texts[0].isEmpty || subjectText != String(texts[0]) {
                return false
            }

            return texts[2].hasPrefix("https://goo.gl/maps/")
        }

        private func isIntentStartWithUrl(_ extraText: String) -> Bool {
            return extraText.hasPrefix("http://") || extraText.hasPrefix("https://")
        }

        private func renameSafeFilename(_ filename: String) -> String {
            var safeFilename = filename
            safeFilename = safeFilename.replacingOccurrences(of: "?", with: "_")
            safeFilename = safeFilename.replacingOccurrences(of: "\"", with: "_")
            safeFilename = safeFilename.replacingOccurrences(of: "/", with: "_")
            safeFilename = safeFilename.replacingOccurrences(of: "<", with: "_")
            safeFilename = safeFilename.replacingOccurrences(of: ">", with: "_")
            safeFilename = safeFilename.replacingOccurrences(of: "*", with: "_")
            safeFilename = safeFilename.replacingOccurrences(of: "|", with: "_")
            safeFilename = safeFilename.replacingOccurrences(of: ";", with: "_")
            safeFilename = safeFilename.replacingOccurrences(of: "=", with: "_")
            safeFilename = safeFilename.replacingOccurrences(of: ",", with: "_")

            let maxLength = 128
            if let data = safeFilename.data(using: .utf8), data.count > maxLength {
                safeFilename = String(data: data.prefix(maxLength), encoding: .utf8) ?? safeFilename
            }
            return safeFilename
        }

        private func internetShortcutUrlText(url: String) -> String {
            return "[InternetShortcut]\r\nURL=\(url)\r\n"
        }

        func internetShortcutWeblocText(url: String) -> String {
            return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            <key>URL</key>
            <string>\(url)</string>
            </dict>
            </plist>
            """
        }

        func internetShortcutDesktopText(url: String, filename: String) -> String {
            return "[Desktop Entry]\n" +
                "Encoding=UTF-8\n" +
                "Name=\(filename)\n" +
                "Type=Link\n" +
                "URL=\(url)\n" +
                "Icon=text-html"
        }

        private func createTempFile(text: String) -> URL? {
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("tmp.tmp")
            do {
                try text.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                print("Error: \(error)")
                return nil
            }
            return fileURL
        }
    }

    override func onBackPressed() {
        if mParents.count <= SINGLE_PARENT {
            super.onBackPressed()
        } else {
            mParents.removeLast()
            browseToFolderIfItExists()
        }
    }

    override func onClick(_ v: UIView) {
        let id = v.tag

        if id == R.id.uploader_choose_folder {
            mUploadPath = ""

            let stringBuilder = NSMutableString()
            for p in mParents {
                stringBuilder.append(p + OCFile.PATH_SEPARATOR)
            }
            mUploadPath = stringBuilder as String

            if mUploadFromTmpFile {
                let dialog = DialogInputUploadFilename.newInstance(mSubjectText, mExtraText)
                dialog.show(self, sender: nil)
            } else {
                Log_OC.d(TAG, "Uploading file to dir \(mUploadPath)")
                uploadFiles()
            }
        } else if id == R.id.uploader_cancel {
            self.dismiss(animated: true, completion: nil)
        } else {
            fatalError("Wrong element clicked")
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(handleActivityResult(notification:)), name: .activityResult, object: nil)
    }

    @objc func handleActivityResult(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let requestCode = userInfo["requestCode"] as? Int,
              let resultCode = userInfo["resultCode"] as? Int else { return }

        print("result received. req: \(requestCode) res: \(resultCode)")

        if requestCode == REQUEST_CODE__SETUP_ACCOUNT {
            if resultCode == RESULT_CANCELED {
                self.dismiss(animated: true, completion: nil)
            }

            let accounts = mAccountManager.accounts(withAccountType: MainApp.getAuthTokenType())
            if accounts.isEmpty {
                let dialog = DialogNoAccount(viewThemeUtils: viewThemeUtils)
                dialog.show(self, sender: nil)
            } else {
                setAccount(accounts[0], false)
                populateDirectoryList()
            }
        }
    }

    private func setupActionBarSubtitle() {
        if let actionBar = self.navigationController?.navigationBar {
            if isHaveMultipleAccount() {
                viewThemeUtils.files.themeActionBar(self, actionBar, getAccount().name)
            } else {
                actionBar.topItem?.subtitle = nil
            }
        }
    }

    private func populateDirectoryList() {
        setupEmptyList()
        setupToolbar()
        let actionBar = navigationController?.navigationBar
        setupActionBarSubtitle()

        binding.toolbarLayout.sortListButtonGroup.isHidden = false
        binding.toolbarLayout.switchGridViewButton.isHidden = true

        let currentDir = mParents.last
        let notRoot = mParents.count > 1

        if let actionBar = actionBar {
            if currentDir?.isEmpty ?? true {
                viewThemeUtils.files.themeActionBar(self, actionBar, R.string.uploader_top_message)
            } else {
                viewThemeUtils.files.themeActionBar(self, actionBar, currentDir!)
            }

            navigationItem.hidesBackButton = !notRoot
        }

        let fullPath = generatePath(mParents)

        print("Populating view with content of : \(fullPath)")

        mFile = getStorageManager().getFileByPath(fullPath)
        if let mFile = mFile {
            var files = getStorageManager().getFolderContent(mFile, false)

            if files.isEmpty {
                setMessageForEmptyList(R.string.file_list_empty_headline, R.string.empty, R.drawable.uploads)
                mEmptyListContainer.isHidden = false
                binding.list.isHidden = true
            } else {
                mEmptyListContainer.isHidden = true
                files = sortFileList(files)
                setupReceiveExternalFilesAdapter(files)
            }

            let btnChooseFolder = binding.uploaderChooseFolder
            viewThemeUtils.material.colorMaterialButtonPrimaryFilled(btnChooseFolder)
            btnChooseFolder.addTarget(self, action: #selector(buttonClicked), for: .touchUpInside)

            btnChooseFolder.isEnabled = mFile.canWrite()

            viewThemeUtils.platform.themeStatusBar(self)

            viewThemeUtils.material.colorMaterialButtonPrimaryOutlined(binding.uploaderCancel)
            binding.uploaderCancel.addTarget(self, action: #selector(buttonClicked), for: .touchUpInside)

            sortButton = binding.toolbarLayout.sortButton
            let sortOrder = preferences.getSortOrderByFolder(mFile)
            sortButton.setTitle(DisplayUtils.getSortOrderStringId(sortOrder), for: .normal)
            sortButton.addTarget(self, action: #selector(openSortingOrderDialogFragment), for: .touchUpInside)
        }
    }

    private func setupReceiveExternalFilesAdapter(files: [OCFile]) {
        receiveExternalFilesAdapter = ReceiveExternalFilesAdapter(files: files,
                                                                  context: self,
                                                                  user: getUser().get(),
                                                                  storageManager: getStorageManager(),
                                                                  viewThemeUtils: viewThemeUtils,
                                                                  syncedFolderProvider: syncedFolderProvider,
                                                                  activity: self)

        binding.list.layoutManager = LinearLayoutManager(context: self)
        binding.list.adapter = receiveExternalFilesAdapter
        binding.list.isHidden = false
    }

    func setupEmptyList() {
        mEmptyListContainer = binding.emptyView.emptyListView
        mEmptyListMessage = binding.emptyView.emptyListViewText
        mEmptyListHeadline = binding.emptyView.emptyListViewHeadline
        mEmptyListIcon = binding.emptyView.emptyListIcon
    }

    func setMessageForEmptyList(headline: Int, message: Int, icon: Int) {
        DispatchQueue.main.async {
            if let emptyListContainer = self.mEmptyListContainer, let emptyListMessage = self.mEmptyListMessage {
                self.mEmptyListHeadline.text = NSLocalizedString(String(headline), comment: "")
                self.mEmptyListMessage.text = NSLocalizedString(String(message), comment: "")
                self.mEmptyListIcon.image = viewThemeUtils.platform.tintPrimaryDrawable(self, icon: icon)
                self.mEmptyListIcon.isHidden = false
                self.mEmptyListMessage.isHidden = false
            }
        }
    }

    func onSavedCertificate() {
        startSyncFolderOperation(getCurrentDir())
    }

    private func startSyncFolderOperation(folder: OCFile?) {
        guard let folder = folder else {
            DisplayUtils.showSnackMessage(self, R.string.receive_external_files_activity_start_sync_folder_is_not_exists_message)
            return
        }

        let currentSyncTime = Date().timeIntervalSince1970 * 1000

        mSyncInProgress = true

        // perform folder synchronization
        let syncFolderOp = RefreshFolderOperation(folder: folder,
                                                  currentSyncTime: currentSyncTime,
                                                  param1: false,
                                                  param2: false,
                                                  storageManager: getStorageManager(),
                                                  user: getUser().orElseThrow { RuntimeException() },
                                                  context: getApplicationContext())
        syncFolderOp.execute(account: getAccount(), listener: self, param1: nil, param2: nil)
    }

    private func sortFileList(files: [OCFile]) -> [OCFile] {
        let sortOrder = preferences.getSortOrderByFolder(mFile)
        return sortOrder.sortCloudFiles(files)
    }

    private func generatePath(dirs: [String]) -> String {
        var fullPath = ""

        for dir in dirs {
            fullPath += dir + OCFile.PATH_SEPARATOR
        }
        return fullPath
    }

    private func prepareStreamsToUpload() {
        let intent = self.intent

        if intent.hasExtra(Intent.EXTRA_STREAM), intent.action == Intent.ACTION_SEND {
            mStreamsToUpload = [IntentExtensionsKt.getParcelableArgument(intent, Intent.EXTRA_STREAM, Parcelable.self)]
        } else if intent.hasExtra(Intent.EXTRA_STREAM), intent.action == Intent.ACTION_SEND_MULTIPLE {
            mStreamsToUpload = intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        } else if intent.hasExtra(Intent.EXTRA_TEXT), intent.action == Intent.ACTION_SEND {
            mStreamsToUpload = nil
            saveTextsFromIntent(intent)
        } else {
            showErrorDialog(R.string.uploader_error_message_no_file_to_upload, R.string.uploader_error_title_file_cannot_be_uploaded)
        }
    }

    func saveTextsFromIntent(intent: Intent) {
        guard intent.type == MimeType.TEXT_PLAIN else {
            return
        }
        mUploadFromTmpFile = true

        mSubjectText = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        if mSubjectText == nil {
            mSubjectText = intent.getStringExtra(Intent.EXTRA_TITLE)
            if mSubjectText == nil {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
                mSubjectText = dateFormatter.string(from: Date())
            }
        }
        mExtraText = intent.getStringExtra(Intent.EXTRA_TEXT)
    }

    private func somethingToUpload() -> Bool {
        return (mStreamsToUpload != nil && !mStreamsToUpload.isEmpty && mStreamsToUpload[0] != nil) || mUploadFromTmpFile
    }

    func uploadFile(tmpName: String, filename: String) {
        FileUploadHelper.instance().uploadNewFiles(
            user: getUser() ?? { fatalError() }(),
            localPaths: [tmpName],
            remotePaths: [mFile.getRemotePath() + filename],
            localBehaviour: .copy,
            isUserInitiated: true,
            operation: .createdByUser,
            isBackground: false,
            isSilent: false,
            collisionPolicy: .askUser
        )
        finish()
    }

    func uploadFiles() {
        guard let streamsToUpload = mStreamsToUpload else {
            DisplayUtils.showSnackMessage(self, R.string.receive_external_files_activity_unable_to_find_file_to_upload)
            return
        }

        if streamsToUpload.count > FileUploadHelper.MAX_FILE_COUNT {
            DisplayUtils.showSnackMessage(self, R.string.max_file_count_warning_message)
            return
        }

        let uploader = UriUploader(
            context: self,
            streamsToUpload: streamsToUpload,
            uploadPath: mUploadPath,
            user: getUser() ?? { fatalError() }(),
            localBehaviour: .delete,
            showWaitingDialog: true,
            copyTempTaskListener: self
        )

        let resultCode = uploader.uploadUris()

        // Save the path to shared preferences; even if upload is not possible, user chose the folder
        preferences.setLastUploadPath(mUploadPath)

        if resultCode == .ok {
            finish()
        } else {
            var messageResTitle = R.string.uploader_error_title_file_cannot_be_uploaded
            var messageResId = R.string.common_error_unknown

            switch resultCode {
            case .errorNoFileToUpload:
                messageResId = R.string.uploader_error_message_no_file_to_upload
                messageResTitle = R.string.uploader_error_title_no_file_to_upload
            case .errorReadPermissionNotGranted:
                messageResId = R.string.uploader_error_message_read_permission_not_granted
            default:
                break
            }

            showErrorDialog(messageResId, messageResTitle)
        }
    }

    override func onRemoteOperationFinish(_ operation: RemoteOperation, result: RemoteOperationResult) {
        super.onRemoteOperationFinish(operation, result)

        if let createFolderOperation = operation as? CreateFolderOperation {
            onCreateFolderOperationFinish(createFolderOperation, result: result)
        }
    }

    private func onCreateFolderOperationFinish(operation: CreateFolderOperation, result: RemoteOperationResult) {
        if result.isSuccess() {
            let remotePath = String(operation.getRemotePath().dropLast())
            let newFolder = remotePath.components(separatedBy: "/").last ?? ""
            mParents.push(newFolder)
            populateDirectoryList()
        } else {
            do {
                try DisplayUtils.showSnackMessage(self, ErrorMessageAdapter.getErrorCauseMessage(result, operation, getResources()))
            } catch {
                Log_OC.e(TAG, "Error while trying to show fail message ", error)
            }
        }
    }

    private func initTargetFolder() {
        guard let storageManager = getStorageManager() else {
            fatalError("Do not call this method before initializing mStorageManager")
        }

        if mParents.isEmpty {
            let lastPath = preferences.getLastUploadPath()
            // "/" equals root-directory
            if OCFile.ROOT_PATH == lastPath {
                mParents.append("")
            } else {
                let dirNames = lastPath.split(separator: OCFile.PATH_SEPARATOR)
                mParents.removeAll()
                mParents.append(contentsOf: dirNames.map { String($0) })
            }
        }

        // make sure that path still exists, if it doesn't pop the stack and try the previous path
        while !storageManager.fileExists(generatePath(mParents)) && mParents.count > 1 {
            mParents.removeLast()
        }
    }

    private func isHaveMultipleAccount() -> Bool {
        return mAccountManager.accounts(withAccountType: MainApp.getAccountType(self)).count > 1
    }

    override func onCreateOptionsMenu(_ menu: Menu) -> Bool {
        let inflater = menuInflater
        inflater.inflate(R.menu.activity_receive_external_files, menu)

        if !isHaveMultipleAccount() {
            menu.findItem(R.id.action_switch_account)?.isVisible = false
            menu.findItem(R.id.action_create_dir)?.setShowAsAction(.ifRoom)
        }

        setupSearchView(menu)

        if let newFolderMenuItem = menu.findItem(R.id.action_create_dir) {
            newFolderMenuItem.isEnabled = mFile.canWrite()
        }

        return true
    }

    private func setupSearchView(menu: UIMenu) {
        if let searchMenuItem = menu.findItem(withIdentifier: R.id.action_search) {
            if let searchView = searchMenuItem.customView as? UISearchBar {
                searchView.delegate = self
            }
        }
    }

    extension ReceiveExternalFilesActivity: UISearchBarDelegate {
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            if let query = searchBar.text {
                receiveExternalFilesAdapter.filter(query)
            }
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            receiveExternalFilesAdapter.filter(searchText)
        }
    }

    override func onOptionsItemSelected(_ item: MenuItem) -> Bool {
        var retval = true
        let itemId = item.itemId

        if itemId == R.id.action_create_dir {
            let dialog = CreateFolderDialogFragment.newInstance(mFile)
            dialog.show(getSupportFragmentManager(), CreateFolderDialogFragment.CREATE_FOLDER_FRAGMENT)
        } else if itemId == android.R.id.home {
            if mParents.count > SINGLE_PARENT {
                onBackPressed()
            }
        } else if itemId == R.id.action_switch_account {
            showAccountChooserDialog()
        } else {
            retval = super.onOptionsItemSelected(item)
        }

        return retval
    }

    private func getCurrentFolder() -> OCFile? {
        if let file = mFile {
            if file.isFolder() {
                return file
            } else if let storageManager = getStorageManager() {
                return storageManager.getFileByPath(file.getParentRemotePath())
            }
        }
        return nil
    }

    private func browseToRoot() {
        let root = getStorageManager().getFileByPath(OCFile.ROOT_PATH)
        mFile = root
        mParents.removeAll()
        mParents.append("")
        startSyncFolderOperation(root)
    }

    override func onReceive(context: Context, intent: Intent) {
        do {
            let event = intent.action
            Log_OC.d(TAG, "Received broadcast \(event ?? "")")
            let accountName = intent.getStringExtra(FileSyncAdapter.EXTRA_ACCOUNT_NAME)
            let syncFolderRemotePath = intent.getStringExtra(FileSyncAdapter.EXTRA_FOLDER_PATH)
            let syncResult = DataHolderUtil.getInstance().retrieve(intent.getStringExtra(FileSyncAdapter.EXTRA_RESULT)) as? RemoteOperationResult
            let sameAccount = getAccount() != nil && accountName == getAccount()?.name && getStorageManager() != nil

            if sameAccount {
                if FileSyncAdapter.EVENT_FULL_SYNC_START == event {
                    mSyncInProgress = true
                } else {
                    var currentFile: OCFile? = (mFile == nil) ? nil : getStorageManager()?.getFileByPath(mFile!.getRemotePath())
                    var currentDir: OCFile? = (getCurrentFolder() == nil) ? nil : getStorageManager()?.getFileByPath(getCurrentFolder()!.getRemotePath())

                    if currentDir == nil {
                        DisplayUtils.showSnackMessage(getActivity(), R.string.sync_current_folder_was_removed, getCurrentFolder()?.getFileName() ?? "")
                        browseToRoot()
                    } else {
                        if currentFile == nil && !(mFile?.isFolder() ?? true) {
                            currentFile = currentDir
                        }

                        if currentDir?.getRemotePath() == syncFolderRemotePath {
                            populateDirectoryList()
                        }
                        mFile = currentFile
                    }

                    mSyncInProgress = !(FileSyncAdapter.EVENT_FULL_SYNC_END == event) && !(RefreshFolderOperation.EVENT_SINGLE_FOLDER_SHARES_SYNCED == event)

                    if RefreshFolderOperation.EVENT_SINGLE_FOLDER_CONTENTS_SYNCED == event && syncResult != nil && !syncResult!.isSuccess() {
                        if syncResult!.getCode() == .UNAUTHORIZED || (syncResult!.isException() && syncResult!.getException() is AuthenticatorException) {
                            requestCredentialsUpdate(context)
                        } else if ResultCode.SSL_RECOVERABLE_PEER_UNVERIFIED == syncResult!.getCode() {
                            showUntrustedCertDialog(syncResult!)
                        }
                    }
                }
                Log_OC.d(TAG, "Setting progress visibility to \(mSyncInProgress)")
            }
        } catch {
            DataHolderUtil.getInstance().delete(intent.getStringExtra(FileSyncAdapter.EXTRA_RESULT))
        }
    }

    override func onTmpFilesCopied(result: ResultCode) {
        dismissLoadingDialog()
        finish()
    }

    private func showErrorDialog(messageResId: Int, messageResTitle: Int) {
        let errorDialog = ConfirmationDialogFragment.newInstance(
            messageResId: messageResId,
            arguments: [getString(R.string.app_name)], // see uploader_error_message_* in strings.xml
            titleResId: messageResTitle,
            positiveButtonResId: R.string.common_back,
            negativeButtonResId: -1,
            neutralButtonResId: -1
        )
        errorDialog.isCancelable = false
        errorDialog.setOnConfirmationListener { callerTag in
            finish()
        } onNeutral: { callerTag in
            // not used at the moment
        } onCancel: { callerTag in
            // not used at the moment
        }
        errorDialog.show(getSupportFragmentManager(), tag: FTAG_ERROR_FRAGMENT)
    }

    override func onConfirmation(callerTag: String) {
        self.dismiss(animated: true, completion: nil)
    }

    func onNeutral(callerTag: String) {
        // not used at the moment
    }

    func onCancel(callerTag: String) {
        // not used at the moment
    }
}
