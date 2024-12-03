
import UIKit
import SwiftUI

class FeaturesWebViewAdapter: UIPageViewControllerDataSource {
    private var mWebUrls: [String]

    init(fragmentActivity: UIViewController, webUrls: String...) {
        self.mWebUrls = webUrls
        super.init()
    }

    func createFragment(at position: Int) -> UIViewController {
        return FeatureWebFragment.newInstance(mWebUrls[position])
    }

    func getItemCount() -> Int {
        return mWebUrls.count
    }
}
