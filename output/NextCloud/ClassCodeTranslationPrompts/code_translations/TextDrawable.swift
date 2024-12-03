
import UIKit

class TextDrawable: Drawable {
    private var text: String
    private var textPaint: Paint
    private var background: Paint
    private var radius: CGFloat
    private var bigText = false

    init(text: String, color: BitmapUtils.Color, radius: CGFloat) {
        self.radius = radius
        self.text = text

        background = Paint()
        background.style = .fill
        background.isAntiAlias = true
        background.color = UIColor(red: CGFloat(color.r) / 255.0, green: CGFloat(color.g) / 255.0, blue: CGFloat(color.b) / 255.0, alpha: CGFloat(color.a) / 255.0)

        textPaint = Paint()
        textPaint.color = .white
        textPaint.textSize = radius
        textPaint.isAntiAlias = true
        textPaint.textAlign = .center

        setBounds(CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2))
    }

    static func createAvatar(user: User, radiusInDp: CGFloat) -> TextDrawable {
        let username = UserAccountManager.getDisplayName(user: user)
        return createNamedAvatar(name: username, radiusInDp: radiusInDp)
    }

    static func createAvatarByUserId(userId: String, radiusInDp: CGFloat) -> TextDrawable {
        return createNamedAvatar(name: userId, radiusInDp: radiusInDp)
    }

    static func createNamedAvatar(name: String, radiusInDp: CGFloat) -> TextDrawable {
        let color = BitmapUtils.usernameToColor(name: name)
        return TextDrawable(text: extractCharsFromDisplayName(name), color: color, radius: radiusInDp)
    }

    static func extractCharsFromDisplayName(_ displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return ""
        }
        let nameParts = trimmed.split(separator: " ")

        var firstTwoLetters = ""
        for i in 0..<min(2, nameParts.count) {
            if let firstChar = nameParts[i].first {
                firstTwoLetters.append(firstChar.uppercased())
            }
        }

        return firstTwoLetters
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let radius = rect.width / 2
        context.setFillColor(background.cgColor)
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))

        if bigText {
            textPaint.font = UIFont.systemFont(ofSize: 1.8 * radius)
        }

        let textSize = text.size(withAttributes: [NSAttributedString.Key.font: textPaint])
        let textRect = CGRect(x: radius - textSize.width / 2, y: radius - textSize.height / 2, width: textSize.width, height: textSize.height)
        text.draw(in: textRect, withAttributes: [NSAttributedString.Key.font: textPaint, NSAttributedString.Key.foregroundColor: textPaint.color])
    }

    override func setAlpha(_ alpha: Int) {
        textPaint.alpha = alpha
    }

    override func setColorFilter(_ cf: ColorFilter?) {
        textPaint.colorFilter = cf
    }

    override func getOpacity() -> Int {
        return PixelFormat.translucent
    }
}
