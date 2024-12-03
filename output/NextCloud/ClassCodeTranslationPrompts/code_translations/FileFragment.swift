
import UIKit

class FileFragment: UIViewController {

    private var file: OCFile?

    weak var containerActivity: ContainerActivity?

    override func viewDidLoad() {
        super.viewDidLoad()

        if let bundle = self.arguments {
            if let file = bundle.getParcelableArgument(EXTRA_FILE, OCFile.self) {
                setFile(file)
            }
        }
    }

    static func newInstance(file: OCFile) -> FileFragment {
        let fileFragment = FileFragment()
        let bundle = Bundle()

        bundle.setValue(file, forKey: EXTRA_FILE)
        fileFragment.setArguments(bundle)

        return fileFragment
    }

    func getFile() -> OCFile? {
        return file
    }

    func setFile(_ file: OCFile) {
        self.file = file
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if let containerActivity = parent as? ContainerActivity {
            self.containerActivity = containerActivity
        } else {
            fatalError("\(String(describing: parent)) must implement \(String(describing: ContainerActivity.self))")
        }
    }

    override func willMove(toParent parent: UIViewController?) {
        if parent == nil {
            containerActivity = nil
        }
        super.willMove(toParent: parent)
    }

    protocol ContainerActivity: ComponentsGetter {
        func showDetails(file: OCFile)
        func showDetails(file: OCFile, activeTab: Int)
        func onBrowsedDownTo(folder: OCFile)
        func onTransferStateChanged(file: OCFile, downloading: Bool, uploading: Bool)
        func showSortListGroup(show: Bool)
    }
}
