
import Foundation

class PreferencesModule {

    func sharedPreferences(context: Context) -> UserDefaults {
        return UserDefaults.standard
    }

    func appPreferences(context: Context, sharedPreferences: UserDefaults, userAccountManager: UserAccountManager) -> AppPreferences {
        return AppPreferencesImpl(context: context, sharedPreferences: sharedPreferences, userAccountManager: userAccountManager)
    }
}
