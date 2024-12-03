
import UIKit

class FileDetailSharingFragmentHelper {
    private init() {
        // Private empty constructor
    }

    static func setupSearchView(searchManager: UISearchController?, searchView: UISearchBar, componentName: String) {
        guard let searchManager = searchManager else {
            searchView.isHidden = true
            return
        }

        // assumes parent activity is the searchable activity
        // Note: In Swift, you would typically set up the search controller with a search results updater
        // searchView.searchableInfo = searchManager.getSearchableInfo(componentName)

        // do not iconify the widget; expand it by default
        searchView.showsCancelButton = false

        // avoid fullscreen with softkeyboard
        searchView.inputAccessoryView = nil

        searchView.delegate = SearchViewDelegate()
    }

    static func isPublicShareDisabled(capabilities: OCCapability?) -> Bool {
        return capabilities != nil && capabilities!.getFilesSharingPublicEnabled().isFalse()
    }
}

class SearchViewDelegate: NSObject, UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        // return true to prevent the query from being processed;
        searchBar.resignFirstResponder()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) -> Bool {
        // leave it for the parent listener in the hierarchy / default behaviour
        return false
    }
}
