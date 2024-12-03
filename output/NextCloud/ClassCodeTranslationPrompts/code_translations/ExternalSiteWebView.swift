
import UIKit
import WebKit

class ExternalSiteWebView: UIViewController {
    static let EXTRA_TITLE = "TITLE"
    static let EXTRA_URL = "URL"
    static let EXTRA_SHOW_SIDEBAR = "SHOW_SIDEBAR"
    static let EXTRA_SHOW_TOOLBAR = "SHOW_TOOLBAR"
    static let EXTRA_TEMPLATE = "TEMPLATE"

    private static let TAG = String(describing: ExternalSiteWebView.self)

    var showToolbar = true
    private var binding: ExternalsiteWebviewBinding!
    private var showSidebar = false
    var url: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        Log_OC.v(Self.TAG, "onCreate() start")
        bindView()
        showToolbar = showToolbarByDefault()

        if let extras = self.navigationController?.viewControllers.last?.extras {
            url = extras[Self.EXTRA_URL] as? String
            if extras.keys.contains(Self.EXTRA_SHOW_TOOLBAR) {
                showToolbar = extras[Self.EXTRA_SHOW_TOOLBAR] as? Bool ?? showToolbar
            }
            showSidebar = extras[Self.EXTRA_SHOW_SIDEBAR] as? Bool ?? false
        }

        if let window = self.view.window {
            window.makeKeyAndVisible()
        }

        setContentView(getRootView())

        postOnCreate()
    }

    func postOnCreate() {
        let webSettings = getWebView().configuration.preferences

        getWebView().isUserInteractionEnabled = true
        getWebView().isMultipleTouchEnabled = true
        getWebView().isOpaque = false

        if (UIApplication.shared.applicationState == .active || Bundle.main.object(forInfoDictionaryKey: "is_beta") as? Bool == true) {
            print("Enable debug for webView")
            WKWebViewConfiguration().preferences.setValue(true, forKey: "developerExtrasEnabled")
        }

        if showToolbar {
            setupToolbar()
        } else {
            if let appbar = view.viewWithTag(R.id.appbar) {
                appbar.isHidden = true
            }
        }

        setupDrawer()

        if !showSidebar {
            setDrawerLockMode(.lockedClosed)
        }

        if let title = getIntent().extras?[Self.EXTRA_TITLE] as? String, !title.isEmpty {
            setupActionBar(title)
        }
        setupWebSettings(webSettings)

        if let progressBar = view.viewWithTag(R.id.progressBar) as? UIProgressView {
            getWebView().navigationDelegate = WebViewNavigationDelegate(progressBar: progressBar)
        }

        let selfReference = self
        getWebView().navigationDelegate = NextcloudWebViewClient(getSupportFragmentManager: getSupportFragmentManager()) { view, request, error in
            if let resources = Bundle.main.url(forResource: "custom_error", withExtension: "html") {
                if let customError = try? String(contentsOf: resources), !customError.isEmpty {
                    self.getWebView().loadHTMLString(customError, baseURL: nil)
                }
            }
        }

        WebViewUtil(applicationContext: UIApplication.shared).setProxyKKPlus(getWebView())
        getWebView().load(URLRequest(url: URL(string: url!)!))
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        getWebView().removeFromSuperview()
    }

    private func bindView() {
        binding = ExternalsiteWebviewBinding.inflate(layoutInflater)
    }

    func showToolbarByDefault() -> Bool {
        return true
    }

    func getRootView() -> UIView {
        return binding.root
    }

    private func setupWebSettings(_ webSettings: WKPreferences) {
        let webView = getWebView()

        webView.scrollView.isZoomingEnabled = true
        webView.scrollView.bouncesZoom = true

        webView.configuration.ignoresViewportScaleLimits = true

        webView.customUserAgent = MainApp.getUserAgent()

        webSettings.isFormDataEnabled = false

        webView.configuration.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")

        webSettings.javaScriptEnabled = true
        webView.configuration.preferences.setValue(true, forKey: "domStorageEnabled")

        #if DEBUG
        webView.configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        #endif
    }

    private func setupActionBar(_ title: String) {
        if let actionBar = self.navigationController?.navigationBar {
            viewThemeUtils.files.themeActionBar(self, actionBar, title)

            if showSidebar {
                self.navigationItem.setHidesBackButton(false, animated: true)
            } else {
                setDrawerIndicatorEnabled(false)
            }
        }
    }

    override func onOptionsItemSelected(_ item: MenuItem) -> Bool {
        if item.itemId == android.R.id.home {
            if showSidebar {
                if isDrawerOpen() {
                    closeDrawer()
                } else {
                    openDrawer()
                }
            } else {
                finish()
            }
            return true
        } else {
            return super.onOptionsItemSelected(item)
        }
    }

    func getWebView() -> WKWebView {
        return binding.webView
    }
}
