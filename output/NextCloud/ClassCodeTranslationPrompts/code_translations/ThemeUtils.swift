
import Foundation

class ThemeUtils {
    
    func themingEnabled(context: Context) -> Bool {
        let capability = CapabilityUtils.getCapability(context: context)
        return capability.getServerColor() != nil && !capability.getServerColor()!.isEmpty
    }
    
    func getDefaultDisplayNameForRootFolder(context: Context) -> String {
        let capability = CapabilityUtils.getCapability(context: context)
        
        if MainApp.isOnlyOnDevice() {
            return MainApp.string(R.string.drawer_item_on_device)
        } else {
            if capability.getServerName() == nil || capability.getServerName()!.isEmpty {
                return MainApp.getAppContext().resources.getString(R.string.default_display_name_for_root_folder)
            } else {
                return capability.getServerName()!
            }
        }
    }
}
