
import UIKit

class InternalShareViewHolder: UICollectionViewCell {
    private var binding: FileDetailsShareInternalShareLinkBinding
    private var context: Context

    init(binding: FileDetailsShareInternalShareLinkBinding, context: Context) {
        self.binding = binding
        self.context = context
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(share: OCShare, listener: ShareeListAdapterListener) {
        binding.copyInternalLinkIcon.background?.setColorFilter(UIColor(named: "nc_grey")?.cgColor, for: .normal)
        binding.copyInternalLinkIcon.image?.withRenderingMode(.alwaysTemplate)
        binding.copyInternalLinkIcon.tintColor = UIColor(named: "icon_on_nc_grey")

        if share.isFolder() {
            binding.shareInternalLinkText.text = NSLocalizedString("share_internal_link_to_folder_text", comment: "")
        } else {
            binding.shareInternalLinkText.text = NSLocalizedString("share_internal_link_to_file_text", comment: "")
        }

        binding.copyInternalContainer.addTarget(self, action: #selector(listener.copyInternalLink), for: .touchUpInside)
    }
}
