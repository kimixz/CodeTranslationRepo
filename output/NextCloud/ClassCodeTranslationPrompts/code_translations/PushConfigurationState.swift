
class PushConfigurationState {
    var pushToken: String
    var deviceIdentifier: String
    var deviceIdentifierSignature: String
    var userPublicKey: String
    var shouldBeDeleted: Bool

    init(pushToken: String, deviceIdentifier: String, deviceIdentifierSignature: String, userPublicKey: String, shouldBeDeleted: Bool) {
        self.pushToken = pushToken
        self.deviceIdentifier = deviceIdentifier
        self.deviceIdentifierSignature = deviceIdentifierSignature
        self.userPublicKey = userPublicKey
        self.shouldBeDeleted = shouldBeDeleted
    }

    init() {
        self.pushToken = ""
        self.deviceIdentifier = ""
        self.deviceIdentifierSignature = ""
        self.userPublicKey = ""
        self.shouldBeDeleted = false
    }

    func getPushToken() -> String {
        return self.pushToken
    }

    func getDeviceIdentifier() -> String {
        return self.deviceIdentifier
    }

    func getDeviceIdentifierSignature() -> String {
        return self.deviceIdentifierSignature
    }

    func getUserPublicKey() -> String {
        return self.userPublicKey
    }

    func isShouldBeDeleted() -> Bool {
        return self.shouldBeDeleted
    }

    func setPushToken(_ pushToken: String) {
        self.pushToken = pushToken
    }

    func setDeviceIdentifier(_ deviceIdentifier: String) {
        self.deviceIdentifier = deviceIdentifier
    }

    func setDeviceIdentifierSignature(_ deviceIdentifierSignature: String) {
        self.deviceIdentifierSignature = deviceIdentifierSignature
    }

    func setUserPublicKey(_ userPublicKey: String) {
        self.userPublicKey = userPublicKey
    }

    func setShouldBeDeleted(_ shouldBeDeleted: Bool) {
        self.shouldBeDeleted = shouldBeDeleted
    }
}
