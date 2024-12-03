
import UIKit
import ImageIO
import CommonCrypto

final class BitmapUtils {
    static let TAG = String(describing: BitmapUtils.self)

    private init() {
        // utility class -> private constructor
    }

    static func addColorFilter(originalImage: UIImage, filterColor: UIColor, opacity: CGFloat) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(originalImage.size, false, originalImage.scale)
        guard let context = UIGraphicsGetCurrentContext(), let cgImage = originalImage.cgImage else {
            return nil
        }
        
        let rect = CGRect(origin: .zero, size: originalImage.size)
        context.draw(cgImage, in: rect)
        
        context.setFillColor(filterColor.withAlphaComponent(opacity).cgColor)
        context.setBlendMode(.sourceAtop)
        context.fill(rect)
        
        let resultImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resultImage
    }

    static func decodeSampledBitmapFromFile(srcPath: String, reqWidth: Int, reqHeight: Int) -> UIImage? {
        if #available(iOS 13.0, *) {
            do {
                let fileURL = URL(fileURLWithPath: srcPath)
                let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil)
                let options: [CFString: Any] = [
                    kCGImageSourceThumbnailMaxPixelSize: max(reqWidth, reqHeight),
                    kCGImageSourceCreateThumbnailFromImageAlways: true
                ]
                if let source = source, let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    return UIImage(cgImage: cgImage)
                }
            } catch {
                print("Error decoding the bitmap from file: \(srcPath), exception: \(error.localizedDescription)")
            }
        }
        
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        
        guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: srcPath) as CFURL, options) else {
            return nil
        }
        
        let propertiesOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, propertiesOptions) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        
        let inSampleSize = calculateSampleFactor(pixelWidth: pixelWidth, pixelHeight: pixelHeight, reqWidth: reqWidth, reqHeight: reqHeight)
        
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: max(reqWidth, reqHeight) / inSampleSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true
        ]
        
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions as CFDictionary) {
            return UIImage(cgImage: cgImage)
        }
        
        return nil
    }

    static func calculateSampleFactor(pixelWidth: Int, pixelHeight: Int, reqWidth: Int, reqHeight: Int) -> Int {
        var inSampleSize = 1
        if pixelHeight > reqHeight || pixelWidth > reqWidth {
            let halfHeight = pixelHeight / 2
            let halfWidth = pixelWidth / 2
            
            while (halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }

    static func scaleBitmap(bitmap: UIImage, px: CGFloat, width: Int, height: Int, max: Int) -> UIImage? {
        let scale = px / CGFloat(max)
        let w = Int(round(scale * CGFloat(width)))
        let h = Int(round(scale * CGFloat(height)))
        let size = CGSize(width: w, height: h)
        
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        bitmap.draw(in: CGRect(origin: .zero, size: size))
        let scaledBitmap = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return scaledBitmap
    }

    static func rotateImage(_ image: UIImage, storagePath: String) -> UIImage? {
        guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: storagePath) as CFURL, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let exifOrientation = imageProperties[kCGImagePropertyOrientation] as? Int else {
            return image
        }
        
        var transform = CGAffineTransform.identity
        
        switch exifOrientation {
        case 2:
            transform = transform.scaledBy(x: -1.0, y: 1.0)
        case 3:
            transform = transform.rotated(by: .pi)
        case 4:
            transform = transform.scaledBy(x: 1.0, y: -1.0)
        case 5:
            transform = transform.rotated(by: -.pi / 2).scaledBy(x: 1.0, y: -1.0)
        case 6:
            transform = transform.rotated(by: .pi / 2)
        case 7:
            transform = transform.rotated(by: .pi / 2).scaledBy(x: 1.0, y: -1.0)
        case 8:
            transform = transform.rotated(by: -.pi / 2)
        default:
            return image
        }
        
        guard let cgImage = image.cgImage else { return image }
        let context = CGContext(data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: cgImage.bitsPerComponent, bytesPerRow: 0, space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: cgImage.bitmapInfo.rawValue)
        
        context?.concatenate(transform)
        
        switch exifOrientation {
        case 5, 6, 7, 8:
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.height, height: cgImage.width))
        default:
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        
        guard let newCGImage = context?.makeImage() else { return image }
        return UIImage(cgImage: newCGImage)
    }

    static func getImageResolution(srcPath: String) -> [Int] {
        let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: srcPath) as CFURL, nil)
        let options: [NSString: Any] = [kCGImageSourceShouldCache: false]
        if let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource!, 0, options as CFDictionary) as? [CFString: Any],
           let width = imageProperties[kCGImagePropertyPixelWidth] as? Int,
           let height = imageProperties[kCGImagePropertyPixelHeight] as? Int {
            return [width, height]
        }
        return [0, 0]
    }

    static func usernameToColor(_ name: String) -> UIColor {
        var hash = name.lowercased()

        if hash.count != 32 || !hash.range(of: "^[0-9a-f]+$", options: .regularExpression) {
            do {
                hash = try md5(hash)
            } catch {
                let color = UIColor(named: "primary_dark") ?? UIColor.black
                return color
            }
        }

        hash = hash.replacingOccurrences(of: "[^0-9a-f]", with: "", options: .regularExpression)
        let steps = 6

        let finalPalette = generateColors(steps)

        return finalPalette[hashToInt(hash, steps * 3)]
    }

    private static func hashToInt(hash: String, maximum: Int) -> Int {
        var finalInt = 0

        for char in hash {
            if let digit = Int(String(char), radix: 16) {
                finalInt += digit
            }
        }

        return finalInt % maximum
    }

    private static func generateColors(steps: Int) -> [UIColor] {
        let red = UIColor(red: 182/255.0, green: 70/255.0, blue: 157/255.0, alpha: 1.0)
        let yellow = UIColor(red: 221/255.0, green: 203/255.0, blue: 85/255.0, alpha: 1.0)
        let blue = UIColor(red: 0/255.0, green: 130/255.0, blue: 201/255.0, alpha: 1.0)

        let palette1 = mixPalette(steps: steps, color1: red, color2: yellow)
        let palette2 = mixPalette(steps: steps, color1: yellow, color2: blue)
        let palette3 = mixPalette(steps: steps, color1: blue, color2: red)

        var resultPalette = [UIColor]()
        resultPalette.append(contentsOf: palette1)
        resultPalette.append(contentsOf: palette2)
        resultPalette.append(contentsOf: palette3)

        return resultPalette
    }

    private static func mixPalette(steps: Int, color1: UIColor, color2: UIColor) -> [UIColor] {
        var palette = [UIColor](repeating: color1, count: steps)
        palette[0] = color1

        let step = stepCalc(steps: steps, color1: color1, color2: color2)
        for i in 1..<steps {
            let r = Int(color1.r + step[0] * CGFloat(i))
            let g = Int(color1.g + step[1] * CGFloat(i))
            let b = Int(color1.b + step[2] * CGFloat(i))

            palette[i] = UIColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)
        }

        return palette
    }

    private static func stepCalc(steps: Int, color1: UIColor, color2: UIColor) -> [CGFloat] {
        var step = [CGFloat](repeating: 0.0, count: 3)
        
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        color1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        color2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        
        step[0] = (r2 - r1) / CGFloat(steps)
        step[1] = (g2 - g1) / CGFloat(steps)
        step[2] = (b2 - b1) / CGFloat(steps)
        
        return step
    }

    static func md5(_ string: String) throws -> String {
        guard let data = string.data(using: .utf8) else {
            throw NSError(domain: "Invalid string encoding", code: 0, userInfo: nil)
        }
        
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &hash)
        }
        
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func bitmapToCircularBitmapDrawable(bitmap: UIImage?, radius: CGFloat) -> UIImage? {
        guard let bitmap = bitmap else {
            return nil
        }

        let size = bitmap.size
        let rect = CGRect(origin: .zero, size: size)

        UIGraphicsBeginImageContextWithOptions(size, false, bitmap.scale)
        let context = UIGraphicsGetCurrentContext()

        if radius != -1 {
            let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
            path.addClip()
        } else {
            context?.addEllipse(in: rect)
            context?.clip()
        }

        bitmap.draw(in: rect)
        let roundedBitmap = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return roundedBitmap
    }

    static func bitmapToCircularBitmapDrawable(resources: Resources, bitmap: UIImage?) -> UIImage? {
        return bitmapToCircularBitmapDrawable(bitmap: bitmap, radius: -1)
    }

    static func setRoundedBitmap(resources: Resources, bitmap: UIImage, radius: CGFloat, imageView: UIImageView) {
        imageView.image = BitmapUtils.bitmapToCircularBitmapDrawable(bitmap: bitmap, radius: radius)
    }

    static func drawableToBitmap(drawable: Drawable) -> UIImage {
        return drawableToBitmap(drawable: drawable, desiredWidth: -1, desiredHeight: -1)
    }

    static func drawableToBitmap(drawable: Drawable, desiredWidth: Int, desiredHeight: Int) -> UIImage {
        if let bitmapDrawable = drawable as? BitmapDrawable, let bitmap = bitmapDrawable.bitmap {
            return bitmap
        }

        var width: Int
        var height: Int

        if desiredWidth > 0 && desiredHeight > 0 {
            width = desiredWidth
            height = desiredHeight
        } else {
            if drawable.intrinsicWidth <= 0 || drawable.intrinsicHeight <= 0 {
                if drawable.bounds.width > 0 && drawable.bounds.height > 0 {
                    width = Int(drawable.bounds.width)
                    height = Int(drawable.bounds.height)
                } else {
                    width = 1
                    height = 1
                }
            } else {
                width = drawable.intrinsicWidth
                height = drawable.intrinsicHeight
            }
        }

        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), false, 0.0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return UIImage()
        }
        drawable.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }

    static func setRoundedBitmap(thumbnail: UIImage, imageView: UIImageView) {
        BitmapUtils.setRoundedBitmap(
            resources: getResources(),
            bitmap: thumbnail,
            radius: getResources().getDimension(R.dimen.file_icon_rounded_corner_radius),
            imageView: imageView
        )
    }

    static func setRoundedBitmapForGridMode(thumbnail: UIImage, imageView: UIImageView) {
        BitmapUtils.setRoundedBitmap(
            resources: getResources(),
            bitmap: thumbnail,
            radius: getResources().getDimension(R.dimen.file_icon_rounded_corner_radius_for_grid_mode),
            imageView: imageView
        )
    }

    static func createAvatarWithStatus(avatar: UIImage, statusType: StatusType, icon: String, context: UIViewController) -> UIImage? {
        let avatarRadius = context.view.bounds.width / 2
        let width = Int(2 * avatarRadius)

        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: width), false, 0.0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        let croppedBitmap = getCroppedBitmap(bitmap: avatar, width: width)
        croppedBitmap?.draw(in: CGRect(x: 0, y: 0, width: width, height: width))

        let statusSize = width / 4

        let status = Status(type: statusType, text: "", icon: icon, id: -1)
        let statusDrawable = StatusDrawable(status: status, size: statusSize, context: context)

        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(width) / 2)
        statusDrawable.draw(in: context)

        let output = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return output
    }

    static func roundBitmap(_ bitmap: UIImage) -> UIImage? {
        let size = bitmap.size
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        let rect = CGRect(origin: .zero, size: size)
        let rectF = CGRect(origin: .zero, size: size)
        
        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)
        
        context.addEllipse(in: rectF)
        context.clip()
        
        bitmap.draw(in: rect)
        
        let output = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return output
    }

    static func tintImage(bitmap: UIImage, color: UIColor) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(bitmap.size, false, bitmap.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.translateBy(x: 0, y: bitmap.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.setBlendMode(.normal)
        
        let rect = CGRect(x: 0, y: 0, width: bitmap.size.width, height: bitmap.size.height)
        context.clip(to: rect, mask: bitmap.cgImage!)
        color.setFill()
        context.fill(rect)
        
        let tintedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return tintedImage
    }

    private static func getCroppedBitmap(bitmap: UIImage, width: Int) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: width), false, 0.0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        let color = UIColor(red: 0.2627, green: 0.2627, blue: 0.2627, alpha: 1.0)
        let rect = CGRect(x: 0, y: 0, width: width, height: width)
        
        context.setFillColor(UIColor.clear.cgColor)
        context.fill(rect)
        
        context.setFillColor(color.cgColor)
        context.setBlendMode(.copy)
        
        context.addEllipse(in: rect)
        context.clip()
        
        let scaledBitmap = bitmap.resized(to: CGSize(width: width, height: width))
        scaledBitmap.draw(in: rect)
        
        let output = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return output
    }

    private static func getResources() -> Resources {
        return MainApp.getAppContext().resources
    }
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        self.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage ?? self
    }
}
