
import Foundation

class RootCursor: MatrixCursor {
    
    private static let DEFAULT_ROOT_PROJECTION: [String] = [
        Root.COLUMN_ROOT_ID,
        Root.COLUMN_FLAGS,
        Root.COLUMN_ICON,
        Root.COLUMN_TITLE,
        Root.COLUMN_DOCUMENT_ID,
        Root.COLUMN_AVAILABLE_BYTES,
        Root.COLUMN_SUMMARY,
        Root.COLUMN_FLAGS
    ]
    
    init(projection: [String]? = nil) {
        super.init(projection: projection ?? RootCursor.DEFAULT_ROOT_PROJECTION)
    }
    
    func addRoot(document: DocumentsStorageProvider.Document, context: Context) {
        let user = document.getUser()
        
        let rootFlags = Root.FLAG_SUPPORTS_CREATE
                      | Root.FLAG_SUPPORTS_RECENTS
                      | Root.FLAG_SUPPORTS_SEARCH
                      | Root.FLAG_SUPPORTS_IS_CHILD
        
        newRow().add(Root.COLUMN_ROOT_ID, user.getAccountName())
            .add(Root.COLUMN_DOCUMENT_ID, document.getDocumentId())
            .add(Root.COLUMN_SUMMARY, user.getAccountName())
            .add(Root.COLUMN_TITLE, context.getString(R.string.app_name))
            .add(Root.COLUMN_ICON, R.mipmap.ic_launcher)
            .add(Root.COLUMN_FLAGS, rootFlags)
    }
}
