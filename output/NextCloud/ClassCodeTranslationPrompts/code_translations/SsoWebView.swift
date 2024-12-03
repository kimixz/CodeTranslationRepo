
import UIKit
import WebKit

class SsoWebView: WKWebView {
    
    override var isTextInput: Bool {
        return false
    }
    
    init(context: UIView) {
        super.init(frame: context.frame, configuration: WKWebViewConfiguration())
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
