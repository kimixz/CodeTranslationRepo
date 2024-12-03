
import UIKit

class ExtendedListFragment: UIViewController, UISearchBarDelegate {
    
    static let TAG = String(describing: ExtendedListFragment.self)
    
    static let KEY_SAVED_LIST_POSITION = "SAVED_LIST_POSITION"
    
    private static let KEY_INDEXES = "INDEXES"
    private static let KEY_FIRST_POSITIONS = "FIRST_POSITIONS"
    private static let KEY_TOPS = "TOPS"
    private static let KEY_HEIGHT_CELL = "HEIGHT_CELL"
    private static let KEY_EMPTY_LIST_MESSAGE = "EMPTY_LIST_MESSAGE"
    private static let KEY_IS_GRID_VISIBLE = "IS_GRID_VISIBLE"
    public static let minColumnSize: Float = 2.0
    
    private var maxColumnSize = 5
    
    @Inject var preferences: AppPreferences!
    @Inject var accountManager: UserAccountManager!
    @Inject var viewThemeUtils: ViewThemeUtils!
    
    private var mScaleGestureDetector: UIPinchGestureRecognizer!
    protected var mRefreshListLayout: UIRefreshControl!
    protected var mSortButton: UIButton!
    protected var mSwitchGridViewButton: UIButton!
    protected var mEmptyListContainer: UIView!
    protected var mEmptyListMessage: UILabel!
    protected var mEmptyListHeadline: UILabel!
    protected var mEmptyListIcon: UIImageView!
    
    private var mIndexes = [Int]()
    private var mFirstPositions = [Int]()
    private var mTops = [Int]()
    private var mHeightCell = 0
    
    private var mOnRefreshListener: OnEnforceableRefreshListener?
    
    private var mRecyclerView: UICollectionView!
    
    protected var searchView: UISearchBar!
    private var closeButton: UIButton!
    private let handler = DispatchQueue.main
    
    private var mScale: Float = AppPreferencesImpl.DEFAULT_GRID_COLUMN
    
    private var binding: ListFragmentBinding!
    
    func getBinding() -> ListFragmentBinding {
        return binding
    }
    
    protected func setRecyclerViewAdapter(_ recyclerViewAdapter: UICollectionViewDataSource) {
        mRecyclerView.dataSource = recyclerViewAdapter
    }
    
    protected func getRecyclerView() -> UICollectionView? {
        return mRecyclerView
    }
    
    public func setLoading(_ enabled: Bool) {
        mRefreshListLayout.isRefreshing = enabled
    }
    
    public func switchToGridView() {
        if !isGridEnabled() {
            getRecyclerView()?.setCollectionViewLayout(UICollectionViewFlowLayout(), animated: true)
        }
    }
    
    public func switchToListView() {
        if isGridEnabled() {
            getRecyclerView()?.setCollectionViewLayout(UICollectionViewFlowLayout(), animated: true)
        }
    }
    
    public func isGridEnabled() -> Bool {
        if let recyclerView = getRecyclerView() {
            return recyclerView.collectionViewLayout is UICollectionViewFlowLayout
        } else {
            return false
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("onCreateView")
        
        binding = ListFragmentBinding.inflate(inflater: nil, container: nil, savedInstanceState: nil)
        let v = binding.root
        
        setupEmptyList(v)
        
        mRecyclerView = binding.listRoot
        mRecyclerView.hasFooter = true
        mRecyclerView.emptyView = binding.emptyList.emptyListView
        mRecyclerView.hasFixedSize = true
        mRecyclerView.collectionViewLayout = UICollectionViewFlowLayout()
        
        mScale = preferences.getGridColumns()
        setGridViewColumns(1.0)
        
        mScaleGestureDetector = UIPinchGestureRecognizer(target: self, action: #selector(scaleListener))
        
        getRecyclerView()?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        
        mRefreshListLayout = UIRefreshControl()
        viewThemeUtils.androidx.themeSwipeRefreshLayout(mRefreshListLayout)
        mRefreshListLayout.addTarget(self, action: #selector(refreshList), for: .valueChanged)
        
        mSortButton = getActivity()?.view.viewWithTag(R.id.sort_button) as? UIButton
        if let sortButton = mSortButton {
            viewThemeUtils.material.colorMaterialTextButton(sortButton)
        }
        mSwitchGridViewButton = getActivity()?.view.viewWithTag(R.id.switch_grid_view_button) as? UIButton
        if let switchGridViewButton = mSwitchGridViewButton {
            viewThemeUtils.material.colorMaterialTextButton(switchGridViewButton)
        }
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            sender.view?.performClick()
        }
    }
    
    @objc func scaleListener(_ gestureRecognizer: UIPinchGestureRecognizer) {
        // Handle scale gesture
    }
    
    @objc func refreshList() {
        // Handle refresh
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        binding = nil
        if let adapter = getRecyclerView()?.dataSource as? OCFileListAdapter {
            adapter.onDestroy()
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        let isLandscape = size.width > size.height
        maxColumnSize = isLandscape ? 10 : 5
        
        if isGridEnabled() && getColumnsCount() > maxColumnSize {
            if let layout = getRecyclerView()?.collectionViewLayout as? UICollectionViewFlowLayout {
                layout.itemSize = CGSize(width: size.width / CGFloat(maxColumnSize), height: layout.itemSize.height)
            }
        }
    }
    
    func setGridViewColumns(scaleFactor: Float) {
        if let gridLayoutManager = mRecyclerView.collectionViewLayout as? UICollectionViewFlowLayout {
            if mScale == -1.0 {
                gridLayoutManager.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
                mScale = Float(gridLayoutManager.estimatedItemSize.width)
            }
            mScale *= 1.0 - (scaleFactor - 1.0)
            mScale = max(minColumnSize, min(mScale, maxColumnSize))
            let scaleInt = Int(round(mScale))
            gridLayoutManager.itemSize = CGSize(width: CGFloat(scaleInt), height: gridLayoutManager.itemSize.height)
            mRecyclerView.reloadData()
        }
    }
    
    func setupEmptyList(view: UIView) {
        mEmptyListContainer = binding.emptyList.emptyListView
        mEmptyListMessage = binding.emptyList.emptyListViewText
        mEmptyListHeadline = binding.emptyList.emptyListViewHeadline
        mEmptyListIcon = binding.emptyList.emptyListIcon
    }
    
    func onQueryTextChange(_ query: String) -> Bool {
        // After 300 ms, set the query
        
        closeButton.isHidden = false
        if query.isEmpty {
            closeButton.isHidden = true
        }
        return false
    }
    
    func onQueryTextSubmit(_ query: String) -> Bool {
        if let adapter = getRecyclerView()?.dataSource as? OCFileListAdapter {
            let listOfHiddenFiles = adapter.listOfHiddenFiles
            performSearch(query: query, listOfHiddenFiles: listOfHiddenFiles, isBackPressed: false)
            return true
        }
        if getRecyclerView()?.dataSource is LocalFileListAdapter {
            performSearch(query: query, listOfHiddenFiles: [], isBackPressed: false)
            return true
        }
        return false
    }
    
    func performSearch(query: String, listOfHiddenFiles: [String], isBackPressed: Bool) {
        handler.async {
            let adapter = self.getRecyclerView()?.dataSource
            let activity = self.getActivity()
            
            if let activity = activity {
                if let fileDisplayActivity = activity as? FileDisplayActivity {
                    if isBackPressed && query.isEmpty {
                        fileDisplayActivity.resetSearchView()
                        fileDisplayActivity.updateListOfFilesFragment(true)
                    } else {
                        self.handler.async {
                            if let ocFileListAdapter = adapter as? OCFileListAdapter {
                                if self.accountManager.user.server.version.isNewerOrEqual(to: OwnCloudVersion.nextcloud_20) {
                                    fileDisplayActivity.performUnifiedSearch(query: query, listOfHiddenFiles: listOfHiddenFiles)
                                } else {
                                    EventBus.default.post(SearchEvent(query: query, searchType: .fileSearch))
                                }
                            } else if let localFileListAdapter = adapter as? LocalFileListAdapter {
                                localFileListAdapter.filter(query: query)
                            }
                        }
                        
                        self.searchView?.resignFirstResponder()
                    }
                } else if let uploadFilesActivity = activity as? UploadFilesActivity {
                    if let localFileListAdapter = adapter as? LocalFileListAdapter {
                        localFileListAdapter.filter(query: query)
                        uploadFilesActivity.getFileListFragment().setLoading(false)
                    }
                } else if let folderPickerActivity = activity as? FolderPickerActivity {
                    folderPickerActivity.search(query: query)
                }
            }
        }
    }
    
    func onClose() -> Bool {
        if let adapter = getRecyclerView()?.dataSource as? OCFileListAdapter {
            let listOfHiddenFiles = adapter.listOfHiddenFiles
            performSearch(query: "", listOfHiddenFiles: listOfHiddenFiles, isBackPressed: true)
            return false
        }
        return true
    }
    
    func setOnRefreshListener(listener: OnEnforceableRefreshListener) {
        mOnRefreshListener = listener
    }
    
    func setSwipeEnabled(_ enabled: Bool) {
        mRefreshListLayout.isEnabled = enabled
    }
    
    func setMessageForEmptyList(message: String) {
        if let emptyListContainer = mEmptyListContainer, let emptyListMessage = mEmptyListMessage {
            emptyListMessage.text = message
        }
    }
    
    func setMessageForEmptyList(headline: Int, message: Int, icon: Int) {
        setMessageForEmptyList(headline: headline, message: message, icon: icon, tintIcon: false)
    }
    
    func setMessageForEmptyList(headline: Int, message: Int, icon: Int, tintIcon: Bool) {
        DispatchQueue.main.async {
            if let emptyListContainer = self.mEmptyListContainer, let emptyListMessage = self.mEmptyListMessage {
                self.mEmptyListHeadline.text = NSLocalizedString(String(headline), comment: "")
                self.mEmptyListMessage.text = NSLocalizedString(String(message), comment: "")
                
                if tintIcon {
                    if let context = self.getContext() {
                        self.mEmptyListIcon.image = self.viewThemeUtils.platform.tintPrimaryDrawable(context: context, icon: icon)
                    }
                } else {
                    self.mEmptyListIcon.image = UIImage(named: String(icon))
                }
                
                self.mEmptyListIcon.isHidden = false
                self.mEmptyListMessage.isHidden = false
            }
        }
    }
    
    func setEmptyListMessage(searchType: SearchType) {
        DispatchQueue.main.async {
            switch searchType {
            case .offlineMode:
                self.setMessageForEmptyList(headline: R.string.offline_mode_info_title,
                                            message: R.string.offline_mode_info_description,
                                            icon: R.drawable.ic_cloud_sync,
                                            tintIcon: true)
            case .noSearch:
                self.setMessageForEmptyList(headline: R.string.file_list_empty_headline,
                                            message: R.string.file_list_empty,
                                            icon: R.drawable.ic_list_empty_folder,
                                            tintIcon: true)
            case .fileSearch:
                self.setMessageForEmptyList(headline: R.string.file_list_empty_headline_server_search,
                                            message: R.string.file_list_empty,
                                            icon: R.drawable.ic_search_light_grey)
            case .favoriteSearch:
                self.setMessageForEmptyList(headline: R.string.file_list_empty_favorite_headline,
                                            message: R.string.file_list_empty_favorites_filter_list,
                                            icon: R.drawable.ic_star_light_yellow)
            case .recentlyModifiedSearch:
                self.setMessageForEmptyList(headline: R.string.file_list_empty_headline_server_search,
                                            message: R.string.file_list_empty_recently_modified,
                                            icon: R.drawable.ic_list_empty_recent)
            case .regularFilter:
                self.setMessageForEmptyList(headline: R.string.file_list_empty_headline_search,
                                            message: R.string.file_list_empty_search,
                                            icon: R.drawable.ic_search_light_grey)
            case .sharedFilter:
                self.setMessageForEmptyList(headline: R.string.file_list_empty_shared_headline,
                                            message: R.string.file_list_empty_shared,
                                            icon: R.drawable.ic_list_empty_shared)
            case .gallerySearch:
                self.setMessageForEmptyList(headline: R.string.file_list_empty_headline_server_search,
                                            message: R.string.file_list_empty_gallery,
                                            icon: R.drawable.file_image)
            case .localSearch:
                self.setMessageForEmptyList(headline: R.string.file_list_empty_headline_server_search,
                                            message: R.string.file_list_empty_local_search,
                                            icon: R.drawable.ic_search_light_grey)
            }
        }
    }
    
    func setEmptyListLoadingMessage() {
        DispatchQueue.main.async {
            if let fileActivity = self as? FileActivity {
                fileActivity.connectivityService.isNetworkAndServerAvailable { result in
                    guard result, self.mEmptyListContainer != nil, self.mEmptyListMessage != nil else { return }
                    
                    self.mEmptyListHeadline.text = NSLocalizedString("file_list_loading", comment: "")
                    self.mEmptyListMessage.text = ""
                    self.mEmptyListIcon.isHidden = true
                }
            }
        }
    }
    
    func getEmptyViewText() -> String {
        return (mEmptyListContainer != nil && mEmptyListMessage != nil) ? mEmptyListMessage.text ?? "" : ""
    }
    
    func onRefresh(ignoreETag: Bool) {
        if let listener = mOnRefreshListener {
            if let fileDisplayActivity = listener as? FileDisplayActivity {
                fileDisplayActivity.onRefresh(ignoreETag: ignoreETag)
            } else {
                listener.onRefresh()
            }
        }
    }
    
    func setGridSwitchButton() {
        if isGridEnabled() {
            mSwitchGridViewButton.accessibilityLabel = NSLocalizedString("action_switch_list_view", comment: "")
            mSwitchGridViewButton.setImage(UIImage(named: "ic_view_list"), for: .normal)
        } else {
            mSwitchGridViewButton.accessibilityLabel = NSLocalizedString("action_switch_grid_view", comment: "")
            mSwitchGridViewButton.setImage(UIImage(named: "ic_view_module"), for: .normal)
        }
    }
}
