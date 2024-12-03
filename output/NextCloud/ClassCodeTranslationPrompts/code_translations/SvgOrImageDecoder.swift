
import Foundation
import UIKit

class SVGorImage {
    var svg: SVG?
    var image: UIImage?
    
    init(svg: SVG?, image: UIImage?) {
        self.svg = svg
        self.image = image
    }
}

class SimpleResource<T> {
    var resource: T
    
    init(_ resource: T) {
        self.resource = resource
    }
}

class SvgOrImageDecoder {
    private var height: Int = -1
    private var width: Int = -1
    
    init(height: Int, width: Int) {
        self.height = height
        self.width = width
    }
    
    init() {
        // empty constructor
    }
    
    func decode(source: InputStream, width: Int, height: Int) throws -> SimpleResource<SVGorImage> {
        let availableBytes = source.hasBytesAvailable ? source.availableBytes : 0
        var array = [UInt8](repeating: 0, count: availableBytes)
        source.read(&array, maxLength: availableBytes)
        
        let svgInputStream = InputStream(data: Data(array))
        let pngInputStream = InputStream(data: Data(array))
        
        do {
            let svg = try SVG.getFromInputStream(svgInputStream)
            source.close()
            pngInputStream.close()
            
            if width > 0 {
                svg.setDocumentWidth(width)
            }
            if height > 0 {
                svg.setDocumentHeight(height)
            }
            svg.setDocumentPreserveAspectRatio(.letterbox)
            
            return SimpleResource(SVGorImage(svg: svg, image: nil))
        } catch {
            let bitmap = UIImage(data: Data(array))
            return SimpleResource(SVGorImage(svg: nil, image: bitmap))
        }
    }
    
    func getId() -> String {
        return "SvgDecoder.com.owncloud.android"
    }
}
