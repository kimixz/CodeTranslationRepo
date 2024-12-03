
import UIKit

class EmptyRecyclerView: UICollectionView {
    private var mEmptyView: UIView?
    private var hasFooter = false

    override func setAdapter(_ adapter: Adapter?) {
        let oldAdapter = getAdapter()
        super.setAdapter(adapter)
        if let oldAdapter = oldAdapter {
            oldAdapter.unregisterAdapterDataObserver(observer)
        }
        if let adapter = adapter {
            adapter.registerAdapterDataObserver(observer)
        }
    }

    func setEmptyView(_ view: UIView) {
        self.mEmptyView = view
        initEmptyView()
    }

    private func initEmptyView() {
        if let emptyView = mEmptyView {
            let emptyCount = hasFooter ? 1 : 0
            let empty = getAdapter()?.itemCount == emptyCount
            emptyView.isHidden = !empty
            emptyView.isUserInteractionEnabled = false
            self.isHidden = empty
        }
    }

    private let observer = AdapterDataObserver() {
        override func onChanged() {
            super.onChanged()
            initEmptyView()
        }

        override func onItemRangeChanged(_ positionStart: Int, _ itemCount: Int) {
            super.onItemRangeChanged(positionStart, itemCount)
            initEmptyView()
        }

        override func onItemRangeChanged(_ positionStart: Int, _ itemCount: Int, _ payload: Any?) {
            super.onItemRangeChanged(positionStart, itemCount, payload)
            initEmptyView()
        }

        override func onItemRangeMoved(fromPosition: Int, toPosition: Int, itemCount: Int) {
            super.onItemRangeMoved(fromPosition: fromPosition, toPosition: toPosition, itemCount: itemCount)
            initEmptyView()
        }

        override func onItemRangeInserted(_ positionStart: Int, _ itemCount: Int) {
            super.onItemRangeInserted(positionStart, itemCount)
            initEmptyView()
        }

        override func onItemRangeRemoved(_ positionStart: Int, _ itemCount: Int) {
            super.onItemRangeRemoved(positionStart, itemCount)
            initEmptyView()
        }
    }

    func setHasFooter(_ bool: Bool) {
        hasFooter = bool
    }
}
