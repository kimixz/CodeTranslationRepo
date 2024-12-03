
import UIKit

class CertificateCombinedExceptionViewAdapter: SslUntrustedCertDialogErrorViewAdapter {

    private let mSslException: CertificateCombinedException

    init(sslException: CertificateCombinedException) {
        self.mSslException = sslException
    }

    func updateErrorView(binding: SslUntrustedCertLayoutBinding) {
        // clean
        binding.reasonNoInfoAboutError.isHidden = true

        // refresh
        if mSslException.certPathValidatorException != nil {
            binding.reasonCertNotTrusted.isHidden = false
        } else {
            binding.reasonCertNotTrusted.isHidden = true
        }

        if mSslException.certificateExpiredException != nil {
            binding.reasonCertExpired.isHidden = false
        } else {
            binding.reasonCertExpired.isHidden = true
        }

        if mSslException.certificateNotYetValidException != nil {
            binding.reasonCertNotYetValid.isHidden = false
        } else {
            binding.reasonCertNotYetValid.isHidden = true
        }

        if mSslException.sslPeerUnverifiedException != nil {
            binding.reasonHostnameNotVerified.isHidden = false
        } else {
            binding.reasonHostnameNotVerified.isHidden = true
        }
    }
}
