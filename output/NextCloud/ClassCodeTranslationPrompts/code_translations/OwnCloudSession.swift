
class OwnCloudSession {
    private var sessionName: String
    private var sessionUrl: String
    private var entryId: Int

    init(sessionName: String, sessionUrl: String, entryId: Int) {
        self.sessionName = sessionName
        self.sessionUrl = sessionUrl
        self.entryId = entryId
    }

    func getSessionName() -> String {
        return self.sessionName
    }

    func getSessionUrl() -> String {
        return self.sessionUrl
    }

    func getEntryId() -> Int {
        return self.entryId
    }

    func setSessionName(_ sessionName: String) {
        self.sessionName = sessionName
    }

    func setSessionUrl(sessionUrl: String) {
        self.sessionUrl = sessionUrl
    }
}
