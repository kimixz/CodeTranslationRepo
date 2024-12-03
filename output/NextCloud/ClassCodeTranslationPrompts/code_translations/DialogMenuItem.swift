
import UIKit

class DialogMenuItem: NSObject, UIMenuItem {
    var mItemId: Int
    var mTitle: String?

    init(itemId: Int) {
        self.mItemId = itemId
    }

    func getItemId() -> Int {
        return mItemId
    }

    func getGroupId() -> Int {
        return 0
    }

    func getOrder() -> Int {
        return 0
    }

    @discardableResult
    func setTitle(_ title: String) -> Self {
        self.mTitle = title
        return self
    }

    func setTitle(_ title: Int) -> UIMenuItem {
        return self
    }

    func getTitle() -> String? {
        return self.mTitle
    }

    func setTitleCondensed(_ title: String?) -> UIMenuItem? {
        return nil
    }

    func getTitleCondensed() -> String? {
        return nil
    }

    func setIcon(icon: UIImage) -> UIMenuItem? {
        return nil
    }

    func setIcon(iconRes: Int) -> UIMenuItem? {
        return nil
    }

    func getIcon() -> UIImage? {
        return nil
    }

    func setIntent(intent: Any) -> UIMenuItem? {
        return nil
    }

    func getIntent() -> Any? {
        return nil
    }

    func setShortcut(numericChar: Character, alphaChar: Character) -> UIMenuItem? {
        return nil
    }

    func setNumericShortcut(_ numericChar: Character) -> UIMenuItem? {
        return nil
    }

    func getNumericShortcut() -> Character {
        return "\0"
    }

    func setAlphabeticShortcut(_ alphaChar: Character) -> UIMenuItem? {
        return nil
    }

    func getAlphabeticShortcut() -> Character {
        return "\0"
    }

    func setCheckable(_ checkable: Bool) -> UIMenuItem? {
        return nil
    }

    func isCheckable() -> Bool {
        return false
    }

    func setChecked(_ checked: Bool) -> UIMenuItem? {
        return nil
    }

    func isChecked() -> Bool {
        return false
    }

    func setVisible(_ visible: Bool) -> UIMenuItem? {
        return nil
    }

    func isVisible() -> Bool {
        return false
    }

    func setEnabled(_ enabled: Bool) -> UIMenuItem? {
        return nil
    }

    func isEnabled() -> Bool {
        return false
    }

    func hasSubMenu() -> Bool {
        return false
    }

    func getSubMenu() -> Any? {
        return nil
    }

    func setOnMenuItemClickListener(_ menuItemClickListener: Any) -> UIMenuItem? {
        return nil
    }

    var menuInfo: Any? {
        return nil
    }

    func setShowAsAction(_ actionEnum: Int) {
        // not used at the moment
    }

    func setShowAsActionFlags(_ actionEnum: Int) -> UIMenuItem? {
        return nil
    }

    func setActionView(_ view: UIView) -> UIMenuItem? {
        return nil
    }

    func setActionView(_ resId: Int) -> UIMenuItem? {
        return nil
    }

    func getActionView() -> UIView? {
        return nil
    }

    func setActionProvider(actionProvider: Any?) -> UIMenuItem? {
        return nil
    }

    func actionProvider() -> Any? {
        return nil
    }

    func expandActionView() -> Bool {
        return false
    }

    func collapseActionView() -> Bool {
        return false
    }

    func isActionViewExpanded() -> Bool {
        return false
    }

    func setOnActionExpandListener(listener: Any?) -> UIMenuItem? {
        return nil
    }
}
