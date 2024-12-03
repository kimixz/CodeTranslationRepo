
import Foundation

class FileCursor: MatrixCursor {
    static let DEFAULT_DOCUMENT_PROJECTION = [
        Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME,
        Document.COLUMN_MIME_TYPE, Document.COLUMN_SIZE,
        Document.COLUMN_FLAGS, Document.COLUMN_LAST_MODIFIED
    ]

    private var extra: Bundle?
    private var loadingTask: AnyObject?

    init(projection: [String]? = nil) {
        super.init(projection: projection ?? FileCursor.DEFAULT_DOCUMENT_PROJECTION)
    }

    func setLoadingTask(task: AnyObject) {
        self.loadingTask = task
    }

    override func setExtras(_ extras: Bundle) {
        self.extra = extras
    }

    override func getExtras() -> Bundle {
        return extra ?? Bundle()
    }

    override func close() {
        super.close()
        if let task = loadingTask, task.status != .finished {
            task.cancel()
        }
    }

    func addFile(document: DocumentsStorageProvider.Document?) {
        guard let document = document else {
            return
        }

        let file = document.getFile()

        let iconRes = MimeTypeUtil.getFileTypeIconId(mimeType: file.getMimeType(), fileName: file.getFileName())
        let mimeType = file.isFolder() ? Document.MIME_TYPE_DIR : file.getMimeType()
        var flags = Document.FLAG_SUPPORTS_DELETE |
            Document.FLAG_SUPPORTS_WRITE |
            (MimeTypeUtil.isImage(file) ? Document.FLAG_SUPPORTS_THUMBNAIL : 0) |
            Document.FLAG_SUPPORTS_COPY | Document.FLAG_SUPPORTS_MOVE | Document.FLAG_SUPPORTS_REMOVE

        if file.isFolder() {
            flags = flags | Document.FLAG_DIR_SUPPORTS_CREATE
        }

        flags = Document.FLAG_SUPPORTS_RENAME | flags

        newRow().add(Document.COLUMN_DOCUMENT_ID, document.getDocumentId())
                .add(Document.COLUMN_DISPLAY_NAME, file.getFileName())
                .add(Document.COLUMN_LAST_MODIFIED, file.getModificationTimestamp())
                .add(Document.COLUMN_SIZE, file.getFileLength())
                .add(Document.COLUMN_FLAGS, flags)
                .add(Document.COLUMN_ICON, iconRes)
                .add(Document.COLUMN_MIME_TYPE, mimeType)
    }
}
