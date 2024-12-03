
import Foundation

class EncryptedFolderMetadataFileV1 {
    private var metadata: DecryptedMetadata
    private var files: [String: EncryptedFile]
    private var filedrop: [String: EncryptedFiledrop]

    init(metadata: DecryptedMetadata, files: [String: EncryptedFile], filedrop: [String: EncryptedFiledrop]) {
        self.metadata = metadata
        self.files = files
        self.filedrop = filedrop
    }

    func getMetadata() -> DecryptedMetadata {
        return self.metadata
    }

    func getFiles() -> [String: EncryptedFile] {
        return files
    }

    func getFiledrop() -> [String: EncryptedFiledrop] {
        return filedrop
    }

    func setMetadata(_ metadata: DecryptedMetadata) {
        self.metadata = metadata
    }

    func setFiles(_ files: [String: EncryptedFile]) {
        self.files = files
    }

    class EncryptedFile {
        private var encrypted: String
        private var initializationVector: String
        private var authenticationTag: String
        private var metadataKey: Int

        init(encrypted: String, initializationVector: String, authenticationTag: String, metadataKey: Int) {
            self.encrypted = encrypted
            self.initializationVector = initializationVector
            self.authenticationTag = authenticationTag
            self.metadataKey = metadataKey
        }

        func getEncrypted() -> String {
            return encrypted
        }

        func getInitializationVector() -> String {
            return initializationVector
        }

        func getAuthenticationTag() -> String {
            return authenticationTag
        }

        func getMetadataKey() -> Int {
            return metadataKey
        }

        func setEncrypted(_ encrypted: String) {
            self.encrypted = encrypted
        }

        func setInitializationVector(_ initializationVector: String) {
            self.initializationVector = initializationVector
        }

        func setAuthenticationTag(_ authenticationTag: String) {
            self.authenticationTag = authenticationTag
        }
    }
}
