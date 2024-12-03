
import Foundation
import UIKit

class X509CertificateViewAdapter: SslUntrustedCertDialog.CertificateViewAdapter {
    
    private let mCertificate: X509Certificate?
    private static let TAG = String(describing: X509CertificateViewAdapter.self)
    
    init(certificate: X509Certificate) {
        self.mCertificate = certificate
    }
    
    override func updateCertificateView(binding: SslUntrustedCertLayoutBinding) {
        if let certificate = mCertificate {
            binding.nullCert.isHidden = true
            showSubject(subject: certificate.subjectX500Principal, binding: binding)
            showIssuer(issuer: certificate.issuerX500Principal, binding: binding)
            showValidity(notBefore: certificate.notBefore, notAfter: certificate.notAfter, binding: binding)
            showSignature(binding: binding)
        } else {
            binding.nullCert.isHidden = false
        }
    }
    
    private func getDigest(algorithm: String, message: [UInt8]) -> [UInt8]? {
        guard let md = try? MessageDigest(algorithm: algorithm) else {
            return nil
        }
        md.reset()
        return md.digest(message)
    }
    
    private func showSignature(binding: SslUntrustedCertLayoutBinding) {
        var cert: [UInt8]?
        
        do {
            cert = try mCertificate?.encoded()
            if cert == nil {
                binding.valueCertificateFingerprint.text = NSLocalizedString("certificate_load_problem", comment: "")
                binding.valueSignatureAlgorithm.text = NSLocalizedString("certificate_load_problem", comment: "")
            } else {
                binding.valueCertificateFingerprint.text = getDigestString(context: binding.valueCertificateFingerprint.context, cert: cert!)
                binding.valueSignatureAlgorithm.text = mCertificate?.sigAlgName
            }
        } catch {
            Log_OC.e(X509CertificateViewAdapter.TAG, "Problem while trying to decode the certificate.")
        }
    }
    
    private func getDigestString(context: Context, cert: [UInt8]) -> String {
        return getDigestHexBytesWithColonsAndNewLines(context: context, digestType: "SHA-256", cert: cert) +
               getDigestHexBytesWithColonsAndNewLines(context: context, digestType: "SHA-1", cert: cert) +
               getDigestHexBytesWithColonsAndNewLines(context: context, digestType: "MD5", cert: cert)
    }
    
    private func getDigestHexBytesWithColonsAndNewLines(context: Context, digestType: String, cert: [UInt8]) -> String {
        let newLine = "\n"
        guard let rawDigest = getDigest(algorithm: digestType, message: cert) else {
            return "\(digestType):\(newLine)\(context.getString(R.string.digest_algorithm_not_available))\(newLine)\(newLine)"
        }
        
        var hex = ""
        for b in rawDigest {
            let hiVal = (b & 0xF0) >> 4
            let loVal = b & 0x0F
            hex.append(Character(UnicodeScalar(hiVal + (hiVal / 10 * 7) + 48)!))
            hex.append(Character(UnicodeScalar(loVal + (loVal / 10 * 7) + 48)!))
            hex.append(":")
        }
        return "\(digestType):\(newLine)\(hex.dropLast())\(newLine)\(newLine)"
    }
    
    private func showValidity(notBefore: Date, notAfter: Date, binding: SslUntrustedCertLayoutBinding) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        binding.valueValidityFrom.text = dateFormatter.string(from: notBefore)
        binding.valueValidityTo.text = dateFormatter.string(from: notAfter)
    }
    
    private func showSubject(subject: X500Principal, binding: SslUntrustedCertLayoutBinding) {
        let s = parsePrincipal(principal: subject)
        
        if let cn = s["CN"] {
            binding.valueSubjectCN.text = cn
            binding.valueSubjectCN.isHidden = false
        } else {
            binding.valueSubjectCN.isHidden = true
        }
        if let o = s["O"] {
            binding.valueSubjectO.text = o
            binding.valueSubjectO.isHidden = false
        } else {
            binding.valueSubjectO.isHidden = true
        }
        if let ou = s["OU"] {
            binding.valueSubjectOU.text = ou
            binding.valueSubjectOU.isHidden = false
        } else {
            binding.valueSubjectOU.isHidden = true
        }
        if let c = s["C"] {
            binding.valueSubjectC.text = c
            binding.valueSubjectC.isHidden = false
        } else {
            binding.valueSubjectC.isHidden = true
        }
        if let st = s["ST"] {
            binding.valueSubjectST.text = st
            binding.valueSubjectST.isHidden = false
        } else {
            binding.valueSubjectST.isHidden = true
        }
        if let l = s["L"] {
            binding.valueSubjectL.text = l
            binding.valueSubjectL.isHidden = false
        } else {
            binding.valueSubjectL.isHidden = true
        }
    }
    
    private func showIssuer(issuer: X500Principal, binding: SslUntrustedCertLayoutBinding) {
        let s = parsePrincipal(principal: issuer)
        
        if let cn = s["CN"] {
            binding.valueIssuerCN.text = cn
            binding.valueIssuerCN.isHidden = false
        } else {
            binding.valueIssuerCN.isHidden = true
        }
        if let o = s["O"] {
            binding.valueIssuerO.text = o
            binding.valueIssuerO.isHidden = false
        } else {
            binding.valueIssuerO.isHidden = true
        }
        if let ou = s["OU"] {
            binding.valueIssuerOU.text = ou
            binding.valueIssuerOU.isHidden = false
        } else {
            binding.valueIssuerOU.isHidden = true
        }
        if let c = s["C"] {
            binding.valueIssuerC.text = c
            binding.valueIssuerC.isHidden = false
        } else {
            binding.valueIssuerC.isHidden = true
        }
        if let st = s["ST"] {
            binding.valueIssuerST.text = st
            binding.valueIssuerST.isHidden = false
        } else {
            binding.valueIssuerST.isHidden = true
        }
        if let l = s["L"] {
            binding.valueIssuerL.text = l
            binding.valueIssuerL.isHidden = false
        } else {
            binding.valueIssuerL.isHidden = true
        }
    }
    
    private func parsePrincipal(principal: Principal) -> [String: String] {
        var result = [String: String]()
        let toParse = principal.getName()
        let pieces = toParse.split(separator: ",")
        let tokens = ["CN", "O", "OU", "C", "ST", "L"]
        for piece in pieces {
            for token in tokens {
                if piece.hasPrefix("\(token)=") {
                    let value = piece.dropFirst(token.count + 1)
                    result[token] = String(value)
                }
            }
        }
        return result
    }
}
