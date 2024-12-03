
import UIKit

class StickyHeaderItemDecoration: UICollectionViewFlowLayout {
    private let adapter: StickyHeaderAdapter

    init(stickyHeaderAdapter: StickyHeaderAdapter) {
        self.adapter = stickyHeaderAdapter
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ canvas: CGContext, for parent: UICollectionView, with state: UICollectionViewLayoutAttributes) {
        super.draw(canvas, for: parent, with: state)

        guard let topChild = parent.cellForItem(at: IndexPath(item: 0, section: 0)) else {
            return
        }
        let topChildPosition = parent.indexPath(for: topChild)?.item ?? NSNotFound

        if topChildPosition == NSNotFound {
            return
        }
        let currentHeader = getHeaderViewForItem(itemPosition: topChildPosition, parent: parent)
        fixLayoutSize(parent: parent, view: currentHeader)
        let contactPoint = currentHeader.frame.maxY
        guard let childInContact = getChildInContact(parent: parent, contactPoint: Int(contactPoint)) else {
            return
        }

        if adapter.isHeader(itemPosition: parent.indexPath(for: childInContact)?.item ?? NSNotFound) {
            moveHeader(canvas: canvas, currentHeader: currentHeader, nextHeader: childInContact)
            return
        }

        drawHeader(canvas: canvas, header: currentHeader)
    }

    private func drawHeader(canvas: CGContext, header: UIView) {
        canvas.saveGState()
        canvas.translateBy(x: 0, y: 0)
        header.layer.render(in: canvas)
        canvas.restoreGState()
    }

    private func moveHeader(canvas: CGContext, currentHeader: UIView, nextHeader: UIView) {
        canvas.saveGState()
        canvas.translateBy(x: 0, y: nextHeader.frame.origin.y - currentHeader.frame.height)
        currentHeader.layer.render(in: canvas)
        canvas.restoreGState()
    }

    private func getChildInContact(parent: UICollectionView, contactPoint: Int) -> UIView? {
        var childInContact: UIView? = nil
        for i in 0..<parent.numberOfItems(inSection: 0) {
            if let currentChild = parent.cellForItem(at: IndexPath(item: i, section: 0)) {
                if currentChild.frame.maxY > CGFloat(contactPoint) && currentChild.frame.minY <= CGFloat(contactPoint) {
                    childInContact = currentChild
                    break
                }
            }
        }
        return childInContact
    }

    private func getHeaderViewForItem(itemPosition: Int, parent: UICollectionView) -> UIView {
        let headerPosition = adapter.getHeaderPositionForItem(itemPosition: itemPosition)
        let layoutId = adapter.getHeaderLayout(itemPosition: itemPosition)
        let header = UINib(nibName: layoutId, bundle: nil).instantiate(withOwner: nil, options: nil).first as! UIView
        adapter.bindHeaderData(header: header, headerPosition: headerPosition)
        return header
    }

    private func fixLayoutSize(parent: UIView, view: UIView) {
        let widthSpec = parent.bounds.width
        let heightSpec = UIView.layoutFittingCompressedSize.height

        let childWidthSpec = view.systemLayoutSizeFitting(CGSize(width: widthSpec, height: 0)).width
        let childHeightSpec = view.systemLayoutSizeFitting(CGSize(width: 0, height: heightSpec)).height

        view.frame = CGRect(x: 0, y: 0, width: childWidthSpec, height: childHeightSpec)
    }
}
