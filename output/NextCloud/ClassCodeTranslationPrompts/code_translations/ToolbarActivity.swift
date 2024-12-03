
import UIKit

class ToolbarActivity: BaseActivity, Injectable {
    var mMenuButton: UIButton!
    var mSearchText: UILabel!
    var mSwitchAccountButton: UIButton!
    var mNotificationButton: UIButton!

    private var mAppBar: UIView!
    private var mDefaultToolbar: UIView!
    private var mToolbar: UIView!
    private var mHomeSearchToolbar: UIView!
    private var mPreviewImage: UIImageView!
    private var mPreviewImageContainer: UIView!
    private var mInfoBox: UIView!
    private var mInfoBoxMessage: UILabel!
    var mToolbarSpinner: UIView!
    private var isHomeSearchToolbarShow = false

    @Inject var themeColorUtils: ThemeColorUtils!
    @Inject var themeUtils: ThemeUtils!
    @Inject var viewThemeUtils: ViewThemeUtils!

    private func setupToolbar(isHomeSearchToolbarShow: Bool, showSortListButtonGroup: Bool) {
        mToolbar = findViewById(R.id.toolbar)
        setSupportActionBar(mToolbar)

        mAppBar = findViewById(R.id.appbar)
        mDefaultToolbar = findViewById(R.id.default_toolbar)
        mHomeSearchToolbar = findViewById(R.id.home_toolbar)
        mMenuButton = findViewById(R.id.menu_button)
        mSearchText = findViewById(R.id.search_text)
        mSwitchAccountButton = findViewById(R.id.switch_account_button)
        mNotificationButton = findViewById(R.id.notification_button)

        if showSortListButtonGroup {
            findViewById(R.id.sort_list_button_group).visibility = .visible
        }

        self.isHomeSearchToolbarShow = isHomeSearchToolbarShow
        updateActionBarTitleAndHomeButton(nil)

        mInfoBox = findViewById(R.id.info_box)
        mInfoBoxMessage = findViewById(R.id.info_box_message)

        mPreviewImage = findViewById(R.id.preview_image)
        mPreviewImageContainer = findViewById(R.id.preview_image_frame)

        mToolbarSpinner = findViewById(R.id.toolbar_spinner)

        viewThemeUtils.material.themeToolbar(mToolbar)
        viewThemeUtils.material.colorToolbarOverflowIcon(mToolbar)
        viewThemeUtils.platform.themeStatusBar(self)
        viewThemeUtils.material.colorMaterialTextButton(mSwitchAccountButton)
    }

    func setupToolbarShowOnlyMenuButtonAndTitle(title: String, toggleDrawer: @escaping () -> Void) {
        setupToolbar(isHomeSearchToolbarShow: false, showSortListButtonGroup: false)

        if let actionBar = self.navigationController?.navigationBar {
            actionBar.topItem?.title = nil
        }

        if let toolbar = self.view.viewWithTag(R.id.toolbar_linear_layout) as? UIView,
           let menuButton = self.view.viewWithTag(R.id.toolbar_menu_button) as? UIButton,
           let titleTextView = self.view.viewWithTag(R.id.toolbar_title) as? UILabel {
            
            titleTextView.text = title
            titleTextView.textColor = UIColor(named: "foreground_highlight")
            menuButton.tintColor = UIColor(named: "foreground_highlight")
            
            toolbar.isHidden = false
            menuButton.addAction(UIAction(handler: { _ in toggleDrawer() }), for: .touchUpInside)
        }
    }

    func setupToolbar() {
        setupToolbar(isHomeSearchToolbarShow: false, showSortListButtonGroup: false)
    }

    func setupHomeSearchToolbarWithSortAndListButtons() {
        setupToolbar(isHomeSearchToolbarShow: true, showSortListButtonGroup: true)
    }

    func updateActionBarTitleAndHomeButton(chosenFile: OCFile?) {
        let title: String
        let isRoot = isRoot(file: chosenFile)

        title = isRoot ? themeUtils.getDefaultDisplayNameForRootFolder(self) : fileDataStorageManager.getFilenameConsideringOfflineOperation(chosenFile: chosenFile)
        updateActionBarTitleAndHomeButtonByString(title: title)

        if mAppBar != nil {
            showHomeSearchToolbar(title: title, isRoot: isRoot)
        }
    }

    func showSearchView() {
        if isHomeSearchToolbarShow {
            showHomeSearchToolbar(isShow: false)
        }
    }

    func hideSearchView(chosenFile: OCFile?) {
        if isHomeSearchToolbarShow {
            showHomeSearchToolbar(isShow: isRoot(file: chosenFile))
        }
    }

    private func showHomeSearchToolbar(title: String, isRoot: Bool) {
        showHomeSearchToolbar(isShow: isHomeSearchToolbarShow && isRoot)
        mSearchText.text = String(format: NSLocalizedString("appbar_search_in", comment: ""), title)
    }

    private func showHomeSearchToolbar(isShow: Bool) {
        viewThemeUtils.material.themeToolbar(mToolbar)
        if isShow {
            viewThemeUtils.platform.resetStatusBar(self)
            mAppBar.layer.shadowOpacity = 0
            mDefaultToolbar.isHidden = true
            mHomeSearchToolbar.isHidden = false
            viewThemeUtils.material.themeCardView(mHomeSearchToolbar)
            viewThemeUtils.material.themeSearchBarText(mSearchText)
        } else {
            mAppBar.layer.shadowOpacity = 1
            viewThemeUtils.platform.themeStatusBar(self)
            mDefaultToolbar.isHidden = false
            mHomeSearchToolbar.isHidden = true
        }
    }

    func updateActionBarTitleAndHomeButtonByString(title: String?) {
        if let actionBar = self.navigationController?.navigationBar {
            if let title = title {
                actionBar.topItem?.title = title
                actionBar.isTranslucent = false
            } else {
                actionBar.isTranslucent = true
            }
        }
    }

    func isRoot(file: OCFile?) -> Bool {
        return file == nil || (file!.isFolder() && file!.getParentId() == FileDataStorageManager.ROOT_PARENT_ID)
    }

    func showInfoBox(text: Int) {
        if let infoBox = mInfoBox, let infoBoxMessage = mInfoBoxMessage {
            infoBox.isHidden = false
            infoBoxMessage.text = String(text)
        }
    }

    func hideInfoBox() {
        if let infoBox = mInfoBox {
            infoBox.isHidden = true
        }
    }

    func setPreviewImageVisibility(isVisibility: Bool) {
        if let previewImage = mPreviewImage, let previewImageContainer = mPreviewImageContainer {
            if isVisibility {
                mToolbar.title = nil
                mToolbar.backgroundColor = UIColor.clear
            } else {
                mToolbar.setBackgroundImage(UIImage(named: "appbar"), for: .default)
            }
            previewImageContainer.isHidden = !isVisibility
        }
    }

    func hidePreviewImage() {
        setPreviewImageVisibility(isVisibility: false)
    }

    func showSortListGroup(show: Bool) {
        let visibility = show ? UIView.Visibility.visible : UIView.Visibility.gone
        view.viewWithTag(R.id.sort_list_button_group)?.visibility = visibility
    }

    func sortListGroupVisibility() -> Bool {
        return findViewById(R.id.sort_list_button_group).visibility == .visible
    }

    func setPreviewImageBitmap(_ bitmap: UIImage?) {
        if let previewImage = mPreviewImage {
            previewImage.image = bitmap
            setPreviewImageVisibility(isVisibility: true)
        }
    }

    func setPreviewImageDrawable(_ drawable: UIImage?) {
        if mPreviewImage != nil {
            mPreviewImage.image = drawable
            setPreviewImageVisibility(isVisibility: true)
        }
    }

    func getPreviewImageView() -> UIImageView {
        return mPreviewImage
    }

    func getPreviewImageContainer() -> UIView {
        return mPreviewImageContainer
    }

    func updateToolbarSubtitle(subtitle: String) {
        if let actionBar = self.navigationController?.navigationBar {
            actionBar.topItem?.subtitle = subtitle
            viewThemeUtils.androidx.themeActionBarSubtitle(self, actionBar)
        }
    }

    func clearToolbarSubtitle() {
        if let actionBar = self.navigationController?.navigationBar {
            actionBar.topItem?.subtitle = nil
        }
    }
}
