
import UIKit

protocol OCFileListFragmentInterface {
    func getColumnsCount() -> Int

    func onShareIconClick(file: OCFile)

    func showShareDetailView(file: OCFile)

    func showActivityDetailView(file: OCFile)

    func onOverflowIconClicked(file: OCFile, view: UIView)

    func onItemClicked(file: OCFile)

    func onLongItemClicked(file: OCFile) -> Bool

    func isLoading() -> Bool

    func onHeaderClicked()
}
