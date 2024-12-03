
import UIKit
import FeatureFragment

class FeaturesViewAdapter: NSObject, UICollectionViewDataSource {
    
    private let mFeatures: [FeatureItem]
    
    init(features: FeatureItem...) {
        self.mFeatures = features
    }
    
    func createFragment(at position: Int) -> Fragment {
        return FeatureFragment.newInstance(mFeatures[position])
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return mFeatures.count
    }
}
