
import UIKit
import SDWebImageSVGCoder

class NotificationListAdapter: NSObject, UICollectionViewDataSource {
    private static let FILE = "file"
    private static let ACTION_TYPE_WEB = "WEB"
    private let styleSpanBold = UIFont.boldSystemFont(ofSize: UIFont.systemFontSize)
    private let foregroundColorSpanBlack: UIColor

    private var notificationsList: [Notification]
    private let client: NextcloudClient
    private let notificationsActivity: NotificationsActivity
    private let viewThemeUtils: ViewThemeUtils

    init(client: NextcloudClient, notificationsActivity: NotificationsActivity, viewThemeUtils: ViewThemeUtils) {
        self.notificationsList = []
        self.client = client
        self.notificationsActivity = notificationsActivity
        self.viewThemeUtils = viewThemeUtils
        self.foregroundColorSpanBlack = notificationsActivity.resources.color(named: "text_color")!
    }

    func setNotificationItems(_ notificationItems: [Notification]) {
        notificationsList.removeAll()
        notificationsList.append(contentsOf: notificationItems)
        notifyDataSetChanged()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return notificationsList.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "NotificationViewHolder", for: indexPath) as! NotificationViewHolder
        return cell
    }

    func onBindViewHolder(_ holder: NotificationViewHolder, position: Int) {
        let notification = notificationsList[position]
        holder.binding.datetime.text = DisplayUtils.getRelativeTimestamp(notificationsActivity, notification.datetime.time)

        let file = notification.subjectRichParameters[NotificationListAdapter.FILE]
        var subject = notification.subject
        if file == nil && !notification.link.isEmpty {
            subject += " ↗"
            holder.binding.subject.font = styleSpanBold
            holder.binding.subject.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleLinkTap(_:))))
            holder.binding.subject.text = subject
        } else {
            if !notification.subjectRich.isEmpty {
                holder.binding.subject.text = makeSpecialPartsBold(notification)
            } else {
                holder.binding.subject.text = subject
            }

            if let file = file, !file.id.isEmpty {
                holder.binding.subject.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleFileTap(_:))))
            }
        }

        if let message = notification.message, !message.isEmpty {
            holder.binding.message.text = message
            holder.binding.message.isHidden = false
        } else {
            holder.binding.message.isHidden = true
        }

        if !notification.icon.isEmpty {
            downloadIcon(icon: notification.icon, itemViewType: holder.binding.icon, context: notificationsActivity)
        }

        viewThemeUtils.platform.colorImageView(holder.binding.icon, colorRole: .onSurfaceVariant)
        viewThemeUtils.platform.colorImageView(holder.binding.dismiss, colorRole: .onSurfaceVariant)
        viewThemeUtils.platform.colorTextView(holder.binding.subject, colorRole: .onSurface)
        viewThemeUtils.platform.colorTextView(holder.binding.message, colorRole: .onSurfaceVariant)
        viewThemeUtils.platform.colorTextView(holder.binding.datetime, colorRole: .onSurfaceVariant)

        setButtons(holder: holder, notification: notification)

        holder.binding.dismiss.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleDismissTap(_:))))
    }

    @objc func handleLinkTap(_ sender: UITapGestureRecognizer) {
        if let notification = sender.view?.tag as? Notification {
            DisplayUtils.startLinkIntent(notificationsActivity, notification.link)
        }
    }

    @objc func handleFileTap(_ sender: UITapGestureRecognizer) {
        if let notification = sender.view?.tag as? Notification, let file = notification.subjectRichParameters[NotificationListAdapter.FILE] {
            let intent = Intent(notificationsActivity, FileDisplayActivity.self)
            intent.action = .view
            intent.putExtra(FileDisplayActivity.KEY_FILE_ID, file.id)
            notificationsActivity.startActivity(intent)
        }
    }

    @objc func handleDismissTap(_ sender: UITapGestureRecognizer) {
        if let notification = sender.view?.tag as? Notification, let holder = sender.view?.superview as? NotificationViewHolder {
            DeleteNotificationTask(client: client, notification: notification, holder: holder, notificationsActivity: notificationsActivity).execute()
        }
    }

    func setButtons(holder: NotificationViewHolder, notification: Notification) {
        holder.binding.buttons.subviews.forEach { $0.removeFromSuperview() }

        let resources = notificationsActivity.resources
        let params = LinearLayout.LayoutParams(width: .wrapContent, height: .wrapContent)
        params.setMargins(
            resources.getDimensionPixelOffset(R.dimen.standard_quarter_margin),
            0,
            resources.getDimensionPixelOffset(R.dimen.standard_half_margin),
            0
        )

        var overflowActions: [Action] = []

        if notification.getActions().count > 0 {
            holder.binding.buttons.isHidden = false
        } else {
            holder.binding.buttons.isHidden = true
        }

        if notification.getActions().count > 2 {
            for action in notification.getActions() {
                if action.primary {
                    let button = MaterialButton(notificationsActivity)
                    button.isAllCaps = false

                    button.setTitle(action.label, for: .normal)
                    button.cornerRadius = resources.getDimension(R.dimen.button_corner_radius)

                    button.layoutParams = params
                    button.contentHorizontalAlignment = .center

                    button.addAction(UIAction { _ in
                        self.setButtonEnabled(holder: holder, enabled: false)

                        if action.type == NotificationListAdapter.ACTION_TYPE_WEB {
                            if let url = URL(string: action.link) {
                                UIApplication.shared.open(url)
                            }
                        } else {
                            NotificationExecuteActionTask(client: client, holder: holder, notification: notification, notificationsActivity: notificationsActivity).execute(action: action)
                        }
                    }, for: .touchUpInside)

                    viewThemeUtils.material.colorMaterialButtonPrimaryFilled(button)
                    holder.binding.buttons.addSubview(button)
                } else {
                    overflowActions.append(action)
                }
            }

            let moreButton = MaterialButton(notificationsActivity)
            moreButton.backgroundColor = UIColor.clear
            viewThemeUtils.material.colorMaterialButtonPrimaryBorderless(moreButton)

            moreButton.isAllCaps = false

            moreButton.setTitle(NSLocalizedString("more", comment: ""), for: .normal)
            moreButton.cornerRadius = resources.getDimension(R.dimen.button_corner_radius)

            moreButton.layoutParams = params
            moreButton.contentHorizontalAlignment = .center

            moreButton.addAction(UIAction { _ in
                let popup = PopupMenu(notificationsActivity, moreButton)

                for action in overflowActions {
                    popup.menu.addItem(withTitle: action.label, action: #selector(self.menuItemClicked(_:)), keyEquivalent: "").target = self
                }

                popup.show()
            }, for: .touchUpInside)

            holder.binding.buttons.addSubview(moreButton)
        } else {
            for action in notification.getActions() {
                let button = MaterialButton(notificationsActivity)

                if action.primary {
                    viewThemeUtils.material.colorMaterialButtonPrimaryFilled(button)
                } else {
                    button.backgroundColor = UIColor.clear
                    viewThemeUtils.material.colorMaterialButtonPrimaryBorderless(button)
                }

                button.isAllCaps = false

                button.setTitle(action.label, for: .normal)
                button.cornerRadius = resources.getDimension(R.dimen.button_corner_radius)

                button.layoutParams = params

                button.addAction(UIAction { _ in
                    self.setButtonEnabled(holder: holder, enabled: false)

                    if action.type == NotificationListAdapter.ACTION_TYPE_WEB {
                        if let url = URL(string: action.link) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        NotificationExecuteActionTask(client: client, holder: holder, notification: notification, notificationsActivity: notificationsActivity).execute(action: action)
                    }
                }, for: .touchUpInside)

                holder.binding.buttons.addSubview(button)
            }
        }
    }

    func makeSpecialPartsBold(notification: Notification) -> NSMutableAttributedString {
        var text = notification.getSubjectRich()
        let ssb = NSMutableAttributedString(string: text)

        var openingBrace = text.firstIndex(of: "{")
        var closingBrace: String.Index
        var replaceablePart: String
        while let opening = openingBrace {
            closingBrace = text.index(after: text[opening...].firstIndex(of: "}")!)
            replaceablePart = String(text[text.index(after: opening)..<text.index(before: closingBrace)])

            if let richObject = notification.subjectRichParameters[replaceablePart] {
                let name = richObject.getName()
                ssb.replaceCharacters(in: NSRange(opening...closingBrace, in: text), with: name)
                text = ssb.string
                closingBrace = text.index(opening, offsetBy: name.count)

                ssb.addAttribute(.font, value: styleSpanBold, range: NSRange(opening..<closingBrace, in: text))
                ssb.addAttribute(.foregroundColor, value: foregroundColorSpanBlack, range: NSRange(opening..<closingBrace, in: text))
            }
            openingBrace = text[closingBrace...].firstIndex(of: "{")
        }

        return ssb
    }

    func removeNotification(holder: NotificationViewHolder) {
        let position = holder.getAdapterPosition()

        if position >= 0 && position < notificationsList.count {
            notificationsList.remove(at: position)
            notifyItemRemoved(position)
            notifyItemRangeChanged(position, notificationsList.count)
        }
    }

    func removeAllNotifications() {
        notificationsList.removeAll()
        notifyDataSetChanged()
    }

    func setButtonEnabled(holder: NotificationViewHolder, enabled: Bool) {
        for i in 0..<holder.binding.buttons.subviews.count {
            holder.binding.buttons.subviews[i].isUserInteractionEnabled = enabled
        }
    }

    func downloadIcon(icon: String, itemViewType: UIImageView, context: UIViewController) {
        let svgCoder = SDImageSVGCoder.shared
        SDImageCodersManager.shared.addCoder(svgCoder)

        if let url = URL(string: icon) {
            itemViewType.sd_setImage(with: url, placeholderImage: UIImage(named: "ic_notification"), options: [.continueInBackground, .retryFailed], context: nil)
        }
    }

    func getItemCount() -> Int {
        return notificationsList.count
    }

    class NotificationViewHolder: UICollectionViewCell {
        var binding: NotificationListItemBinding

        override init(frame: CGRect) {
            self.binding = NotificationListItemBinding()
            super.init(frame: frame)
            self.contentView.addSubview(binding.getRoot())
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
