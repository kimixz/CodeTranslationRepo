
import UIKit

class ModifiedAuthenticatorActivity: AuthenticatorActivity, Injectable {

    override func viewDidLoad() {
        super.viewDidLoad()
        GooglePlayUtils.checkPlayServices(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        GooglePlayUtils.checkPlayServices(self)
    }
}
