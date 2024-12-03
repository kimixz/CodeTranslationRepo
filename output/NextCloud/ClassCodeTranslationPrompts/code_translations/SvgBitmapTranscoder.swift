
import UIKit

class SvgBitmapTranscoder {
    private var width: Int
    private var height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    func transcode(toTranscode: Resource<SVG>) -> Resource<UIImage> {
        let svg = toTranscode.get()

        do {
            try svg.setDocumentHeight("100%")
            try svg.setDocumentWidth("100%")
        } catch {
            print("Could not set document size. Output might have wrong size")
        }

        // Create a canvas to draw onto
        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), false, 0.0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return SimpleResource(UIImage())
        }

        // Render our document onto our canvas
        svg.renderToContext(context)

        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()

        return SimpleResource(image)
    }

    func getId() -> String {
        return ""
    }
}
