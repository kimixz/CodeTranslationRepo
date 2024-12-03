
import UIKit
import NextcloudClient
import OwnCloudClient
import EventBus

class FileDetailActivitiesFragment: UIViewController, ActivityListInterface, DisplayUtils.AvatarGenerationListener, VersionListInterface.View, Injectable {

    private static let TAG = String(describing: FileDetailActivitiesFragment.self)

    private static let ARG_FILE = "FILE"
    private static let ARG_USER = "USER"
    private static let END_REACHED = 0

    private var adapter: ActivityAndVersionListAdapter!
    private var ownCloudClient: OwnCloudClient!
    private var nextcloudClient: NextcloudClient!

    private var file: OCFile!
    private var user: User!

    private var lastGiven: Int = 0
    private var isLoadingActivities: Bool = false
    private var isDataFetched: Bool = false

    private var restoreFileVersionSupported: Bool = false
    private var operationsHelper: FileOperationsHelper!
    private var callback: VersionListInterface.CommentCallback!

    private var binding: FileDetailsActivitiesFragmentBinding!

    @Inject var accountManager: UserAccountManager!
    @Inject var clientFactory: ClientFactory!
    @Inject var contentResolver: ContentResolver!
    @Inject var viewThemeUtils: ViewThemeUtils!

    static func newInstance(file: OCFile, user: User) -> FileDetailActivitiesFragment {
        let fragment = FileDetailActivitiesFragment()
        let args = Bundle()
        args.putParcelable(ARG_FILE, file)
        args.putParcelable(ARG_USER, user)
        fragment.setArguments(args)
        return fragment
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let arguments = self.arguments else {
            fatalError("arguments are mandatory")
        }
        file = arguments.getParcelableArgument(ARG_FILE, OCFile.self)
        user = arguments.getParcelableArgument(ARG_USER, User.self)

        if let savedInstanceState = savedInstanceState {
            file = savedInstanceState.getParcelableArgument(ARG_FILE, OCFile.self)
            user = savedInstanceState.getParcelableArgument(ARG_USER, User.self)
        }

        binding = FileDetailsActivitiesFragmentBinding.inflate(inflater, container: container, savedInstanceState: savedInstanceState)
        let view = binding.root

        setupView()

        viewThemeUtils.androidx.themeSwipeRefreshLayout(binding.swipeContainingEmpty)
        viewThemeUtils.androidx.themeSwipeRefreshLayout(binding.swipeContainingList)

        isLoadingActivities = true
        fetchAndSetData(-1)

        binding.swipeContainingList.setOnRefreshListener {
            setLoadingMessage()
            binding.swipeContainingList.isRefreshing = true
            fetchAndSetData(-1)
        }

        binding.swipeContainingEmpty.setOnRefreshListener {
            setLoadingMessageEmpty()
            fetchAndSetData(-1)
        }

        callback = VersionListInterface.CommentCallback(
            onSuccess: {
                binding.commentInputField.text = ""
                fetchAndSetData(-1)
            },
            onError: { error in
                Snackbar.make(binding.list, error, Snackbar.LENGTH_LONG).show()
            }
        )

        binding.submitComment.setOnClickListener { _ in
            submitComment()
        }

        viewThemeUtils.material.colorTextInputLayout(binding.commentInputFieldContainer)

        DisplayUtils.setAvatar(user,
                               self,
                               resources.dimension(R.dimen.activity_icon_radius),
                               resources,
                               binding.avatar,
                               context)

        return view
    }

    func submitComment() {
        guard let commentField = binding.commentInputField.text else {
            return
        }

        let trimmedComment = commentField.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedComment.isEmpty, let nextcloudClient = nextcloudClient, isDataFetched {
            SubmitCommentTask(trimmedComment: trimmedComment, localId: file.localId, callback: callback, nextcloudClient: nextcloudClient).execute()
        }
    }

    private func setLoadingMessage() {
        binding.swipeContainingEmpty.isHidden = true
    }

    func setLoadingMessageEmpty() {
        binding.swipeContainingList.isHidden = true
        binding.emptyList.emptyListView.isHidden = true
        binding.loadingContent.isHidden = false
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        binding = nil
    }

    private func setupView() {
        let storageManager = FileDataStorageManager(user: user, contentResolver: contentResolver)
        operationsHelper = (requireActivity() as! ComponentsGetter).getFileOperationsHelper()

        let capability = storageManager.getCapability(user.accountName)
        restoreFileVersionSupported = capability.filesVersioning.isTrue()

        binding.emptyList.emptyListIcon.image = UIImage(named: "ic_activity")
        binding.emptyList.emptyListView.isHidden = true

        adapter = ActivityAndVersionListAdapter(context: getContext(),
                                                accountManager: accountManager,
                                                delegate: self,
                                                dataSource: self,
                                                clientFactory: clientFactory,
                                                viewThemeUtils: viewThemeUtils)
        binding.list.adapter = adapter

        let layoutManager = LinearLayoutManager(context: getContext())
        binding.list.layoutManager = layoutManager
        binding.list.addOnScrollListener(object: RecyclerView.OnScrollListener() {
            override func onScrolled(_ recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx: dx, dy: dy)

                let visibleItemCount = recyclerView.childCount
                let totalItemCount = layoutManager.itemCount
                let firstVisibleItemIndex = layoutManager.findFirstVisibleItemPosition()

                if !isLoadingActivities && (totalItemCount - visibleItemCount) <= (firstVisibleItemIndex + 5) && lastGiven > 0 {
                    fetchAndSetData(lastGiven)
                }
            }
        })
    }

    func reload() {
        fetchAndSetData(-1)
    }

    private func fetchAndSetData(lastGiven: Int) {
        guard let activity = self.activity else {
            Log_OC.e(self, "Activity is null, aborting!")
            return
        }

        let user = accountManager.getUser()

        if user.isAnonymous() {
            DispatchQueue.main.async {
                self.setEmptyContent(getString(R.string.common_error), getString(R.string.file_detail_activity_error))
            }
            return
        }

        if !isLoadingActivities {
            return
        }

        let t = Thread {
            do {
                self.ownCloudClient = try clientFactory.create(user)
                self.nextcloudClient = try clientFactory.createNextcloudClient(user)

                self.isLoadingActivities = true

                let getRemoteNotificationOperation: GetActivitiesRemoteOperation

                if lastGiven > 0 {
                    getRemoteNotificationOperation = GetActivitiesRemoteOperation(file.getLocalId(), lastGiven)
                } else {
                    getRemoteNotificationOperation = GetActivitiesRemoteOperation(file.getLocalId())
                }

                Log_OC.d(TAG, "BEFORE getRemoteActivitiesOperation.execute")
                let result = self.nextcloudClient.execute(getRemoteNotificationOperation)

                var versions: [Any]? = nil
                if restoreFileVersionSupported {
                    let readFileVersionsOperation = ReadFileVersionsRemoteOperation(file.getLocalId())

                    let result1 = readFileVersionsOperation.execute(self.ownCloudClient)

                    if result1.isSuccess() {
                        versions = result1.getData()
                    }
                }

                if result.isSuccess(), let data = result.getData() {
                    let activitiesAndVersions = data[0] as! [Any]

                    self.lastGiven = data[1] as! Int

                    if activitiesAndVersions.isEmpty {
                        self.lastGiven = END_REACHED
                    }

                    if restoreFileVersionSupported, let versions = versions {
                        activitiesAndVersions.append(contentsOf: versions)
                    }

                    DispatchQueue.main.async {
                        if self.lifecycle.currentState.isAtLeast(.resumed) {
                            self.populateList(activitiesAndVersions, self.lastGiven == -1)
                        }
                    }

                    self.isDataFetched = true
                } else {
                    Log_OC.d(TAG, result.getLogMessage())
                    var logMessage = result.getLogMessage()
                    if result.getHttpCode() == HttpStatus.SC_NOT_MODIFIED {
                        logMessage = getString(R.string.activities_no_results_message)
                    }
                    let finalLogMessage = logMessage
                    DispatchQueue.main.async {
                        if self.lifecycle.currentState.isAtLeast(.resumed) {
                            self.setErrorContent(finalLogMessage)
                            self.isLoadingActivities = false
                        }
                    }

                    self.isDataFetched = false
                }

                self.hideRefreshLayoutLoader(activity)
            } catch {
                self.isDataFetched = false
                Log_OC.e(TAG, "Error fetching file details activities", error)
            }
        }

        t.start()
    }

    func markCommentsAsRead() {
        DispatchQueue.global().async {
            if file.getUnreadCommentsCount() > 0 {
                let unreadOperation = MarkCommentsAsReadRemoteOperation(file.getLocalId())
                let remoteOperationResult = unreadOperation.execute(ownCloudClient)

                if remoteOperationResult.isSuccess() {
                    EventBus.getDefault().post(CommentsEvent(file.getRemoteId()))
                }
            }
        }
    }

    func populateList(activities: [Any], clear: Bool) {
        adapter.setActivityAndVersionItems(activities: activities, nextcloudClient: nextcloudClient, clear: clear)

        if adapter.getItemCount() == 0 {
            setEmptyContent(
                headline: NSLocalizedString("activities_no_results_headline", comment: ""),
                message: NSLocalizedString("activities_no_results_message", comment: "")
            )
        } else {
            binding.swipeContainingList.isHidden = false
            binding.swipeContainingEmpty.isHidden = true
            binding.emptyList.emptyListView.isHidden = true
        }
        isLoadingActivities = false
    }

    private func setEmptyContent(headline: String, message: String) {
        setInfoContent(image: R.drawable.ic_activity, headline: headline, message: message)
    }

    func setErrorContent(_ message: String) {
        setInfoContent(image: UIImage(named: "ic_list_empty_error")!, title: NSLocalizedString("common_error", comment: ""), message: message)
    }

    private func setInfoContent(icon: Int, headline: String, message: String) {
        binding.emptyList.emptyListIcon.image = UIImage(named: String(icon))
        binding.emptyList.emptyListViewHeadline.text = headline
        binding.emptyList.emptyListViewText.text = message

        binding.swipeContainingList.isHidden = true
        binding.loadingContent.isHidden = true

        binding.emptyList.emptyListViewHeadline.isHidden = false
        binding.emptyList.emptyListViewText.isHidden = false
        binding.emptyList.emptyListIcon.isHidden = false
        binding.emptyList.emptyListView.isHidden = false
        binding.swipeContainingEmpty.isHidden = false
    }

    private func hideRefreshLayoutLoader(activity: FragmentActivity) {
        DispatchQueue.main.async {
            if self.lifecycle.currentState.isAtLeast(.resumed) {
                self.binding.swipeContainingList.isRefreshing = false
                self.binding.swipeContainingEmpty.isRefreshing = false
                self.binding.emptyList.emptyListView.isHidden = true
                self.isLoadingActivities = false
            }
        }
    }

    func onActivityClicked(richObject: RichObject) {
        // TODO implement activity click
    }

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        logFileSize(file: file, tag: TAG)
        coder.encode(file, forKey: ARG_FILE)
        coder.encode(user, forKey: ARG_USER)
    }

    func onRestoreClicked(fileVersion: FileVersion) {
        operationsHelper.restoreFileVersion(fileVersion)
    }

    override func avatarGenerated(avatarDrawable: Drawable, callContext: Any?) {
        binding.avatar.image = avatarDrawable
    }

    override func shouldCallGeneratedCallback(tag: String, callContext: Any) -> Bool {
        return false
    }

    @objc func disableLoadingActivities() {
        isLoadingActivities = false
    }

    private class SubmitCommentTask: AsyncTask<Void, Void, Bool> {

        private let message: String
        private let fileId: Int64
        private let callback: VersionListInterface.CommentCallback
        private let client: NextcloudClient

        init(message: String, fileId: Int64, callback: VersionListInterface.CommentCallback, client: NextcloudClient) {
            self.message = message
            self.fileId = fileId
            self.callback = callback
            self.client = client
        }

        override func doInBackground() -> Bool {
            let commentFileOperation = CommentFileOperation(message: message, fileId: fileId)
            let result = commentFileOperation.execute(client: client)
            return result.isSuccess()
        }

        override func onPostExecute(success: Bool) {
            super.onPostExecute(success: success)

            if success {
                callback.onSuccess()
            } else {
                callback.onError(R.string.error_comment_file)
            }
        }
    }
}
