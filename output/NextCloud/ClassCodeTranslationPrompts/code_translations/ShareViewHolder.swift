
import UIKit

class ShareViewHolder: UICollectionViewCell {
    private var binding: FileDetailsShareShareItemBinding!
    private var avatarRadiusDimension: Float = 0.0
    private var user: User!
    private var context: Context!
    private var viewThemeUtils: ViewThemeUtils!

    init(binding: FileDetailsShareShareItemBinding, user: User, context: Context, viewThemeUtils: ViewThemeUtils) {
        super.init(frame: .zero)
        self.binding = binding
        self.user = user
        self.context = context
        self.viewThemeUtils = viewThemeUtils
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(share: OCShare, listener: ShareeListAdapterListener, avatarListener: DisplayUtils.AvatarGenerationListener, userId: String, avatarRadiusDimension: Float) {
        self.avatarRadiusDimension = avatarRadiusDimension
        var name = share.getSharedWithDisplayName()
        binding.icon.tag = nil

        switch share.getShareType() {
        case .GROUP:
            name = context.getString(R.string.share_group_clarification, name)
            viewThemeUtils.files.createAvatar(share.getShareType(), binding.icon, context)
        case .ROOM:
            name = context.getString(R.string.share_room_clarification, name)
            viewThemeUtils.files.createAvatar(share.getShareType(), binding.icon, context)
        case .CIRCLE:
            viewThemeUtils.files.createAvatar(share.getShareType(), binding.icon, context)
        case .FEDERATED:
            name = context.getString(R.string.share_remote_clarification, name)
            setImage(avatar: binding.icon, name: share.getSharedWithDisplayName(), fallback: R.drawable.ic_user)
        case .USER:
            binding.icon.tag = share.getShareWith()
            let avatarRadius = context.resources.getDimension(R.dimen.list_item_avatar_icon_radius)
            DisplayUtils.setAvatar(user: user, shareWith: share.getShareWith(), sharedWithDisplayName: share.getSharedWithDisplayName(), avatarListener: avatarListener, avatarRadius: avatarRadius, resources: context.resources, imageView: binding.icon, context: context)

            binding.icon.setOnClickListener { _ in
                listener.showProfileBottomSheet(user: user, shareWith: share.getShareWith())
            }
        default:
            setImage(avatar: binding.icon, name: name, fallback: R.drawable.ic_user)
        }

        binding.name.text = name

        if share.getShareWith().equalsIgnoreCase(userId) || share.getUserId().equalsIgnoreCase(userId) {
            binding.overflowMenu.isHidden = false

            let permissionName = SharingMenuHelper.getPermissionName(context: context, share: share)
            setPermissionName(permissionName)

            binding.overflowMenu.setOnClickListener { _ in
                listener.showSharingMenuActionSheet(share: share)
            }
            binding.shareNameLayout.setOnClickListener { _ in
                listener.showPermissionsDialog(share: share)
            }
        } else {
            binding.overflowMenu.isHidden = true
        }
    }

    private func setPermissionName(_ permissionName: String?) {
        if let permissionName = permissionName, !permissionName.isEmpty {
            binding.permissionName.text = permissionName
            binding.permissionName.isHidden = false
        } else {
            binding.permissionName.isHidden = true
        }
    }

    private func setImage(avatar: UIImageView, name: String, fallback: Int) {
        do {
            avatar.image = try TextDrawable.createNamedAvatar(name: name, radius: avatarRadiusDimension)
        } catch {
            avatar.image = UIImage(named: "\(fallback)")
        }
    }
}
