
import UIKit

class ShareeListAdapter: NSObject, UICollectionViewDataSource, DisplayUtils.AvatarGenerationListener {
    private let listener: ShareeListAdapterListener
    private let fileActivity: FileActivity
    private var shares: [OCShare]
    private let avatarRadiusDimension: CGFloat
    private let userId: String
    private let user: User
    private let viewThemeUtils: ViewThemeUtils
    private let encrypted: Bool

    init(fileActivity: FileActivity,
         shares: [OCShare],
         listener: ShareeListAdapterListener,
         userId: String,
         user: User,
         viewThemeUtils: ViewThemeUtils,
         encrypted: Bool) {
        self.fileActivity = fileActivity
        self.shares = shares
        self.listener = listener
        self.userId = userId
        self.user = user
        self.viewThemeUtils = viewThemeUtils
        self.encrypted = encrypted

        self.avatarRadiusDimension = fileActivity.resources.dimension(R.dimen.user_icon_radius)

        super.init()
        sortShares()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let shareViaLink = MDMConfig.instance.shareViaLink(fileActivity)
        return shareViaLink ? shares.count : 1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let shareViaLink = MDMConfig.instance.shareViaLink(fileActivity)
        let viewType = shares[indexPath.row].shareType.value

        if shareViaLink {
            switch ShareType.fromValue(viewType) {
            case .publicLink, .email:
                return LinkShareViewHolder(
                    FileDetailsShareLinkShareItemBinding.inflate(LayoutInflater.from(fileActivity),
                                                                 collectionView,
                                                                 false),
                    fileActivity,
                    viewThemeUtils)
            case .newPublicLink:
                if encrypted {
                    return NewSecureFileDropViewHolder(
                        FileDetailsShareSecureFileDropAddNewItemBinding.inflate(LayoutInflater.from(fileActivity),
                                                                                collectionView,
                                                                                false)
                    )
                } else {
                    return NewLinkShareViewHolder(
                        FileDetailsSharePublicLinkAddNewItemBinding.inflate(LayoutInflater.from(fileActivity),
                                                                            collectionView,
                                                                            false)
                    )
                }
            case .internal:
                return InternalShareViewHolder(
                    FileDetailsShareInternalShareLinkBinding.inflate(LayoutInflater.from(fileActivity), collectionView, false),
                    fileActivity)
            default:
                return ShareViewHolder(FileDetailsShareShareItemBinding.inflate(LayoutInflater.from(fileActivity),
                                                                                collectionView,
                                                                                false),
                                       user,
                                       fileActivity,
                                       viewThemeUtils)
            }
        } else {
            return InternalShareViewHolder(
                FileDetailsShareInternalShareLinkBinding.inflate(LayoutInflater.from(fileActivity), collectionView, false),
                fileActivity)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard shares.count > indexPath.row else { return }

        let share = shares[indexPath.row]
        let shareViaLink = MDMConfig.instance.shareViaLink(fileActivity)

        if !shareViaLink {
            if let internalShareViewHolder = collectionView.cellForItem(at: indexPath) as? InternalShareViewHolder {
                internalShareViewHolder.bind(share, listener)
            }
            return
        }

        if let publicShareViewHolder = collectionView.cellForItem(at: indexPath) as? LinkShareViewHolder {
            publicShareViewHolder.bind(share, listener)
        } else if let internalShareViewHolder = collectionView.cellForItem(at: indexPath) as? InternalShareViewHolder {
            internalShareViewHolder.bind(share, listener)
        } else if let newLinkShareViewHolder = collectionView.cellForItem(at: indexPath) as? NewLinkShareViewHolder {
            newLinkShareViewHolder.bind(listener)
        } else if let newSecureFileDropViewHolder = collectionView.cellForItem(at: indexPath) as? NewSecureFileDropViewHolder {
            newSecureFileDropViewHolder.bind(listener)
        } else if let userViewHolder = collectionView.cellForItem(at: indexPath) as? ShareViewHolder {
            userViewHolder.bind(share, listener, self, userId, avatarRadiusDimension)
        }
    }

    func addShares(_ sharesToAdd: [OCShare]) {
        shares.append(contentsOf: sharesToAdd)
        sortShares()
        notifyDataSetChanged()
    }

    func avatarGenerated(avatarDrawable: Drawable, callContext: Any) {
        if let iv = callContext as? UIImageView {
            iv.image = avatarDrawable
        }
    }

    func shouldCallGeneratedCallback(tag: String, callContext: Any) -> Bool {
        if let iv = callContext as? UIImageView {
            return String(describing: iv.tag) == tag.split(separator: "@")[0]
        }
        return false
    }

    func remove(share: OCShare) {
        if let index = shares.firstIndex(of: share) {
            shares.remove(at: index)
            notifyDataSetChanged()
        }
    }

    func sortShares() {
        var links: [OCShare] = []
        var users: [OCShare] = []

        for share in shares {
            if share.shareType == .publicLink || share.shareType == .email {
                links.append(share)
            } else if share.shareType != .internal {
                users.append(share)
            }
        }

        links.sort { $0.sharedDate > $1.sharedDate }
        users.sort { $0.sharedDate > $1.sharedDate }

        shares = links
        shares.append(contentsOf: users)

        if !encrypted {
            let ocShare = OCShare()
            ocShare.shareType = .internal
            shares.append(ocShare)
        }
    }

    func getShares() -> [OCShare] {
        return shares
    }

    func removeNewPublicShare() {
        for (index, share) in shares.enumerated() {
            if share.shareType == .newPublicLink {
                shares.remove(at: index)
                break
            }
        }
    }
}
