
import Foundation
import UIKit

class PrintAdapter: UIPrintPageRenderer {
    private static let TAG = String(describing: PrintAdapter.self)
    private static let PDF_NAME = "finalPrint.pdf"
    
    private let filePath: String
    
    init(filePath: String) {
        self.filePath = filePath
    }
    
    override func drawPage(at pageIndex: Int, in printableRect: CGRect) {
        // Implement drawing logic if needed
    }
    
    func onLayout(oldAttributes: UIPrintPaper, newAttributes: UIPrintPaper, cancellationSignal: NSProgress, callback: @escaping (UIPrintFormatter, Bool) -> Void, extras: [AnyHashable: Any]?) {
        if cancellationSignal.isCancelled {
            callback(UIPrintFormatter(), false)
        } else {
            let printInfo = UIPrintInfo(dictionary: nil)
            printInfo.outputType = .general
            printInfo.jobName = PrintAdapter.PDF_NAME
            callback(UIPrintFormatter(), newAttributes != oldAttributes)
        }
    }
    
    func onWrite(pages: [UIPrintPageRenderer.PageRange], to destination: URL, with cancellationSignal: NSProgress, completionHandler: @escaping (UIPrintPageRenderer.PageRange) -> Void) {
        do {
            let inputStream = InputStream(fileAtPath: filePath)
            let outputStream = OutputStream(url: destination, append: false)
            
            inputStream?.open()
            outputStream?.open()
            
            var buffer = [UInt8](repeating: 0, count: 16384)
            var size: Int
            
            while inputStream?.hasBytesAvailable == true && !cancellationSignal.isCancelled {
                size = inputStream!.read(&buffer, maxLength: buffer.count)
                if size > 0 {
                    outputStream?.write(buffer, maxLength: size)
                }
            }
            
            if cancellationSignal.isCancelled {
                completionHandler(.cancelled)
            } else {
                completionHandler(.completed)
            }
            
            inputStream?.close()
            outputStream?.close()
            
        } catch {
            print("Error using temp file: \(error)")
        }
    }
}
