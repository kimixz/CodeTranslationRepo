
import Foundation
import UIKit

class PrintAsyncTask: Operation {
    private static let TAG = String(describing: PrintAsyncTask.self)
    private static let JOB_NAME = "Document"
    
    private var file: File
    private var url: String
    private var richDocumentsWebViewWeakReference: WeakReference<RichDocumentsEditorWebView>
    
    init(file: File, url: String, richDocumentsWebViewWeakReference: WeakReference<RichDocumentsEditorWebView>) {
        self.file = file
        self.url = url
        self.richDocumentsWebViewWeakReference = richDocumentsWebViewWeakReference
    }
    
    override func main() {
        onPreExecute()
        let result = doInBackground()
        onPostExecute(result)
    }
    
    func onPreExecute() {
        DispatchQueue.main.async {
            self.richDocumentsWebViewWeakReference.get()?.showLoadingDialog(
                self.richDocumentsWebViewWeakReference.get()?.getString(R.string.common_loading) ?? "")
        }
    }
    
    func doInBackground() -> Bool {
        let client = HttpClient()
        var getMethod: GetMethod? = nil
        var fos: FileOutputStream? = nil
        
        do {
            getMethod = GetMethod(url: url)
            let status = try client.executeMethod(getMethod!)
            if status == HttpStatus.SC_OK {
                if file.exists() && !file.delete() {
                    return false
                }
                
                file.getParentFile().mkdirs()
                
                if !file.getParentFile().exists() {
                    Log_OC.d(PrintAsyncTask.TAG, "\(file.getParentFile().getAbsolutePath()) does not exist")
                    return false
                }
                
                if !file.createNewFile() {
                    Log_OC.d(PrintAsyncTask.TAG, "\(file.getAbsolutePath()) could not be created")
                    return false
                }
                
                let bis = BufferedInputStream(inputStream: getMethod!.getResponseBodyAsStream())
                fos = FileOutputStream(file: file)
                var transferred: Int64 = 0
                
                let contentLength = getMethod!.getResponseHeader("Content-Length")
                let totalToTransfer: Int64 = contentLength != nil && !contentLength!.getValue().isEmpty ?
                    Int64(contentLength!.getValue()) ?? 0 : 0
                
                var bytes = [UInt8](repeating: 0, count: 4096)
                var readResult: Int
                while (readResult = bis.read(&bytes)) != -1 {
                    fos!.write(bytes, 0, readResult)
                    transferred += Int64(readResult)
                }
                // Check if the file is completed
                if transferred != totalToTransfer {
                    return false
                }
                
                if getMethod!.getResponseBodyAsStream() != nil {
                    getMethod!.getResponseBodyAsStream().close()
                }
            }
        } catch {
            Log_OC.e(PrintAsyncTask.TAG, "Error reading file", error)
        } finally {
            if getMethod != nil {
                getMethod!.releaseConnection()
            }
            if fos != nil {
                do {
                    try fos!.close()
                } catch {
                    Log_OC.e(PrintAsyncTask.TAG, "Error closing file output stream", error)
                }
            }
        }
        
        return true
    }
    
    func onPostExecute(_ result: Bool) {
        guard let richDocumentsWebView = richDocumentsWebViewWeakReference.get() else { return }
        richDocumentsWebView.dismissLoadingDialog()
        
        guard let printManager = richDocumentsWebView.getSystemService(PRINT_SERVICE) as? PrintManager else {
            DisplayUtils.showSnackMessage(richDocumentsWebView, richDocumentsWebView.getString(R.string.failed_to_print))
            return
        }
        
        let printAdapter = PrintAdapter(file.absolutePath)
        printManager.print(PrintAsyncTask.JOB_NAME, adapter: printAdapter, attributes: PrintAttributes.Builder().build())
    }
}
