
import Foundation
import CommonCrypto

final class EncryptionUtils {
    private static let TAG = "EncryptionUtils"
    
    public static let PUBLIC_KEY = "PUBLIC_KEY"
    public static let PRIVATE_KEY = "PRIVATE_KEY"
    public static let MNEMONIC = "MNEMONIC"
    public static let ivLength = 16
    public static let saltLength = 40
    public static let ivDelimiter = "|"
    public static let ivDelimiterOld = "fA=="
    
    private static let HASH_DELIMITER: Character = "$"
    private static let iterationCount = 1024
    private static let keyStrength = 256
    private static let AES_CIPHER = "AES/GCM/NoPadding"
    private static let AES = "AES"
    public static let RSA_CIPHER = "RSA/ECB/OAEPWithSHA-256AndMGF1Padding"
    public static let RSA = "RSA"
    public static let MIGRATED_FOLDER_IDS = "MIGRATED_FOLDER_IDS"
    
    private init() {
        // utility class -> private constructor
    }
    
    static func deserializeJSON<T: Decodable>(_ json: String, type: T.Type, excludeTransient: Bool) -> T? {
        let decoder = JSONDecoder()
        if !excludeTransient {
            // Handle transient fields if needed
        }
        guard let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }
    
    static func deserializeJSON<T>(_ json: String, type: TypeToken<T>) -> T {
        return deserializeJSON(json, type: type, excludeTransient: false)
    }
    
    static func serializeJSON(_ data: Any, excludeTransient: Bool) -> String {
        let jsonEncoder = JSONEncoder()
        if excludeTransient {
            // Assuming excludeTransient means not including certain fields, 
            // but Swift's JSONEncoder doesn't have a direct equivalent to exclude fields by modifier.
            // Custom logic would be needed here if specific fields need to be excluded.
        } else {
            // No direct equivalent for excluding fields with modifiers in Swift's JSONEncoder.
            // Custom logic would be needed here if specific fields need to be excluded.
        }
        
        do {
            let jsonData = try jsonEncoder.encode(data as! Encodable)
            return String(data: jsonData, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
    
    static func removeFileFromMetadata(fileName: String, metadata: DecryptedFolderMetadataFileV1) {
        metadata.files.removeValue(forKey: fileName)
    }
    
    static func serializeJSON(_ data: Any) -> String {
        return serializeJSON(data, excludeTransient: false)
    }
    
    static func encryptFolderMetadata(
        decryptedFolderMetadata: DecryptedFolderMetadataFileV1,
        publicKey: String,
        parentId: Int64,
        user: User,
        arbitraryDataProvider: ArbitraryDataProvider
    ) throws -> EncryptedFolderMetadataFileV1 {
        
        var files = [String: EncryptedFolderMetadataFileV1.EncryptedFile]()
        var filesdrop = [String: EncryptedFiledrop]()
        var encryptedFolderMetadata = EncryptedFolderMetadataFileV1(metadata: decryptedFolderMetadata.metadata, files: files, filesdrop: filesdrop)
        
        let metadataKeyBytes = EncryptionUtils.generateKey()
        let encryptedMetadataKey = EncryptionUtils.encryptStringAsymmetric(
            EncryptionUtils.encodeBytesToBase64String(metadataKeyBytes),
            publicKey)
        encryptedFolderMetadata.metadata.metadataKey = encryptedMetadataKey
        
        addIdToMigratedIds(parentId, user, arbitraryDataProvider)
        
        for (key, decryptedFile) in decryptedFolderMetadata.files {
            var encryptedFile = EncryptedFolderMetadataFileV1.EncryptedFile(
                initializationVector: decryptedFile.initializationVector,
                authenticationTag: decryptedFile.authenticationTag,
                encrypted: ""
            )
            
            let dataJson = EncryptionUtils.serializeJSON(decryptedFile.encrypted)
            encryptedFile.encrypted = EncryptionUtils.encryptStringSymmetricAsString(dataJson, metadataKeyBytes)
            
            files[key] = encryptedFile
        }
        
        let mnemonic = arbitraryDataProvider.getValue(user.accountName, EncryptionUtils.MNEMONIC).trimmingCharacters(in: .whitespaces)
        let checksum = EncryptionUtils.generateChecksum(decryptedFolderMetadata, mnemonic)
        encryptedFolderMetadata.metadata.checksum = checksum
        
        return encryptedFolderMetadata
    }
    
    static func encryptFileDropFiles(decryptedFolderMetadata: DecryptedFolderMetadataFileV1, encryptedFolderMetadata: EncryptedFolderMetadataFileV1, cert: String) throws {
        let filesdrop = encryptedFolderMetadata.getFiledrop()
        for (key, decryptedFile) in decryptedFolderMetadata.getFiledrop() {
            let byt = generateKey()
            let metadataKey0 = encodeBytesToBase64String(byt)
            let enc = try encryptStringAsymmetric(metadataKey0, cert: cert)
            
            let dataJson = EncryptionUtils.serializeJSON(decryptedFile.getEncrypted())
            
            let encJson = try encryptStringSymmetricAsString(dataJson, key: byt)
            
            let delimiterPosition = encJson.lastIndex(of: ivDelimiter) ?? encJson.endIndex
            let encryptedInitializationVector = String(encJson[encJson.index(after: delimiterPosition)...])
            let encodedCryptedBytes = String(encJson[..<delimiterPosition])
            
            let bytes = decodeStringToBase64Bytes(encodedCryptedBytes)
            
            let extractedAuthenticationTag = bytes.suffix(128 / 8)
            
            let encryptedTag = encodeBytesToBase64String(Array(extractedAuthenticationTag))
            
            let encryptedFile = EncryptedFiledrop(
                encodedCryptedBytes: encodedCryptedBytes,
                initializationVector: decryptedFile.getInitializationVector(),
                authenticationTag: decryptedFile.getAuthenticationTag(),
                enc: enc,
                encryptedTag: encryptedTag,
                encryptedInitializationVector: encryptedInitializationVector
            )
            
            filesdrop[key] = encryptedFile
        }
    }
    
    static func decryptFolderMetaData(encryptedFolderMetadata: EncryptedFolderMetadataFileV1, privateKey: String, arbitraryDataProvider: ArbitraryDataProvider, user: User, remoteId: Int64) throws -> DecryptedFolderMetadataFileV1 {
        var files = [String: DecryptedFile]()
        let decryptedFolderMetadata = DecryptedFolderMetadataFileV1(metadata: encryptedFolderMetadata.metadata, files: files)
        
        var decryptedMetadataKey: Data? = nil
        
        let encryptedMetadataKey = decryptedFolderMetadata.metadata.metadataKey
        
        if let encryptedMetadataKey = encryptedMetadataKey {
            decryptedMetadataKey = try decodeStringToBase64Bytes(decryptStringAsymmetric(encryptedMetadataKey, privateKey: privateKey))
        }
        
        if let encryptedFiles = encryptedFolderMetadata.files {
            for (key, encryptedFile) in encryptedFiles {
                var decryptedFile = DecryptedFile()
                decryptedFile.initializationVector = encryptedFile.initializationVector
                decryptedFile.metadataKey = encryptedFile.metadataKey
                decryptedFile.authenticationTag = encryptedFile.authenticationTag
                
                if decryptedMetadataKey == nil {
                    decryptedMetadataKey = try decodeStringToBase64Bytes(decryptStringAsymmetric(decryptedFolderMetadata.metadata.metadataKeys[encryptedFile.metadataKey]!, privateKey: privateKey))
                }
                
                let dataJson = try decryptStringSymmetric(encryptedFile.encrypted, key: decryptedMetadataKey!)
                decryptedFile.encrypted = try deserializeJSON(dataJson)
                
                files[key] = decryptedFile
            }
        }
        
        let mnemonic = arbitraryDataProvider.getValue(user.accountName, key: EncryptionUtils.MNEMONIC).trimmingCharacters(in: .whitespacesAndNewlines)
        let checksum = try generateChecksum(decryptedFolderMetadata, mnemonic: mnemonic)
        let decryptedFolderChecksum = decryptedFolderMetadata.metadata.checksum
        
        if decryptedFolderChecksum.isEmpty && isFolderMigrated(remoteId: remoteId, user: user, arbitraryDataProvider: arbitraryDataProvider) {
            reportE2eError(arbitraryDataProvider: arbitraryDataProvider, user: user)
            throw NSError(domain: "IllegalStateException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Possible downgrade attack detected!"])
        }
        
        if !decryptedFolderChecksum.isEmpty && decryptedFolderChecksum != checksum {
            reportE2eError(arbitraryDataProvider: arbitraryDataProvider, user: user)
            throw NSError(domain: "IllegalStateException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Wrong checksum!"])
        }
        
        if let fileDrop = encryptedFolderMetadata.filedrop {
            for (key, encryptedFile) in fileDrop {
                let encryptedKey = try decryptStringAsymmetric(encryptedFile.encryptedKey, privateKey: privateKey)
                
                let decryptedData = try decryptStringSymmetricAsString(encryptedFile.encrypted, key: decodeStringToBase64Bytes(encryptedKey), iv: decodeStringToBase64Bytes(encryptedFile.encryptedInitializationVector), tag: decodeStringToBase64Bytes(encryptedFile.encryptedTag), arbitraryDataProvider: arbitraryDataProvider, user: user)
                
                var decryptedFile = DecryptedFile()
                decryptedFile.initializationVector = encryptedFile.initializationVector
                decryptedFile.authenticationTag = encryptedFile.authenticationTag
                
                decryptedFile.encrypted = try deserializeJSON(decryptedData)
                
                files[key] = decryptedFile
                
                fileDrop.removeValue(forKey: key)
            }
        }
        
        return decryptedFolderMetadata
    }
    
    static func downloadFolderMetadata(folder: OCFile, client: OwnCloudClient, context: Context, user: User) -> Any? {
        let getMetadataOperationResult = GetMetadataRemoteOperation(localId: folder.getLocalId()).execute(client: client)
        
        guard getMetadataOperationResult.isSuccess else {
            return nil
        }
        
        let capability = CapabilityUtils.getCapability(context: context)
        
        let encryptionUtilsV2 = EncryptionUtilsV2()
        let serializedEncryptedMetadata = getMetadataOperationResult.getResultData().getMetadata()
        
        let version = determinateVersion(serializedEncryptedMetadata: serializedEncryptedMetadata)
        
        switch version {
        case .unknown:
            Log_OC.e(TAG, "Unknown e2e state")
            return nil
            
        case .v1_0, .v1_1, .v1_2:
            let arbitraryDataProvider = ArbitraryDataProviderImpl(context: context)
            let privateKey = arbitraryDataProvider.getValue(accountName: user.getAccountName(), key: EncryptionUtils.PRIVATE_KEY)
            let publicKey = arbitraryDataProvider.getValue(accountName: user.getAccountName(), key: EncryptionUtils.PUBLIC_KEY)
            let encryptedFolderMetadata: EncryptedFolderMetadataFileV1 = EncryptionUtils.deserializeJSON(serializedEncryptedMetadata)
            
            do {
                let v1 = try decryptFolderMetaData(encryptedFolderMetadata: encryptedFolderMetadata,
                                                   privateKey: privateKey,
                                                   arbitraryDataProvider: arbitraryDataProvider,
                                                   user: user,
                                                   localId: folder.getLocalId())
                
                if capability.getEndToEndEncryptionApiVersion().compareTo(E2EVersion.v2_0) >= 0 {
                    try encryptionUtilsV2.migrateV1ToV2andUpload(v1: v1,
                                                                 userId: client.getUserId(),
                                                                 publicKey: publicKey,
                                                                 folder: folder,
                                                                 fileDataStorageManager: FileDataStorageManager(user: user, contentResolver: context.getContentResolver()),
                                                                 client: client,
                                                                 user: user,
                                                                 context: context)
                } else {
                    return v1
                }
            } catch {
                Log_OC.e(TAG, "Could not decrypt metadata for \(folder.getDecryptedFileName())", error)
                return nil
            }
            
        case .v2_0:
            return encryptionUtilsV2.parseAnyMetadata(resultData: getMetadataOperationResult.getResultData(),
                                                      user: user,
                                                      client: client,
                                                      context: context,
                                                      folder: folder)
        }
        return nil
    }
    
    static func determinateVersion(metadata: String) -> E2EVersion {
        do {
            let v1: EncryptedFolderMetadataFileV1 = try EncryptionUtils.deserializeJSON(metadata)
            let version = v1.metadata.version
            
            switch version {
            case 1.0:
                return .V1_0
            case 1.1:
                return .V1_1
            case 1.2:
                return .V1_2
            default:
                fatalError("Unknown version")
            }
        } catch {
            let v2: EncryptedFolderMetadataFile? = try? EncryptionUtils.deserializeJSON(metadata)
            
            if let v2 = v2 {
                if v2.version == "2.0" || v2.version == "2" {
                    return .V2_0
                }
            } else {
                return .UNKNOWN
            }
        }
        
        return .UNKNOWN
    }
    
    static func encodeStringToBase64Bytes(_ string: String) -> [UInt8] {
        if let data = string.data(using: .utf8) {
            return Array(data.base64EncodedData(options: .endLineWithLineFeed))
        } else {
            return []
        }
    }
    
    static func decodeBase64BytesToString(_ bytes: [UInt8]) -> String {
        do {
            if let decodedData = Data(base64Encoded: Data(bytes), options: .ignoreUnknownCharacters) {
                return String(data: decodedData, encoding: .utf8) ?? ""
            }
        } catch {
            return ""
        }
        return ""
    }
    
    static func encodeBytesToBase64String(_ bytes: [UInt8]) -> String {
        return Data(bytes).base64EncodedString(options: [])
    }
    
    static func encodeStringToBase64String(_ string: String) -> String {
        let data = string.data(using: .utf8)!
        return data.base64EncodedString(options: [])
    }
    
    static func decodeBase64StringToString(_ string: String) -> String? {
        if let data = Data(base64Encoded: string, options: .ignoreUnknownCharacters) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    static func decodeStringToBase64Bytes(_ string: String) -> [UInt8]? {
        return Data(base64Encoded: string, options: .ignoreUnknownCharacters)?.map { $0 }
    }
    
    static func encryptFile(accountName: String, file: URL, cipher: CCCryptorRef) throws -> EncryptedFile {
        let tempEncryptedFolder = try FileDataStorageManager.createTempEncryptedFolder(accountName: accountName)
        let tempEncryptedFile = tempEncryptedFolder.appendingPathComponent(file.lastPathComponent)
        try encryptFileWithGivenCipher(inputFile: file, outputFile: tempEncryptedFile, cipher: cipher)
        let authenticationTagString = try getAuthenticationTag(cipher: cipher)
        return EncryptedFile(file: tempEncryptedFile, authenticationTag: authenticationTagString)
    }
    
    static func getAuthenticationTag(cipher: CCCryptorRef) throws -> String {
        var ivSize = 0
        var iv = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        CCCryptorGetParameter(cipher, kCCParameterIV, &iv, kCCBlockSizeAES128, &ivSize)
        let authenticationTag = Data(iv.prefix(ivSize))
        return authenticationTag.base64EncodedString()
    }
    
    static func getCipher(mode: CCOperation, encryptionKeyBytes: [UInt8], iv: [UInt8]) throws -> CCCryptorRef? {
        guard encryptionKeyBytes.count == kCCKeySizeAES256 else {
            throw EncryptionError.invalidKey
        }
        guard iv.count == kCCBlockSizeAES128 else {
            throw EncryptionError.invalidInitializationVector
        }
        
        var cryptor: CCCryptorRef? = nil
        let status = CCCryptorCreateWithMode(
            mode,
            CCMode(kCCModeGCM),
            CCAlgorithm(kCCAlgorithmAES),
            CCPadding(ccNoPadding),
            iv,
            encryptionKeyBytes,
            encryptionKeyBytes.count,
            nil,
            0,
            0,
            CCModeOptions(kCCModeOptionCTR_BE),
            &cryptor
        )
        
        guard status == kCCSuccess else {
            return nil
        }
        
        return cryptor
    }
    
    static func encryptFileWithGivenCipher(inputFile: URL, encryptedFile: URL, cipher: CCCryptorRef) {
        do {
            let inputStream = InputStream(url: inputFile)!
            let outputStream = OutputStream(url: encryptedFile, append: false)!
            
            inputStream.open()
            outputStream.open()
            
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            
            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(&buffer, maxLength: bufferSize)
                if bytesRead > 0 {
                    var outputBuffer = [UInt8](repeating: 0, count: bufferSize)
                    var numBytesEncrypted: size_t = 0
                    
                    let cryptStatus = CCCryptorUpdate(cipher, buffer, bytesRead, &outputBuffer, bufferSize, &numBytesEncrypted)
                    
                    if cryptStatus == kCCSuccess {
                        outputStream.write(outputBuffer, maxLength: numBytesEncrypted)
                    } else {
                        print("Error during encryption: \(cryptStatus)")
                        break
                    }
                }
            }
            
            CCCryptorFinal(cipher, nil, 0, nil, 0, nil)
            
            inputStream.close()
            outputStream.close()
            
            print("\(encryptedFile.lastPathComponent) encrypted successfully")
        } catch {
            print("Error caught at encryptFileWithGivenCipher(): \(error.localizedDescription)")
        }
    }
    
    static func decryptFile(cipher: CCCryptorRef, encryptedFile: URL, decryptedFile: URL, authenticationTag: String, arbitraryDataProvider: ArbitraryDataProvider, user: User) {
        do {
            let inputStream = InputStream(url: encryptedFile)!
            let outputStream = OutputStream(url: decryptedFile, append: false)!
            
            inputStream.open()
            outputStream.open()
            
            var buffer = [UInt8](repeating: 0, count: 4096)
            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)
                if bytesRead > 0 {
                    var output = [UInt8](repeating: 0, count: buffer.count)
                    var outputLength: size_t = 0
                    let status = CCCryptorUpdate(cipher, buffer, bytesRead, &output, output.count, &outputLength)
                    if status == kCCSuccess {
                        outputStream.write(output, maxLength: outputLength)
                    }
                }
            }
            
            var finalOutput = [UInt8](repeating: 0, count: 4096)
            var finalOutputLength: size_t = 0
            let finalStatus = CCCryptorFinal(cipher, &finalOutput, finalOutput.count, &finalOutputLength)
            if finalStatus == kCCSuccess {
                outputStream.write(finalOutput, maxLength: finalOutputLength)
            }
            
            inputStream.close()
            outputStream.close()
            
            if getAuthenticationTag(cipher: cipher) != authenticationTag {
                reportE2eError(arbitraryDataProvider: arbitraryDataProvider, user: user)
                throw NSError(domain: "SecurityException", code: 0, userInfo: [NSLocalizedDescriptionKey: "Tag not correct"])
            }
            
            print("\(encryptedFile.lastPathComponent) decrypted successfully")
        } catch {
            print("Error caught at decryptFile(): \(error.localizedDescription)")
        }
    }
    
    static func encryptStringAsymmetric(_ string: String, _ cert: String) throws -> String {
        let rsaCipher = SecKeyAlgorithm.rsaEncryptionPKCS1
        
        let trimmedCert = cert.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----\n", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----\n", with: "")
        guard let encodedCert = trimmedCert.data(using: .utf8) else {
            throw NSError(domain: "Invalid certificate encoding", code: -1, userInfo: nil)
        }
        guard let decodedCert = Data(base64Encoded: encodedCert) else {
            throw NSError(domain: "Invalid certificate base64 decoding", code: -1, userInfo: nil)
        }
        
        let certOptions: [String: Any] = [kSecImportExportPassphrase as String: ""]
        var items: CFArray?
        let status = SecPKCS12Import(decodedCert as CFData, certOptions as CFDictionary, &items)
        guard status == errSecSuccess, let array = items as? [[String: Any]], let dict = array.first,
              let identity = dict[kSecImportItemIdentity as String] as? SecIdentity else {
            throw NSError(domain: "Certificate import failed", code: -1, userInfo: nil)
        }
        
        var publicKey: SecKey?
        let statusKey = SecIdentityCopyPublicKey(identity, &publicKey)
        guard statusKey == errSecSuccess, let realPublicKey = publicKey else {
            throw NSError(domain: "Public key extraction failed", code: -1, userInfo: nil)
        }
        
        guard SecKeyIsAlgorithmSupported(realPublicKey, .encrypt, rsaCipher) else {
            throw NSError(domain: "Algorithm not supported", code: -1, userInfo: nil)
        }
        
        guard let bytes = string.data(using: .utf8) else {
            throw NSError(domain: "String encoding failed", code: -1, userInfo: nil)
        }
        
        var error: Unmanaged<CFError>?
        guard let cryptedData = SecKeyCreateEncryptedData(realPublicKey, rsaCipher, bytes as CFData, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        
        return (cryptedData as Data).base64EncodedString()
    }
    
    static func encryptStringAsymmetricV2(bytes: [UInt8], cert: String) throws -> String {
        let rsaCipher = SecKeyAlgorithm.rsaEncryptionPKCS1
        
        let trimmedCert = cert.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----\n", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----\n", with: "")
        guard let encodedCert = trimmedCert.data(using: .utf8) else {
            throw NSError(domain: "Invalid certificate encoding", code: -1, userInfo: nil)
        }
        guard let decodedCert = Data(base64Encoded: encodedCert) else {
            throw NSError(domain: "Invalid certificate base64 decoding", code: -1, userInfo: nil)
        }
        
        let certOptions: [String: Any] = [kSecImportExportPassphrase as String: ""]
        var items: CFArray?
        let status = SecPKCS12Import(decodedCert as CFData, certOptions as CFDictionary, &items)
        guard status == errSecSuccess, let itemArray = items as? [[String: Any]], let firstItem = itemArray.first,
              let identity = firstItem[kSecImportItemIdentity as String] as? SecIdentity else {
            throw NSError(domain: "Certificate import failed", code: -1, userInfo: nil)
        }
        
        var publicKey: SecKey?
        let statusKey = SecIdentityCopyPublicKey(identity, &publicKey)
        guard statusKey == errSecSuccess, let realPublicKey = publicKey else {
            throw NSError(domain: "Public key extraction failed", code: -1, userInfo: nil)
        }
        
        guard SecKeyIsAlgorithmSupported(realPublicKey, .encrypt, rsaCipher) else {
            throw NSError(domain: "Algorithm not supported", code: -1, userInfo: nil)
        }
        
        var error: Unmanaged<CFError>?
        guard let cryptedData = SecKeyCreateEncryptedData(realPublicKey, rsaCipher, Data(bytes).asCFData(), &error) else {
            throw error!.takeRetainedValue() as Error
        }
        
        return cryptedData.base64EncodedString()
    }
    
    static func encryptStringAsymmetric(_ string: String, publicKey: SecKey) throws -> String {
        let algorithm: SecKeyAlgorithm = .rsaEncryptionPKCS1
        
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: errSecUnsupportedAlgorithm, userInfo: nil)
        }
        
        guard let data = string.data(using: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFormattingError, userInfo: nil)
        }
        
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(publicKey, algorithm, data as CFData, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        
        return (encryptedData as Data).base64EncodedString()
    }
    
    static func decryptStringAsymmetric(_ string: String, privateKeyString: String) throws -> String {
        guard let privateKeyData = Data(base64Encoded: privateKeyString) else {
            throw NSError(domain: "Invalid private key string", code: -1, userInfo: nil)
        }
        
        let keyDict: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(privateKeyData as CFData, keyDict as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        
        guard let dataToDecrypt = Data(base64Encoded: string) else {
            throw NSError(domain: "Invalid string to decrypt", code: -1, userInfo: nil)
        }
        
        var decryptError: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(privateKey, .rsaEncryptionPKCS1, dataToDecrypt as CFData, &decryptError) else {
            throw decryptError!.takeRetainedValue() as Error
        }
        
        guard let decryptedString = String(data: decryptedData as Data, encoding: .utf8) else {
            throw NSError(domain: "Decryption failed", code: -1, userInfo: nil)
        }
        
        return decryptedString
    }
    
    static func decryptStringAsymmetricAsBytes(string: String, privateKeyString: String) throws -> [UInt8] {
        guard let privateKeyData = Data(base64Encoded: privateKeyString) else {
            throw NSError(domain: "Invalid private key string", code: -1, userInfo: nil)
        }
        
        let keyDict: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(privateKeyData as CFData, keyDict as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        
        guard let dataToDecrypt = Data(base64Encoded: string) else {
            throw NSError(domain: "Invalid string to decrypt", code: -1, userInfo: nil)
        }
        
        var decryptedData = Data(count: SecKeyGetBlockSize(privateKey))
        var decryptedDataLength = decryptedData.count
        
        let status = decryptedData.withUnsafeMutableBytes { decryptedBytes in
            dataToDecrypt.withUnsafeBytes { encryptedBytes in
                SecKeyDecrypt(privateKey, .PKCS1, encryptedBytes.baseAddress!, dataToDecrypt.count, decryptedBytes.baseAddress!, &decryptedDataLength)
            }
        }
        
        guard status == errSecSuccess else {
            throw NSError(domain: "Decryption failed", code: Int(status), userInfo: nil)
        }
        
        decryptedData.count = decryptedDataLength
        return [UInt8](decryptedData)
    }
    
    static func decryptStringAsymmetricV2(_ string: String, _ privateKeyString: String) throws -> Data {
        let rsaCipher = "RSA/ECB/PKCS1Padding"
        
        guard let privateKeyData = Data(base64Encoded: privateKeyString) else {
            throw NSError(domain: "Invalid private key string", code: -1, userInfo: nil)
        }
        
        let keyDict: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(privateKeyData as CFData, keyDict as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        
        guard let cipher = SecKeyCreateDecryptedData(privateKey, .rsaEncryptionPKCS1, Data(base64Encoded: string) ?? Data(), &error) else {
            throw error!.takeRetainedValue() as Error
        }
        
        return cipher as Data
    }
    
    static func decryptStringAsymmetric(_ string: String, privateKey: SecKey) throws -> String {
        guard let data = Data(base64Encoded: string) else {
            throw NSError(domain: "InvalidBase64String", code: -1, userInfo: nil)
        }
        
        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(privateKey, .rsaEncryptionPKCS1, data as CFData, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        
        guard let decryptedString = String(data: decryptedData as Data, encoding: .utf8) else {
            throw NSError(domain: "InvalidUTF8String", code: -1, userInfo: nil)
        }
        
        return decryptedString
    }
    
    static func encryptStringSymmetricAsString(_ string: String, _ encryptionKeyBytes: [UInt8]) throws -> String {
        let ivDelimiter = ":" // Assuming ivDelimiter is defined somewhere
        let metadata = try encryptStringSymmetric(string, encryptionKeyBytes, ivDelimiter)
        return metadata.ciphertext
    }
    
    static func encryptStringSymmetricAsStringOld(_ string: String, encryptionKeyBytes: [UInt8]) throws -> String {
        let metadata = try encryptStringSymmetric(string, encryptionKeyBytes: encryptionKeyBytes, ivDelimiter: ivDelimiterOld)
        return metadata.ciphertext
    }
    
    static func decryptStringSymmetricAsString(string: String, encryptionKeyBytes: [UInt8], iv: [UInt8], authenticationTag: [UInt8], arbitraryDataProvider: ArbitraryDataProvider, user: User) throws -> String {
        return try decryptStringSymmetricAsString(
            decodeStringToBase64Bytes(string: string),
            encryptionKeyBytes: encryptionKeyBytes,
            iv: iv,
            authenticationTag: authenticationTag,
            false,
            arbitraryDataProvider: arbitraryDataProvider,
            user: user)
    }
    
    static func decryptStringSymmetricAsString(_ string: String, encryptionKeyBytes: [UInt8], iv: [UInt8], authenticationTag: [UInt8], fileDropV2: Bool, arbitraryDataProvider: ArbitraryDataProvider, user: User) throws -> String {
        
        return try decryptStringSymmetricAsString(
            decodeStringToBase64Bytes(string),
            encryptionKeyBytes: encryptionKeyBytes,
            iv: iv,
            authenticationTag: authenticationTag,
            fileDropV2: fileDropV2,
            arbitraryDataProvider: arbitraryDataProvider,
            user: user)
    }
    
    static func decryptStringSymmetricAsString(bytes: Data, encryptionKeyBytes: Data, iv: Data, authenticationTag: Data, fileDropV2: Bool, arbitraryDataProvider: ArbitraryDataProvider, user: User) throws -> String {
        let keyLength = kCCKeySizeAES256
        let tagLength = 16
        
        guard authenticationTag.count == tagLength else {
            reportE2eError(arbitraryDataProvider: arbitraryDataProvider, user: user)
            throw EncryptionError.invalidAuthenticationTag
        }
        
        let extractedAuthenticationTag = bytes.suffix(tagLength)
        guard extractedAuthenticationTag == authenticationTag else {
            reportE2eError(arbitraryDataProvider: arbitraryDataProvider, user: user)
            throw EncryptionError.invalidAuthenticationTag
        }
        
        var decryptedData = Data(count: bytes.count - tagLength)
        var numBytesDecrypted: size_t = 0
        
        let cryptStatus = decryptedData.withUnsafeMutableBytes { decryptedBytes in
            bytes.prefix(bytes.count - tagLength).withUnsafeBytes { encryptedBytes in
                encryptionKeyBytes.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCryptorGCM(kCCDecrypt,
                                     CCAlgorithm(kCCAlgorithmAES),
                                     keyBytes.baseAddress,
                                     keyLength,
                                     ivBytes.baseAddress,
                                     iv.count,
                                     nil,
                                     0,
                                     encryptedBytes.baseAddress,
                                     encryptedBytes.count,
                                     decryptedBytes.baseAddress,
                                     &numBytesDecrypted,
                                     extractedAuthenticationTag.baseAddress,
                                     tagLength)
                    }
                }
            }
        }
        
        guard cryptStatus == kCCSuccess else {
            throw EncryptionError.decryptionFailed
        }
        
        decryptedData.removeSubrange(numBytesDecrypted..<decryptedData.count)
        
        if fileDropV2 {
            return try EncryptionUtilsV2().gZipDecompress(data: decryptedData)
        } else {
            return decodeBase64BytesToString(data: decryptedData)
        }
    }
    
    static func encryptStringSymmetric(_ string: String, encryptionKeyBytes: [UInt8]) throws -> EncryptedMetadata {
        return try encryptStringSymmetric(string, encryptionKeyBytes: encryptionKeyBytes, ivDelimiter: ivDelimiter)
    }
    
    static func encryptStringSymmetric(_ string: String, encryptionKeyBytes: Data, delimiter: String) throws -> EncryptedMetadata {
        let bytes = encodeStringToBase64Bytes(string)
        return try encryptStringSymmetric(bytes, encryptionKeyBytes: encryptionKeyBytes, delimiter: delimiter)
    }
    
    static func encryptStringSymmetric(bytes: [UInt8], encryptionKeyBytes: [UInt8], delimiter: String) throws -> EncryptedMetadata {
        let ivLength = 12
        let iv = randomBytes(length: ivLength)
        
        var cryptedBytes = [UInt8](repeating: 0, count: bytes.count + kCCBlockSizeAES128)
        var numBytesEncrypted: size_t = 0
        
        let key = Data(encryptionKeyBytes)
        let ivData = Data(iv)
        
        let cryptStatus = key.withUnsafeBytes { keyBytes in
            ivData.withUnsafeBytes { ivBytes in
                CCCryptorGCM(kCCEncrypt, CCAlgorithm(kCCAlgorithmAES), keyBytes.baseAddress, key.count, ivBytes.baseAddress, iv.count, nil, 0, bytes, bytes.count, &cryptedBytes, &numBytesEncrypted)
            }
        }
        
        guard cryptStatus == kCCSuccess else {
            throw NSError(domain: "EncryptionError", code: Int(cryptStatus), userInfo: nil)
        }
        
        let cryptedData = Data(cryptedBytes.prefix(numBytesEncrypted))
        let encodedCryptedBytes = cryptedData.base64EncodedString()
        let encodedIV = ivData.base64EncodedString()
        let authenticationTag = cryptedData.suffix(16).base64EncodedString()
        
        return EncryptedMetadata(encryptedData: encodedCryptedBytes + delimiter + encodedIV, iv: encodedIV, authenticationTag: authenticationTag)
    }
    
    static func decryptStringSymmetric(_ string: String, encryptionKeyBytes: [UInt8]) throws -> String {
        let AES_CIPHER = "AES/GCM/NoPadding"
        let ivDelimiter = "your_iv_delimiter"
        let ivDelimiterOld = "your_old_iv_delimiter"
        
        guard let cipher = try? AESGCM() else {
            throw NSError(domain: "Cipher Initialization Failed", code: -1, userInfo: nil)
        }
        
        let delimiterPosition: String.Index
        let ivString: String
        
        if let range = string.range(of: ivDelimiter, options: .backwards) {
            delimiterPosition = range.lowerBound
            ivString = String(string[range.upperBound...])
        } else if let range = string.range(of: ivDelimiterOld, options: .backwards) {
            delimiterPosition = range.lowerBound
            ivString = String(string[range.upperBound...])
        } else {
            throw NSError(domain: "Delimiter Not Found", code: -1, userInfo: nil)
        }
        
        let cipherString = String(string[..<delimiterPosition])
        
        guard let ivData = Data(base64Encoded: ivString),
              let cipherData = Data(base64Encoded: cipherString) else {
            throw NSError(domain: "Base64 Decoding Failed", code: -1, userInfo: nil)
        }
        
        let key = SymmetricKey(data: Data(encryptionKeyBytes))
        
        let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: ivData), ciphertext: cipherData, tag: Data())
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        
        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw NSError(domain: "String Decoding Failed", code: -1, userInfo: nil)
        }
        
        return decryptedString
    }
    
    static func decryptStringSymmetric(string: String, encryptionKeyBytes: [UInt8], authenticationTag: String?, ivString: String) throws -> [UInt8] {
        guard let key = encryptionKeyBytes.withUnsafeBytes({ keyBytes in
            return SecKeyCreateWithData(Data(bytes: keyBytes.baseAddress!, count: keyBytes.count) as CFData, [
                kSecAttrKeyType: kSecAttrKeyTypeAES,
                kSecAttrKeySizeInBits: 256
            ] as CFDictionary, nil)
        }) else {
            throw EncryptionError.invalidKey
        }
        
        let delimiterPosition = string.lastIndex(of: ivDelimiter) ?? string.endIndex
        let cipherString = String(string[..<delimiterPosition])
        
        guard let ivData = Data(base64Encoded: ivString) else {
            throw EncryptionError.decryptionFailed
        }
        
        var decryptedData = Data()
        let cipherData = Data(base64Encoded: cipherString)!
        
        if let authenticationTag = authenticationTag {
            let authenticationTagBytes = Data(base64Encoded: authenticationTag)!
            let extractedAuthenticationTag = cipherData.suffix(128 / 8)
            
            if extractedAuthenticationTag != authenticationTagBytes {
                throw EncryptionError.authenticationTagMismatch
            }
        }
        
        var cryptor: CCCryptorRef?
        let status = CCCryptorCreateWithMode(CCOperation(kCCDecrypt), CCMode(kCCModeGCM), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding), ivData.bytes, encryptionKeyBytes, encryptionKeyBytes.count, nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
        
        guard status == kCCSuccess, let cryptorRef = cryptor else {
            throw EncryptionError.decryptionFailed
        }
        
        var outLength = 0
        decryptedData.count = cipherData.count + kCCBlockSizeAES128
        let updateStatus = CCCryptorUpdate(cryptorRef, cipherData.bytes, cipherData.count, &decryptedData, decryptedData.count, &outLength)
        
        guard updateStatus == kCCSuccess else {
            CCCryptorRelease(cryptorRef)
            throw EncryptionError.decryptionFailed
        }
        
        decryptedData.count = outLength
        CCCryptorRelease(cryptorRef)
        
        return [UInt8](decryptedData)
    }
    
    static func encryptPrivateKey(privateKey: String, keyPhrase: String) throws -> String {
        return try encryptPrivateKey(privateKey: privateKey, keyPhrase: keyPhrase, ivDelimiter: ivDelimiter)
    }
    
    static func encryptPrivateKeyOld(privateKey: String, keyPhrase: String) throws -> String {
        return try encryptPrivateKey(privateKey: privateKey, keyPhrase: keyPhrase, ivDelimiter: ivDelimiterOld)
    }
    
    private static func encryptPrivateKey(privateKey: String, keyPhrase: String, delimiter: String) throws -> String {
        let saltLength = 16
        let iterationCount = 10000
        let keyStrength = 256
        let aesCipher = "AES/CBC/PKCS5Padding"
        
        guard let salt = randomBytes(length: saltLength) else {
            throw NSError(domain: "EncryptionError", code: -1, userInfo: nil)
        }
        
        let keyData = try deriveKey(keyPhrase: keyPhrase, salt: salt, iterationCount: iterationCount, keyStrength: keyStrength)
        
        let cipher = try AES256Crypter(key: keyData, iv: nil)
        let bytes = encodeStringToBase64Bytes(privateKey)
        let encrypted = try cipher.encrypt(bytes)
        
        let iv = cipher.iv
        let encodedIV = encodeBytesToBase64String(iv)
        let encodedSalt = encodeBytesToBase64String(salt)
        let encodedEncryptedBytes = encodeBytesToBase64String(encrypted)
        
        return encodedEncryptedBytes + delimiter + encodedIV + delimiter + encodedSalt
    }
    
    static func decryptPrivateKey(privateKey: String, keyPhrase: String) throws -> String {
        let ivDelimiter = "your_iv_delimiter"
        let ivDelimiterOld = "your_old_iv_delimiter"
        let AES_CIPHER = "AES/CBC/PKCS5Padding"
        let iterationCount = 1000
        let keyStrength = 256
        let AES = kCCAlgorithmAES
        
        let strings: [String]
        if privateKey.lastIndex(of: ivDelimiter) == nil {
            strings = privateKey.components(separatedBy: ivDelimiterOld)
        } else {
            strings = privateKey.components(separatedBy: ivDelimiter)
        }
        
        let realPrivateKey = strings[0]
        guard let iv = Data(base64Encoded: strings[1]),
              let salt = Data(base64Encoded: strings[2]) else {
            throw EncryptionError.invalidKey
        }
        
        var key = Data(count: keyStrength / 8)
        let keyData = keyPhrase.data(using: .utf8)!
        let status = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), keyPhrase, keyPhrase.count, saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), UInt32(iterationCount), keyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), key.count)
            }
        }
        
        guard status == kCCSuccess else {
            throw EncryptionError.invalidKey
        }
        
        guard let cipher = try? AES_CIPHER.createCipher(key: key, iv: iv, operation: kCCDecrypt) else {
            throw EncryptionError.invalidKey
        }
        
        guard let bytes = Data(base64Encoded: realPrivateKey),
              let decrypted = cipher.update(data: bytes) else {
            throw EncryptionError.decryptionFailed
        }
        
        let pemKey = String(data: decrypted, encoding: .utf8)!
        return pemKey.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
    }
    
    static func privateKeyToPEM(privateKey: SecKey) -> String? {
        guard let privateKeyData = SecKeyCopyExternalRepresentation(privateKey, nil) as Data? else {
            return nil
        }
        let privateKeyString = privateKeyData.base64EncodedString()
        let formattedKey = privateKeyString.enumerated().map { $0.offset % 65 == 0 ? "\n\($0.element)" : "\($0.element)" }.joined()
        return "-----BEGIN PRIVATE KEY-----\n" + formattedKey + "\n-----END PRIVATE KEY-----"
    }
    
    static func PEMtoPrivateKey(_ pem: String) throws -> SecKey {
        guard let privateKeyData = Data(base64Encoded: pem) else {
            throw EncryptionUtilsError.invalidKey
        }
        
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: RSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(privateKeyData as CFData, keyAttributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        
        return privateKey
    }
    
    static func getRandomWords(count: Int, context: Any) throws -> [String] {
        guard let path = Bundle.main.path(forResource: "encryption_key_words", ofType: nil),
              let inputStream = InputStream(fileAtPath: path) else {
            throw NSError(domain: "FileNotFound", code: 404, userInfo: nil)
        }
        
        inputStream.open()
        defer { inputStream.close() }
        
        let inputStreamReader = InputStreamReader(inputStream: inputStream)
        let bufferedReader = BufferedReader(reader: inputStreamReader)
        
        var lines = [String]()
        while let line = bufferedReader.readLine() {
            lines.append(line)
        }
        
        var outputLines = [String]()
        for _ in 0..<count {
            let randomLine = Int(arc4random_uniform(UInt32(lines.count)))
            outputLines.append(lines[randomLine])
        }
        
        return outputLines
    }
    
    static func generateKeyPair() throws -> (privateKey: SecKey, publicKey: SecKey) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: errSecParam, userInfo: nil)
        }
        
        return (privateKey: privateKey, publicKey: publicKey)
    }
    
    static func generateKey() -> Data? {
        var keyData = Data(count: kCCKeySizeAES128)
        let result = keyData.withUnsafeMutableBytes { keyBytes in
            SecRandomCopyBytes(kSecRandomDefault, kCCKeySizeAES128, keyBytes)
        }
        
        if result == errSecSuccess {
            return keyData
        } else {
            print("Error generating key: \(result)")
            return nil
        }
    }
    
    static func generateKeyString() -> String {
        return EncryptionUtils.encodeBytesToBase64String(generateKey())
    }
    
    static func randomBytes(size: Int) -> [UInt8] {
        var iv = [UInt8](repeating: 0, count: size)
        _ = SecRandomCopyBytes(kSecRandomDefault, size, &iv)
        return iv
    }
    
    static func generateSHA512(token: String) -> String {
        let salt = EncryptionUtils.encodeBytesToBase64String(EncryptionUtils.randomBytes(length: EncryptionUtils.saltLength))
        return generateSHA512(token: token, salt: salt)
    }
    
    static func generateSHA512(token: String, salt: String) -> String {
        var hashedToken = ""
        if let digest = NSMutableData(length: Int(CC_SHA512_DIGEST_LENGTH)) {
            let saltData = salt.data(using: .utf8)!
            let tokenData = token.data(using: .utf8)!
            
            saltData.withUnsafeBytes { saltBytes in
                tokenData.withUnsafeBytes { tokenBytes in
                    CC_SHA512_CTX().withMemoryRebound(to: CC_SHA512_CTX.self, capacity: 1) { context in
                        CC_SHA512_Init(context)
                        CC_SHA512_Update(context, saltBytes.baseAddress, CC_LONG(saltData.count))
                        CC_SHA512_Update(context, tokenBytes.baseAddress, CC_LONG(tokenData.count))
                        CC_SHA512_Final(digest.mutableBytes.assumingMemoryBound(to: UInt8.self), context)
                    }
                }
            }
            
            let hashBytes = digest.map { String(format: "%02x", $0) }
            hashedToken = hashBytes.joined() + HASH_DELIMITER + salt
        }
        return hashedToken
    }
    
    static func verifySHA512(hashWithSalt: String, compareToken: String) -> Bool {
        let components = hashWithSalt.split(separator: Character(HASH_DELIMITER))
        guard components.count > 1 else { return false }
        let salt = String(components[1])
        
        let newHash = generateSHA512(compareToken: compareToken, salt: salt)
        
        return hashWithSalt == newHash
    }
    
    static func lockFolder(parentFile: ServerFileInterface, client: OwnCloudClient) throws -> String {
        return try lockFolder(parentFile: parentFile, client: client, timeout: -1)
    }
    
    static func lockFolder(parentFile: ServerFileInterface, client: OwnCloudClient, counter: Int64) throws -> String {
        let lockFileOperation = LockFileRemoteOperation(localId: parentFile.getLocalId(), counter: counter)
        let lockFileOperationResult = lockFileOperation.execute(client: client)
        
        if lockFileOperationResult.isSuccess, let resultData = lockFileOperationResult.getResultData(), !resultData.isEmpty {
            return resultData
        } else if lockFileOperationResult.getHttpCode() == HttpStatus.SC_FORBIDDEN {
            throw UploadException.forbidden
        } else {
            throw UploadException.couldNotLockFolder
        }
    }
    
    static func retrieveMetadataV1(parentFile: OCFile, client: OwnCloudClient, privateKey: String, publicKey: String, arbitraryDataProvider: ArbitraryDataProvider, user: User) throws -> (Bool, DecryptedFolderMetadataFileV1) {
        let localId = parentFile.localId
        
        let getMetadataOperation = GetMetadataRemoteOperation(localId: localId)
        let getMetadataOperationResult = getMetadataOperation.execute(client: client)
        
        var metadata: DecryptedFolderMetadataFileV1
        
        if getMetadataOperationResult.isSuccess {
            let serializedEncryptedMetadata = getMetadataOperationResult.resultData.metadata
            
            let encryptedFolderMetadata: EncryptedFolderMetadataFileV1 = EncryptionUtils.deserializeJSON(serializedEncryptedMetadata)
            
            return (true, try decryptFolderMetaData(encryptedFolderMetadata: encryptedFolderMetadata,
                                                    privateKey: privateKey,
                                                    arbitraryDataProvider: arbitraryDataProvider,
                                                    user: user,
                                                    localId: localId))
            
        } else if getMetadataOperationResult.httpCode == HttpStatus.SC_NOT_FOUND {
            metadata = DecryptedFolderMetadataFileV1()
            metadata.metadata = DecryptedMetadata()
            metadata.metadata.version = Double(E2EVersion.V1_2.rawValue)!
            metadata.metadata.metadataKeys = [:]
            let metadataKey = EncryptionUtils.encodeBytesToBase64String(EncryptionUtils.generateKey())
            let encryptedMetadataKey = EncryptionUtils.encryptStringAsymmetric(metadataKey, publicKey: publicKey)
            metadata.metadata.metadataKey = encryptedMetadataKey
            
            return (false, metadata)
        } else {
            throw EncryptionError.uploadException("something wrong")
        }
    }
    
    static func retrieveMetadata(parentFile: OCFile, client: OwnCloudClient, privateKey: String, publicKey: String, storageManager: FileDataStorageManager, user: User, context: Context, arbitraryDataProvider: ArbitraryDataProvider) throws -> (Bool, DecryptedFolderMetadataFile) {
        
        let localId = parentFile.getLocalId()
        
        let getMetadataOperation = GetMetadataRemoteOperation(localId: localId)
        let getMetadataOperationResult = try getMetadataOperation.execute(client: client)
        
        var metadata: DecryptedFolderMetadataFile
        
        if getMetadataOperationResult.isSuccess {
            let serializedEncryptedMetadata = getMetadataOperationResult.resultData.metadata
            
            let encryptedFolderMetadata: EncryptedFolderMetadataFile = try EncryptionUtils.deserializeJSON(serializedEncryptedMetadata)
            
            return (true, try EncryptionUtilsV2().decryptFolderMetadataFile(encryptedFolderMetadata: encryptedFolderMetadata,
                                                                            userId: client.getUserId(),
                                                                            privateKey: privateKey,
                                                                            parentFile: parentFile,
                                                                            storageManager: storageManager,
                                                                            client: client,
                                                                            e2eCounter: parentFile.getE2eCounter(),
                                                                            signature: getMetadataOperationResult.resultData.signature,
                                                                            user: user,
                                                                            context: context,
                                                                            arbitraryDataProvider: arbitraryDataProvider))
            
        } else if getMetadataOperationResult.httpCode == HttpStatus.SC_NOT_FOUND ||
                    getMetadataOperationResult.httpCode == HttpStatus.SC_INTERNAL_SERVER_ERROR {
            metadata = DecryptedFolderMetadataFile(metadata: DecryptedMetadata(),
                                                   users: [],
                                                   keyChecksums: [:],
                                                   version: E2EVersion.V2_0.getValue())
            metadata.users.append(DecryptedUser(userId: client.getUserId(), publicKey: publicKey, metadataKey: nil))
            guard let metadataKey = EncryptionUtils.generateKey() else {
                throw UploadException("Could not encrypt folder!")
            }
            
            metadata.metadata.metadataKey = metadataKey
            metadata.metadata.keyChecksums.append(try EncryptionUtilsV2().hashMetadataKey(metadataKey: metadataKey))
            
            return (false, metadata)
        } else {
            reportE2eError(arbitraryDataProvider: arbitraryDataProvider, user: user)
            throw UploadException("something wrong")
        }
    }
    
    static func uploadMetadata(parentFile: ServerFileInterface, serializedFolderMetadata: String, token: String, client: OwnCloudClient, metadataExists: Bool, version: E2EVersion, signature: String, arbitraryDataProvider: ArbitraryDataProvider, user: User) throws {
        var uploadMetadataOperationResult: RemoteOperationResult<String>
        
        if metadataExists {
            if version == .V2_0 {
                uploadMetadataOperationResult = UpdateMetadataV2RemoteOperation(
                    remoteId: parentFile.getRemoteId(),
                    serializedFolderMetadata: serializedFolderMetadata,
                    token: token,
                    signature: signature
                ).execute(client: client)
            } else {
                uploadMetadataOperationResult = UpdateMetadataRemoteOperation(
                    localId: parentFile.getLocalId(),
                    serializedFolderMetadata: serializedFolderMetadata,
                    token: token
                ).execute(client: client)
            }
        } else {
            if version == .V2_0 {
                uploadMetadataOperationResult = StoreMetadataV2RemoteOperation(
                    remoteId: parentFile.getRemoteId(),
                    serializedFolderMetadata: serializedFolderMetadata,
                    token: token,
                    signature: signature
                ).execute(client: client)
            } else {
                uploadMetadataOperationResult = StoreMetadataRemoteOperation(
                    localId: parentFile.getLocalId(),
                    serializedFolderMetadata: serializedFolderMetadata
                ).execute(client: client)
            }
        }
        
        if !uploadMetadataOperationResult.isSuccess() {
            reportE2eError(arbitraryDataProvider: arbitraryDataProvider, user: user)
            throw UploadException.uploadFailed("Storing/updating metadata was not successful")
        }
    }
    
    static func unlockFolder(parentFolder: ServerFileInterface, client: OwnCloudClient, token: String?) -> RemoteOperationResult<Void> {
        if let token = token {
            return UnlockFileRemoteOperation(localId: parentFolder.getLocalId(), token: token).execute(client: client)
        } else {
            return RemoteOperationResult<Void>(error: NSError(domain: "No token available", code: 0, userInfo: nil))
        }
    }
    
    static func unlockFolderV1(parentFolder: ServerFileInterface, client: OwnCloudClient, token: String?) -> RemoteOperationResult<Void> {
        if let token = token {
            return UnlockFileV1RemoteOperation(localId: parentFolder.getLocalId(), token: token).execute(client: client)
        } else {
            return RemoteOperationResult<Void>(error: NSError(domain: "No token available", code: 0, userInfo: nil))
        }
    }
    
    static func convertCertFromString(_ string: String) throws -> SecCertificate {
        let trimmedCert = string.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----\n", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----\n", with: "")
        guard let encodedCert = trimmedCert.data(using: .utf8) else {
            throw NSError(domain: "InvalidEncoding", code: -1, userInfo: nil)
        }
        guard let decodedCert = Data(base64Encoded: encodedCert) else {
            throw NSError(domain: "InvalidBase64", code: -1, userInfo: nil)
        }
        guard let certificate = SecCertificateCreateWithData(nil, decodedCert as CFData) else {
            throw NSError(domain: "CertificateCreationFailed", code: -1, userInfo: nil)
        }
        return certificate
    }
    
    static func convertPublicKeyFromString(_ string: String) throws -> SecKey? {
        guard let certificate = try? convertCertFromString(string) else {
            throw NSError(domain: "CertificateError", code: -1, userInfo: nil)
        }
        return SecCertificateCopyKey(certificate)
    }
    
    static func removeE2E(arbitraryDataProvider: ArbitraryDataProvider, user: User) {
        arbitraryDataProvider.deleteKeyForAccount(user.getAccountName(), key: EncryptionUtils.PRIVATE_KEY)
        arbitraryDataProvider.deleteKeyForAccount(user.getAccountName(), key: EncryptionUtils.PUBLIC_KEY)
        arbitraryDataProvider.deleteKeyForAccount(user.getAccountName(), key: EncryptionUtils.MNEMONIC)
    }
    
    static func isMatchingKeys(keyPair: (privateKey: SecKey, publicKey: SecKey), publicKeyString: String) throws -> Bool {
        guard let publicKeyData = Data(base64Encoded: publicKeyString),
              let publicKey = try? convertPublicKeyFromString(publicKeyData: publicKeyData) else {
            throw NSError(domain: "InvalidPublicKey", code: -1, userInfo: nil)
        }
        
        guard let privateKeyAttributes = SecKeyCopyAttributes(keyPair.privateKey) as? [CFString: Any],
              let privateKeyModulus = privateKeyAttributes[kSecAttrModulus] as? Data,
              let publicKeyAttributes = SecKeyCopyAttributes(publicKey) as? [CFString: Any],
              let publicKeyModulus = publicKeyAttributes[kSecAttrModulus] as? Data else {
            throw NSError(domain: "KeyAttributesError", code: -1, userInfo: nil)
        }
        
        return privateKeyModulus == publicKeyModulus
    }
    
    static func supportsSecureFiledrop(file: OCFile, user: User) -> Bool {
        return file.isEncrypted() &&
            file.isFolder() &&
            user.server.version.isNewerOrEqual(to: NextcloudVersion.nextcloud_26)
    }
    
    static func generateChecksum(metadataFile: DecryptedFolderMetadataFileV1, mnemonic: String) throws -> String {
        var stringBuilder = mnemonic.replacingOccurrences(of: " ", with: "")
        
        let keys = Array(metadataFile.getFiles().keys).sorted()
        
        for key in keys {
            stringBuilder.append(key)
        }
        
        stringBuilder.append(metadataFile.getMetadata().getMetadataKey())
        
        return sha256(stringBuilder)
    }
    
    static func sha256(_ string: String) -> String? {
        guard let data = string.data(using: .utf8) else { return nil }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    static func bytesToHex(_ bytes: [UInt8]) -> String {
        var result = ""
        for individualByte in bytes {
            result += String(format: "%02x", individualByte)
        }
        return result
    }
    
    static func addIdToMigratedIds(id: Int64, user: User, arbitraryDataProvider: ArbitraryDataProvider) {
        let ids = arbitraryDataProvider.getValue(user: user, key: MIGRATED_FOLDER_IDS)
        
        var arrayList: [Int64] = []
        if let data = ids.data(using: .utf8) {
            if let jsonArray = try? JSONSerialization.jsonObject(with: data, options: []) as? [Int64] {
                arrayList = jsonArray
            }
        }
        
        if arrayList.contains(id) {
            return
        }
        
        arrayList.append(id)
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: arrayList, options: []),
           let json = String(data: jsonData, encoding: .utf8) {
            arbitraryDataProvider.storeOrUpdateKeyValue(accountName: user.getAccountName(), key: MIGRATED_FOLDER_IDS, value: json)
        }
    }
    
    static func isFolderMigrated(id: Int64, user: User, arbitraryDataProvider: ArbitraryDataProvider) -> Bool {
        let gson = Gson()
        let ids = arbitraryDataProvider.getValue(user: user, key: MIGRATED_FOLDER_IDS)
        
        guard let data = ids.data(using: .utf8) else {
            return false
        }
        
        let arrayList: [Int64]? = try? gson.fromJson(data: data, type: [Int64].self)
        
        if arrayList == nil {
            return false
        }
        
        return arrayList!.contains(id)
    }
    
    static func reportE2eError(arbitraryDataProvider: ArbitraryDataProvider, user: User) {
        arbitraryDataProvider.incrementValue(user.getAccountName(), key: ArbitraryDataProvider.E2E_ERRORS)
        
        if arbitraryDataProvider.getLongValue(user.getAccountName(), key: ArbitraryDataProvider.E2E_ERRORS_TIMESTAMP) == -1 {
            arbitraryDataProvider.storeOrUpdateKeyValue(
                user.getAccountName(),
                key: ArbitraryDataProvider.E2E_ERRORS_TIMESTAMP,
                value: Int64(Date().timeIntervalSince1970)
            )
        }
    }
    
    static func readE2eError(arbitraryDataProvider: ArbitraryDataProvider, user: User) -> Problem? {
        let value = arbitraryDataProvider.getIntegerValue(user.getAccountName(), ArbitraryDataProvider.E2E_ERRORS)
        let timestamp = arbitraryDataProvider.getLongValue(user.getAccountName(), ArbitraryDataProvider.E2E_ERRORS_TIMESTAMP)
        
        arbitraryDataProvider.deleteKeyForAccount(user.getAccountName(), ArbitraryDataProvider.E2E_ERRORS)
        arbitraryDataProvider.deleteKeyForAccount(user.getAccountName(), ArbitraryDataProvider.E2E_ERRORS_TIMESTAMP)
        
        if value > 0 && timestamp > 0 {
            return Problem(type: SendClientDiagnosticRemoteOperation.E2EE_ERRORS, value: value, timestamp: timestamp)
        } else {
            return nil
        }
    }
    
    static func generateUid() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
    
    static func retrievePublicKeyForUser(user: User, context: Context) -> String {
        return ArbitraryDataProviderImpl(context: context).getValue(user: user, key: PUBLIC_KEY)
    }
    
    static func generateIV() -> [UInt8] {
        return EncryptionUtils.randomBytes(length: EncryptionUtils.ivLength)
    }
    
    static func byteToHex(_ bytes: [UInt8]) -> String {
        var sbKey = ""
        for b in bytes {
            sbKey += String(format: "%02X ", b)
        }
        return sbKey
    }
    
    static func savePublicKey(currentUser: User, key: String, user: String, arbitraryDataProvider: ArbitraryDataProvider) {
        arbitraryDataProvider.storeOrUpdateKeyValue(currentUser, key: ArbitraryDataProvider.PUBLIC_KEY + user, value: key)
    }
    
    static func getPublicKey(currentUser: User, user: String, arbitraryDataProvider: ArbitraryDataProvider) -> String {
        return arbitraryDataProvider.getValue(currentUser, key: ArbitraryDataProvider.PUBLIC_KEY + user)
    }
}
