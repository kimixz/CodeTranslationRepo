
import UIKit

class UploadListActivity: FileActivity {

    private static let TAG = String(describing: UploadListActivity.self)

    private var uploadMessagesReceiver: UploadMessagesReceiver?
    private var uploadListAdapter: UploadListAdapter!
    public var swipeListRefreshLayout: UIRefreshControl!

    @Inject var userAccountManager: UserAccountManager!
    @Inject var uploadsStorageManager: UploadsStorageManager!
    @Inject var powerManagementService: PowerManagementService!
    @Inject var clock: Clock!
    @Inject var backgroundJobManager: BackgroundJobManager!
    @Inject var syncedFolderProvider: SyncedFolderProvider!
    @Inject var localBroadcastManager: LocalBroadcastManager!
    @Inject var throttler: Throttler!

    private var binding: UploadListLayoutBinding!

    static func createIntent(file: OCFile, user: User, flag: Int?, context: Context) -> Intent {
        let intent = Intent(context: context, UploadListActivity.self)
        if let flag = flag {
            intent.setFlags(intent.getFlags() | flag)
        }
        intent.putExtra(ConflictsResolveActivity.EXTRA_FILE, file)
        intent.putExtra(ConflictsResolveActivity.EXTRA_USER, user)
        
        return intent
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        throttler.setIntervalMillis(1000)

        binding = UploadListLayoutBinding.inflate(getLayoutInflater())
        view = binding.root

        swipeListRefreshLayout = binding.swipeContainingList

        setFile(nil)

        setupToolbar()

        updateActionBarTitleAndHomeButtonByString(getString(R.string.uploads_view_title))

        setupDrawer()

        setupContent()
        observeWorkerState()
    }

    private func observeWorkerState() {
        WorkerStateLiveData.instance().observe(self) { state in
            if state is WorkerState.UploadStarted {
                Log_OC.d(TAG, "Upload worker started")
                handleUploadWorkerState()
            }
        }
    }

    private func handleUploadWorkerState() {
        uploadListAdapter.loadUploadItemsFromDb()
    }

    private func setupContent() {
        binding.list.emptyView = binding.emptyList.root
        binding.emptyList.root.isHidden = true
        binding.emptyList.emptyListIcon.image = UIImage(named: "uploads")
        binding.emptyList.emptyListIcon.image?.withRenderingMode(.alwaysOriginal)
        binding.emptyList.emptyListIcon.alpha = 0.5
        binding.emptyList.emptyListIcon.isHidden = false
        binding.emptyList.emptyListViewHeadline.text = NSLocalizedString("upload_list_empty_headline", comment: "")
        binding.emptyList.emptyListViewText.text = NSLocalizedString("upload_list_empty_text_auto_upload", comment: "")
        binding.emptyList.emptyListViewText.isHidden = false

        uploadListAdapter = UploadListAdapter(
            context: self,
            uploadsStorageManager: uploadsStorageManager,
            storageManager: getStorageManager(),
            userAccountManager: userAccountManager,
            connectivityService: connectivityService,
            powerManagementService: powerManagementService,
            clock: clock,
            viewThemeUtils: viewThemeUtils
        )

        let lm = GridLayoutManager(context: self, spanCount: 1)
        uploadListAdapter.setLayoutManager(lm)

        let spacing = Int(UIApplication.shared.delegate?.window??.rootViewController?.view.frame.size.width ?? 0)
        binding.list.addItemDecoration(MediaGridItemDecoration(spacing: spacing))
        binding.list.layoutManager = lm
        binding.list.adapter = uploadListAdapter

        viewThemeUtils.androidxThemeSwipeRefreshLayout(swipeListRefreshLayout)
        swipeListRefreshLayout.addTarget(self, action: #selector(refresh), for: .valueChanged)

        loadItems()
        uploadListAdapter.loadUploadItemsFromDb()
    }

    private func loadItems() {
        uploadListAdapter.loadUploadItemsFromDb()

        if uploadListAdapter.getItemCount() > 0 {
            return
        }

        swipeListRefreshLayout.isHidden = false
        swipeListRefreshLayout.isRefreshing = false
    }

    @objc private func refresh() {
        FilesSyncHelper.startFilesSyncForAllFolders(syncedFolderProvider: syncedFolderProvider,
                                                    backgroundJobManager: backgroundJobManager,
                                                    force: true,
                                                    folderIds: [])

        if uploadsStorageManager.getFailedUploads().count > 0 {
            DispatchQueue.global().async {
                FileUploadHelper.instance().retryFailedUploads(
                    uploadsStorageManager: uploadsStorageManager,
                    connectivityService: connectivityService,
                    accountManager: accountManager,
                    powerManagementService: powerManagementService)
                DispatchQueue.main.async {
                    self.uploadListAdapter.loadUploadItemsFromDb()
                }
            }
            DisplayUtils.showSnackMessage(context: self, messageId: R.string.uploader_local_files_uploaded)
        }

        uploadListAdapter.loadUploadItemsFromDb()
        swipeListRefreshLayout.setRefreshing(false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Log_OC.v(TAG, "viewWillAppear() start")

        uploadMessagesReceiver = UploadMessagesReceiver()
        let uploadIntentFilter = NotificationCenter.default
        uploadIntentFilter.addObserver(uploadMessagesReceiver, selector: #selector(handleUploadsAdded), name: NSNotification.Name(FileUploadWorker.uploadsAddedMessage), object: nil)
        uploadIntentFilter.addObserver(uploadMessagesReceiver, selector: #selector(handleUploadStart), name: NSNotification.Name(FileUploadWorker.uploadStartMessage), object: nil)
        uploadIntentFilter.addObserver(uploadMessagesReceiver, selector: #selector(handleUploadFinish), name: NSNotification.Name(FileUploadWorker.uploadFinishMessage), object: nil)

        Log_OC.v(TAG, "viewWillAppear() end")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Log_OC.v(TAG, "viewWillDisappear() start")
        if let receiver = uploadMessagesReceiver {
            localBroadcastManager.removeObserver(receiver)
            uploadMessagesReceiver = nil
        }
        Log_OC.v(TAG, "viewWillDisappear() end")
    }

    override func onCreateOptionsMenu(_ menu: Menu) -> Bool {
        let inflater = menuInflater
        inflater.inflate(R.menu.activity_upload_list, menu)
        updateGlobalPauseIcon(menu.getItem(0))
        return true
    }

    func updateGlobalPauseIcon(pauseMenuItem: UIBarButtonItem) {
        guard pauseMenuItem.tag == R.id.action_toggle_global_pause else {
            return
        }

        let iconId: UIImage
        let title: String
        if preferences.isGlobalUploadPaused() {
            iconId = UIImage(named: "ic_global_resume")!
            title = NSLocalizedString("upload_action_global_upload_resume", comment: "")
        } else {
            iconId = UIImage(named: "ic_global_pause")!
            title = NSLocalizedString("upload_action_global_upload_pause", comment: "")
        }

        pauseMenuItem.image = iconId
        pauseMenuItem.title = title
    }

    private func toggleGlobalPause(pauseMenuItem: MenuItem) {
        preferences.setGlobalUploadPaused(!preferences.isGlobalUploadPaused())
        updateGlobalPauseIcon(pauseMenuItem)

        for user in accountManager.getAllUsers() {
            if let user = user {
                FileUploadHelper.instance().cancelAndRestartUploadJob(user: user)
            }
        }

        uploadListAdapter.notifyDataSetChanged()
    }

    override func onOptionsItemSelected(_ item: MenuItem) -> Bool {
        let itemId = item.itemId

        if itemId == android.R.id.home {
            if isDrawerOpen() {
                closeDrawer()
            } else {
                openDrawer()
            }
        } else if itemId == R.id.action_toggle_global_pause {
            toggleGlobalPause(item)
        } else {
            return super.onOptionsItemSelected(item)
        }

        return true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(handleActivityResult(_:)), name: .activityResult, object: nil)
    }

    @objc func handleActivityResult(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let requestCode = userInfo["requestCode"] as? Int,
              let resultCode = userInfo["resultCode"] as? Int else { return }
        
        if requestCode == FileActivity.REQUEST_CODE__UPDATE_CREDENTIALS && resultCode == RESULT_OK {
            FilesSyncHelper.restartUploadsIfNeeded(uploadsStorageManager: uploadsStorageManager,
                                                   userAccountManager: userAccountManager,
                                                   connectivityService: connectivityService,
                                                   powerManagementService: powerManagementService)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: .activityResult, object: nil)
    }

    override func onRemoteOperationFinish(operation: RemoteOperation, result: RemoteOperationResult) {
        if operation is CheckCurrentCredentialsOperation {
            getFileOperationsHelper().setOpIdWaitingFor(Int64.max)
            dismissLoadingDialog()
            if let account = result.getData().first as? Account {
                if !result.isSuccess() {
                    requestCredentialsUpdate(self, account: account)
                } else {
                    FilesSyncHelper.restartUploadsIfNeeded(uploadsStorageManager: uploadsStorageManager,
                                                           userAccountManager: userAccountManager,
                                                           connectivityService: connectivityService,
                                                           powerManagementService: powerManagementService)
                }
            }
        } else {
            super.onRemoteOperationFinish(operation: operation, result: result)
        }
    }

    override func onReceive(context: Context, intent: Intent) {
        throttler.run("update_upload_list") {
            uploadListAdapter.loadUploadItemsFromDb()
        }
    }
}
