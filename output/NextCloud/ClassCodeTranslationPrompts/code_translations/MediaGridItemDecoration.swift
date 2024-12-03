
import UIKit

class MediaGridItemDecoration: NSObject, UICollectionViewDelegateFlowLayout {
    private var space: CGFloat

    init(space: CGFloat) {
        self.space = space
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: space, left: space, bottom: space, right: space)
    }
}
