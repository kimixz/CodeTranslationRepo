
import UIKit

class UploadFilesActivity: UIViewController, LocalFileListFragmentContainerActivity, OnClickListener, ConfirmationDialogFragmentListener, SortingOrderDialogFragmentOnSortingOrderListener, CheckAvailableSpaceTaskCheckAvailableSpaceListener, StoragePathAdapterStoragePathAdapterListener, Injectable {

    private static let KEY_ALL_SELECTED = "UploadFilesActivity.KEY_ALL_SELECTED"
    public static let KEY_LOCAL_FOLDER_PICKER_MODE = "UploadFilesActivity.LOCAL_FOLDER_PICKER_MODE"
    public static let LOCAL_BASE_PATH = "UploadFilesActivity.LOCAL_BASE_PATH"
    public static let EXTRA_CHOSEN_FILES = "UploadFilesActivity.EXTRA_CHOSEN_FILES"
    public static let KEY_DIRECTORY_PATH = "UploadFilesActivity.KEY_DIRECTORY_PATH"

    private static let SINGLE_DIR = 1
    public static let RESULT_OK_AND_DELETE = 3
    public static let RESULT_OK_AND_DO_NOTHING = 2
    public static let RESULT_OK_AND_MOVE = RESULT_FIRST_USER
    public static let REQUEST_CODE_KEY = "requestCode"
    private static let ENCRYPTED_FOLDER_KEY = "encrypted_folder"

    private static let QUERY_TO_MOVE_DIALOG_TAG = "QUERY_TO_MOVE"
    private static let TAG = "UploadFilesActivity"
    private static let WAIT_DIALOG_TAG = "WAIT"

    @Inject var preferences: AppPreferences!
    private var mAccountOnCreation: Account?
    private var mDirectories: ArrayAdapter<String>!
    private var mLocalFolderPickerMode = false
    private var mSelectAll = false
    private var mCurrentDialog: DialogFragment?
    private var mCurrentDir: File!
    private var requestCode = 0
    private var mFileListFragment: LocalFileListFragment!
    private var dialog: LocalStoragePathPickerDialogFragment?
    private var mOptionsMenu: Menu?
    private var mSearchView: SearchView?
    private var binding: UploadFilesLayoutBinding!
    private var isWithinEncryptedFolder = false

    func getFileListFragment() -> LocalFileListFragment {
        return mFileListFragment
    }

    static func startUploadActivityForResult(activity: UIViewController, user: User, requestCode: Int, isWithinEncryptedFolder: Bool) {
        let action = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "UploadFilesActivity") as! UploadFilesActivity
        action.user = user
        action.requestCode = requestCode
        action.isWithinEncryptedFolder = isWithinEncryptedFolder
        activity.present(action, animated: true, completion: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Log_OC.d(TAG, "onCreate() start")

        if let extras = self.intent.extras {
            mLocalFolderPickerMode = extras.getBoolean(KEY_LOCAL_FOLDER_PICKER_MODE, false)
            requestCode = extras.getInt(REQUEST_CODE_KEY)
            isWithinEncryptedFolder = extras.getBoolean(ENCRYPTED_FOLDER_KEY, false)
        }

        if let savedInstanceState = savedInstanceState {
            mCurrentDir = File(savedInstanceState.getString(KEY_DIRECTORY_PATH, Environment.getExternalStorageDirectory().absolutePath))
            mSelectAll = savedInstanceState.getBoolean(KEY_ALL_SELECTED, false)
            isWithinEncryptedFolder = savedInstanceState.getBoolean(ENCRYPTED_FOLDER_KEY, false)
        } else {
            let lastUploadFrom = preferences.getUploadFromLocalLastPath()
            if !lastUploadFrom.isEmpty {
                mCurrentDir = File(lastUploadFrom)
                while !mCurrentDir.exists() {
                    mCurrentDir = mCurrentDir.getParentFile()
                }
            } else {
                mCurrentDir = Environment.getExternalStorageDirectory()
            }
        }

        mAccountOnCreation = getAccount()

        mDirectories = ArrayAdapter<String>(context: self, android.R.layout.simple_spinner_item)
        mDirectories.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        fillDirectoryDropdown()

        binding = UploadFilesLayoutBinding.inflate(layoutInflater)
        setContentView(binding.root)

        if mLocalFolderPickerMode {
            binding.uploadOptions.visibility = .gone
            binding.uploadFilesBtnUpload.setText(R.string.uploader_btn_alternative_text)
        }

        mFileListFragment = supportFragmentManager.findFragmentByTag("local_files_list") as? LocalFileListFragment

        viewThemeUtils.material.colorMaterialButtonPrimaryOutlined(binding.uploadFilesBtnCancel)
        binding.uploadFilesBtnCancel.setOnClickListener(self)

        viewThemeUtils.material.colorMaterialButtonPrimaryFilled(binding.uploadFilesBtnUpload)
        binding.uploadFilesBtnUpload.setOnClickListener(self)
        binding.uploadFilesBtnUpload.isEnabled = mLocalFolderPickerMode

        let localBehaviour = preferences.getUploaderBehaviour()

        var behaviours = [String]()
        behaviours.append(getString(R.string.uploader_upload_files_behaviour_move_to_nextcloud_folder, themeUtils.getDefaultDisplayNameForRootFolder(self)))
        behaviours.append(getString(R.string.uploader_upload_files_behaviour_only_upload))
        behaviours.append(getString(R.string.uploader_upload_files_behaviour_upload_and_delete_from_source))

        let behaviourAdapter = ArrayAdapter<String>(context: self, android.R.layout.simple_spinner_item, behaviours)
        behaviourAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        binding.uploadFilesSpinnerBehaviour.adapter = behaviourAdapter
        binding.uploadFilesSpinnerBehaviour.setSelection(localBehaviour)

        setupToolbar()
        binding.uploadFilesToolbar.sortListButtonGroup.visibility = .visible
        binding.uploadFilesToolbar.switchGridViewButton.visibility = .gone

        if let actionBar = supportActionBar {
            actionBar.setHomeButtonEnabled(true)
            actionBar.setDisplayHomeAsUpEnabled(mCurrentDir != nil)
            actionBar.setDisplayShowTitleEnabled(false)
            viewThemeUtils.files.themeActionBar(self, actionBar)
        }

        showToolbarSpinner()
        mToolbarSpinner.adapter = mDirectories
        mToolbarSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>, view: View, position: Int, id: Long) {
                var i = position
                while (i-- != 0) {
                    onBackPressed()
                }
                if (position != 0) {
                    mToolbarSpinner.setSelection(0)
                }
            }

            override fun onNothingSelected(parent: AdapterView<*>) {
                // no action
            }
        }

        if mCurrentDialog != nil {
            mCurrentDialog.dismiss()
            mCurrentDialog = nil
        }

        checkWritableFolder(mCurrentDir)

        getOnBackPressedDispatcher().addCallback(self, onBackPressedCallback)

        Log_OC.d(TAG, "onCreate() end")
    }

    private func requestPermissions() {
        PermissionUtil.requestExternalStoragePermission(self, viewThemeUtils: viewThemeUtils, true)
    }

    func showToolbarSpinner() {
        mToolbarSpinner.isHidden = false
    }

    private func fillDirectoryDropdown() {
        var currentDir = mCurrentDir
        while let dir = currentDir, let parentDir = dir.parent {
            mDirectories.append(dir.lastPathComponent)
            currentDir = parentDir
        }
        mDirectories.append(FileManager.default.pathSeparator)
    }

    override func onCreateOptionsMenu(_ menu: Menu) -> Bool {
        mOptionsMenu = menu
        menuInflater.inflate(R.menu.activity_upload_files, menu)

        if !mLocalFolderPickerMode {
            if let selectAll = menu.findItem(withId: R.id.action_select_all) {
                setSelectAllMenuItem(selectAll, mSelectAll)
            }
        }

        if let item = menu.findItem(withId: R.id.action_search) {
            mSearchView = item.actionView as? UISearchBar
            viewThemeUtils.androidx.themeToolbarSearchView(mSearchView)
            if let icon = menu.findItem(withId: R.id.action_choose_storage_path)?.icon {
                viewThemeUtils.platform.tintTextDrawable(self, icon)
            }

            mSearchView?.onSearchClick = { [weak self] in
                self?.mToolbarSpinner.isHidden = true
            }
        }

        return super.onCreateOptionsMenu(menu)
    }

    override func onOptionsItemSelected(_ item: MenuItem) -> Bool {
        var retval = true
        let itemId = item.itemId

        if itemId == android.R.id.home {
            if let currentDir = mCurrentDir, currentDir.parentFile != nil {
                onBackPressed()
            }
        } else if itemId == R.id.action_select_all {
            mSelectAll = !item.isChecked
            item.isChecked = mSelectAll
            mFileListFragment.selectAllFiles(mSelectAll)
            setSelectAllMenuItem(item, mSelectAll)
        } else if itemId == R.id.action_choose_storage_path {
            checkLocalStoragePathPickerPermission()
        } else {
            retval = super.onOptionsItemSelected(item)
        }

        return retval
    }

    private func checkLocalStoragePathPickerPermission() {
        if !PermissionUtil.checkExternalStoragePermission(self) {
            requestPermissions()
        } else {
            showLocalStoragePathPickerDialog()
        }
    }

    private func showLocalStoragePathPickerDialog() {
        let fm = self.navigationController
        let dialog = LocalStoragePathPickerDialogFragment.newInstance()
        fm?.pushViewController(dialog, animated: true)
    }

    override func onRequestPermissionsResult(_ requestCode: Int, _ permissions: [String], _ grantResults: [Int]) {
        if requestCode == PermissionUtil.PERMISSIONS_EXTERNAL_STORAGE {
            if grantResults.count > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED {
                showLocalStoragePathPickerDialog()
            } else {
                DisplayUtils.showSnackMessage(self, R.string.permission_storage_access)
            }
        } else {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    func onSortingOrderChosen(selection: FileSortOrder) {
        preferences.setSortOrder(type: .localFileListView, selection: selection)
        mFileListFragment.sortFiles(selection: selection)
    }

    private func isSearchOpen() -> Bool {
        guard let mSearchView = mSearchView else {
            return false
        }
        if let mSearchEditFrame = mSearchView.viewWithTag(androidx.appcompat.R.id.search_edit_frame) {
            return mSearchEditFrame.isHidden == false
        }
        return false
    }

    private let onBackPressedCallback = OnBackPressedCallback(true) {
        override func handleOnBackPressed() {
            if isSearchOpen(), let searchView = mSearchView {
                searchView.setQuery("", submit: false)
                mFileListFragment.onClose()
                searchView.onActionViewCollapsed()
                setDrawerIndicatorEnabled(isDrawerIndicatorAvailable())
            } else {
                if mDirectories.count <= SINGLE_DIR {
                    finish()
                    return
                }

                guard let parentFolder = mCurrentDir.parent else {
                    checkLocalStoragePathPickerPermission()
                    return
                }

                popDirname()
                mFileListFragment.onNavigateUp()
                mCurrentDir = mFileListFragment.getCurrentDirectory()
                checkWritableFolder(mCurrentDir)

                if mCurrentDir.parent == nil {
                    if let actionBar = getSupportActionBar() {
                        actionBar.setDisplayHomeAsUpEnabled(false)
                    }
                }

                if !mLocalFolderPickerMode {
                    if let selectAllMenuItem = mOptionsMenu.findItem(withId: R.id.action_select_all) {
                        setSelectAllMenuItem(selectAllMenuItem, false)
                    }
                }
            }
        }
    }

    override func encodeRestorableState(with coder: NSCoder) {
        FileExtensionsKt.logFileSize(mCurrentDir, TAG)
        super.encodeRestorableState(with: coder)
        coder.encode(mCurrentDir.path, forKey: UploadFilesActivity.KEY_DIRECTORY_PATH)
        if let menu = mOptionsMenu, let selectAllItem = menu.findItem(withIdentifier: R.id.action_select_all) {
            coder.encode(selectAllItem.isChecked, forKey: UploadFilesActivity.KEY_ALL_SELECTED)
        } else {
            coder.encode(false, forKey: UploadFilesActivity.KEY_ALL_SELECTED)
        }
        Log_OC.d(TAG, "encodeRestorableState() end")
    }

    func pushDirname(directory: URL) {
        guard directory.hasDirectoryPath else {
            fatalError("Only directories may be pushed!")
        }
        mDirectories.insert(directory.lastPathComponent, at: 0)
        mCurrentDir = directory
        checkWritableFolder(mCurrentDir)
    }

    func popDirname() -> Bool {
        mDirectories.remove(at: 0)
        return !mDirectories.isEmpty
    }

    private func updateUploadButtonActive() {
        let anySelected = mFileListFragment.getCheckedFilesCount() > 0
        binding.uploadFilesBtnUpload.isEnabled = anySelected || mLocalFolderPickerMode
    }

    private func setSelectAllMenuItem(selectAll: MenuItem?, checked: Bool) {
        if let selectAll = selectAll {
            selectAll.isChecked = checked
            if checked {
                selectAll.icon = UIImage(named: "ic_select_none")
            } else {
                selectAll.icon = viewThemeUtils.platform.tintPrimaryDrawable(self, drawableName: "ic_select_all")
            }
            updateUploadButtonActive()
        }
    }

    override func onCheckAvailableSpaceStart() {
        if requestCode == FileDisplayActivity.REQUEST_CODE__SELECT_FILES_FROM_FILE_SYSTEM {
            mCurrentDialog = IndeterminateProgressDialog.newInstance(R.string.wait_a_moment, false)
            mCurrentDialog.show(getSupportFragmentManager(), WAIT_DIALOG_TAG)
        }
    }

    func onCheckAvailableSpaceFinish(hasEnoughSpaceAvailable: Bool, filesToUpload: String...) {
        if let currentDialog = mCurrentDialog, isDialogFragmentReady(self, currentDialog) {
            currentDialog.dismiss()
            mCurrentDialog = nil
        }

        if hasEnoughSpaceAvailable {
            let data = Intent()

            if requestCode == FileDisplayActivity.REQUEST_CODE__UPLOAD_FROM_CAMERA {
                data.putExtra(EXTRA_CHOSEN_FILES, [filesToUpload[0]])
                setResult(RESULT_OK_AND_DELETE, data)

                preferences.setUploaderBehaviour(FileUploadWorker.LOCAL_BEHAVIOUR_DELETE)
            } else {
                data.putExtra(EXTRA_CHOSEN_FILES, mFileListFragment.getCheckedFilePaths())
                data.putExtra(LOCAL_BASE_PATH, mCurrentDir.absolutePath)

                switch binding.uploadFilesSpinnerBehaviour.selectedItemPosition {
                case 0:
                    setResult(RESULT_OK_AND_MOVE, data)
                case 1:
                    setResult(RESULT_OK_AND_DO_NOTHING, data)
                case 2:
                    setResult(RESULT_OK_AND_DELETE, data)
                default:
                    break
                }

                preferences.setUploaderBehaviour(binding.uploadFilesSpinnerBehaviour.selectedItemPosition)
            }

            finish()
        } else {
            let args = [getString(R.string.app_name)]
            let dialog = ConfirmationDialogFragment.newInstance(
                R.string.upload_query_move_foreign_files, args, 0, R.string.common_yes, R.string.common_no, -1)
            dialog.setOnConfirmationListener(self)
            dialog.show(getSupportFragmentManager(), QUERY_TO_MOVE_DIALOG_TAG)
        }
    }

    func chosenPath(_ path: String) {
        if let localFileListFragment = getListOfFilesFragment() as? LocalFileListFragment {
            let file = File(path: path)
            localFileListFragment.listDirectory(file)
            onDirectoryClick(file)

            mCurrentDir = File(path: path)
            mDirectories.removeAll()

            fillDirectoryDropdown()
        }
    }

    func onDirectoryClick(directory: File) {
        if !mLocalFolderPickerMode {
            if let selectAll = mOptionsMenu.findItem(withId: R.id.action_select_all) {
                setSelectAllMenuItem(selectAll, false)
            }
        }

        pushDirname(directory)
        if let actionBar = getSupportActionBar() {
            actionBar.setDisplayHomeAsUpEnabled(true)
        }
    }

    func checkWritableFolder(folder: URL) {
        let canWriteIntoFolder = FileManager.default.isWritableFile(atPath: folder.path)
        binding.uploadFilesSpinnerBehaviour.isEnabled = canWriteIntoFolder

        let textView = self.view.viewWithTag(R.id.upload_files_upload_files_behaviour_text) as! UILabel

        if canWriteIntoFolder {
            textView.text = NSLocalizedString("uploader_upload_files_behaviour", comment: "")
            let localBehaviour = preferences.getUploaderBehaviour()
            binding.uploadFilesSpinnerBehaviour.selectedSegmentIndex = localBehaviour
        } else {
            binding.uploadFilesSpinnerBehaviour.selectedSegmentIndex = 1
            textView.text = "\(NSLocalizedString("uploader_upload_files_behaviour", comment: "")) \(NSLocalizedString("uploader_upload_files_behaviour_not_writable", comment: ""))"
        }
    }

    func onFileClick(file: File) {
        updateUploadButtonActive()

        let selectAll = mFileListFragment.getCheckedFilesCount() == mFileListFragment.getFilesCount()
        setSelectAllMenuItem(mOptionsMenu.findItem(withId: R.id.action_select_all), selectAll)
    }

    func getInitialDirectory() -> URL {
        return mCurrentDir
    }

    func isFolderPickerMode() -> Bool {
        return mLocalFolderPickerMode
    }

    func isWithinEncryptedFolder() -> Bool {
        return isWithinEncryptedFolder
    }

    override func onClick(_ sender: UIView) {
        if sender.tag == R.id.upload_files_btn_cancel {
            setResult(RESULT_CANCELED)
            finish()
        } else if sender.tag == R.id.upload_files_btn_upload {
            if PermissionUtil.checkExternalStoragePermission(self) {
                if let currentDir = mCurrentDir {
                    preferences.setUploadFromLocalLastPath(currentDir.absolutePath)
                }
                if mLocalFolderPickerMode {
                    let data = Intent()
                    if let currentDir = mCurrentDir {
                        data.putExtra(EXTRA_CHOSEN_FILES, currentDir.absolutePath)
                    }
                    setResult(RESULT_OK, data)
                    finish()
                } else {
                    let selectedFilePaths = mFileListFragment.getCheckedFilePaths()
                    let isPositionZero = (binding.uploadFilesSpinnerBehaviour.selectedItemPosition == 0)
                    CheckAvailableSpaceTask(self, selectedFilePaths).execute(isPositionZero)
                }
            } else {
                requestPermissions()
            }
        }
    }

    func onConfirmation(callerTag: String) {
        Log_OC.d(TAG, "Positive button in dialog was clicked; dialog tag is \(callerTag)")
        if mFileListFragment.getCheckedFilePaths().count > FileUploadHelper.MAX_FILE_COUNT {
            DisplayUtils.showSnackMessage(self, R.string.max_file_count_warning_message)
            return
        }

        if QUERY_TO_MOVE_DIALOG_TAG == callerTag {
            let data = Intent()
            data.putExtra(EXTRA_CHOSEN_FILES, mFileListFragment.getCheckedFilePaths())
            data.putExtra(LOCAL_BASE_PATH, mCurrentDir.absolutePath)
            setResult(RESULT_OK_AND_MOVE, data)
            finish()
        }
    }

    func onNeutral(callerTag: String) {
        print("Phantom neutral button in dialog was clicked; dialog tag is \(callerTag)")
    }

    func onCancel(callerTag: String) {
        Log_OC.d(TAG, "Negative button in dialog was clicked; dialog tag is \(callerTag)")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let account = getAccount()
        if let accountOnCreation = mAccountOnCreation, accountOnCreation == account {
            requestPermissions()
        } else {
            setResult(RESULT_CANCELED)
            finish()
        }
    }

    private func isGridView() -> Bool {
        return getListOfFilesFragment().isGridEnabled()
    }

    private func getListOfFilesFragment() -> ExtendedListFragment? {
        if mFileListFragment == nil {
            Log_OC.e(TAG, "Access to unexisting list of files fragment!!")
        }
        
        return mFileListFragment
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if dialog != nil {
            dialog.dismiss(animated: false, completion: nil)
        }
    }
}
