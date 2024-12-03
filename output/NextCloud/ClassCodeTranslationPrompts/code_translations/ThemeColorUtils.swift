
import UIKit

@available(*, deprecated, message: "use material 3 Schemes and utilities from common lib instead")
class ThemeColorUtils {
    func unchangedPrimaryColor(account: Account, context: Context) -> UIColor {
        do {
            return UIColor(hexString: getCapability(account: account, context: context).getServerColor())
        } catch {
            return UIColor(named: "primary") ?? UIColor.black
        }
    }

    func unchangedFontColor(context: Context) -> UIColor {
        do {
            return UIColor(hexString: getCapability(context: context).getServerTextColor())
        } catch {
            if PlatformThemeUtil.isDarkMode(context: context) {
                return UIColor.white
            } else {
                return UIColor.black
            }
        }
    }
}
