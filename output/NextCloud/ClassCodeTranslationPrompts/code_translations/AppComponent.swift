
import Foundation

protocol AppComponent {
    func inject(app: MainApp)
    func inject(mediaControlView: MediaControlView)
    @available(*, deprecated, message: "Unstable API")
    func inject(backgroundPlayerService: BackgroundPlayerService)
    func inject(switchPreference: ThemeableSwitchPreference)
    func inject(fileUploadHelper: FileUploadHelper)
    func inject(fileDownloadHelper: FileDownloadHelper)
    func inject(progressIndicator: ProgressIndicator)
    
    associatedtype Builder
    func application(_ application: Application) -> Builder
    func build() -> AppComponent
}
