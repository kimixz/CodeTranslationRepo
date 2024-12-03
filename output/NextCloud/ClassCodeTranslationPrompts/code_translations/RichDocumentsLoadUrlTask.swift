
import Foundation

class RichDocumentsLoadUrlTask: Operation {
    private let user: User
    private weak var editorWebViewWeakReference: EditorWebView?
    private let file: OCFile

    init(editorWebView: EditorWebView, user: User, file: OCFile) {
        self.user = user
        self.editorWebViewWeakReference = editorWebView
        self.file = file
    }

    override func main() {
        let url = doInBackground(nil)
        onPostExecute(url: url)
    }

    func doInBackground(_ voids: [Void]?) -> String {
        guard let editorWebView = editorWebViewWeakReference else {
            return ""
        }

        let result = RichDocumentsUrlOperation(file.localId).execute(user: user, editorWebView: editorWebView)

        if !result.isSuccess() {
            return ""
        }

        return result.getData()[0] as! String
    }

    func onPostExecute(url: String?) {
        guard let editorWebView = editorWebViewWeakReference else {
            return
        }
        
        editorWebView.onUrlLoaded(url)
    }
}
