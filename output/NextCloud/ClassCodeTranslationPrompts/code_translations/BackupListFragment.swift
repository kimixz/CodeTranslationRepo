
import UIKit
import Foundation

class BackupListFragment: FileFragment, Injectable {
    static let TAG = String(describing: BackupListFragment.self)

    static let FILE_NAMES = "FILE_NAMES"
    static let FILE_NAME = "FILE_NAME"
    static let USER = "USER"
    static let CHECKED_CALENDAR_ITEMS_ARRAY_KEY = "CALENDAR_CHECKED_ITEMS"
    static let CHECKED_CONTACTS_ITEMS_ARRAY_KEY = "CONTACTS_CHECKED_ITEMS"

    private var binding: BackuplistFragmentBinding!

    private var listAdapter: BackupListAdapter!
    private var vCards = [VCard]()
    private var ocFiles = [OCFile]()
    @Inject var accountManager: UserAccountManager!
    @Inject var clientFactory: ClientFactory!
    @Inject var backgroundJobManager: BackgroundJobManager!
    @Inject var viewThemeUtils: ViewThemeUtils!
    private var fileDownloader: TransferManagerConnection?
    private var loadContactsTask: LoadContactsTask?
    private var selectedAccount: ContactsAccount?

    static func newInstance(file: OCFile, user: User) -> BackupListFragment {
        let frag = BackupListFragment()
        let arguments = Bundle()
        arguments.setValue(file, forKey: FILE_NAME)
        arguments.setValue(user, forKey: USER)
        frag.setArguments(arguments)
        
        return frag
    }

    static func newInstance(files: [OCFile], user: User) -> BackupListFragment {
        let frag = BackupListFragment()
        let arguments = Bundle()
        arguments.setValue(files, forKey: FILE_NAMES)
        arguments.setValue(user, forKey: USER)
        frag.setArguments(arguments)
        
        return frag
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        binding = BackuplistFragmentBinding.inflate(inflater, container: container, savedInstanceState: savedInstanceState)
        let view = binding.root

        setHasOptionsMenu(true)

        if let contactsPreferenceActivity = activity as? ContactsPreferenceActivity {
            if let actionBar = contactsPreferenceActivity.supportActionBar {
                viewThemeUtils.files.themeActionBar(context: requireContext(), actionBar: actionBar, titleRes: R.string.actionbar_calendar_contacts_restore)
                actionBar.setDisplayHomeAsUpEnabled(true)
            }
            contactsPreferenceActivity.setDrawerIndicatorEnabled(false)
        }

        if savedInstanceState == nil {
            listAdapter = BackupListAdapter(accountManager: accountManager,
                                            clientFactory: clientFactory,
                                            checkedContactsItems: Set(),
                                            checkedCalendarItems: [String: Int](),
                                            fragment: self,
                                            context: requireContext(),
                                            viewThemeUtils: viewThemeUtils)
        } else {
            var checkedCalendarItems = [String: Int]()
            if let checkedCalendarItemsArray = savedInstanceState?.stringArray(forKey: CHECKED_CALENDAR_ITEMS_ARRAY_KEY) {
                for checkedItem in checkedCalendarItemsArray {
                    checkedCalendarItems[checkedItem] = -1
                }
            }
            if !checkedCalendarItems.isEmpty {
                showRestoreButton(true)
            }

            var checkedContactsItems = Set<Int>()
            if let checkedContactsItemsArray = savedInstanceState?.intArray(forKey: CHECKED_CONTACTS_ITEMS_ARRAY_KEY) {
                for checkedItem in checkedContactsItemsArray {
                    checkedContactsItems.insert(checkedItem)
                }
            }
            if !checkedContactsItems.isEmpty {
                showRestoreButton(true)
            }

            listAdapter = BackupListAdapter(accountManager: accountManager,
                                            clientFactory: clientFactory,
                                            checkedContactsItems: checkedContactsItems,
                                            checkedCalendarItems: checkedCalendarItems,
                                            fragment: self,
                                            context: requireContext(),
                                            viewThemeUtils: viewThemeUtils)
        }

        binding.list.adapter = listAdapter
        binding.list.layoutManager = LinearLayoutManager(context: getContext())

        guard let arguments = getArguments() else {
            return view
        }

        if let file = arguments.getParcelableArgument(key: FILE_NAME, type: OCFile.self) {
            ocFiles.append(file)
        } else if let files = arguments.getParcelableArray(forKey: FILE_NAMES) as? [OCFile] {
            ocFiles.append(contentsOf: files)
        } else {
            return view
        }

        if let user = arguments.getParcelableArgument(key: USER, type: User.self) {
            fileDownloader = TransferManagerConnection(activity: getActivity(), user: user)
            fileDownloader?.registerTransferListener { [weak self] in
                self?.onDownloadUpdate()
            }
            fileDownloader?.bind()
        }

        for file in ocFiles {
            if !file.isDown {
                let request = DownloadRequest(user: user, file: file)
                fileDownloader?.enqueue(request)
            }

            if MimeTypeUtil.isVCard(file) && file.isDown {
                setFile(file)
                loadContactsTask = LoadContactsTask(fragment: self, file: file)
                loadContactsTask?.execute()
            }

            if MimeTypeUtil.isCalendar(file) && file.isDown {
                showLoadingMessage(false)
                listAdapter?.addCalendar(file)
            }
        }

        binding.restoreSelected.setOnClickListener { [weak self] _ in
            guard let self = self else { return }
            if self.checkAndAskForCalendarWritePermission() {
                self.importCalendar()
            }

            if self.listAdapter?.getCheckedContactsIntArray().count ?? 0 > 0 && self.checkAndAskForContactsWritePermission() {
                self.importContacts(selectedAccount: self.selectedAccount)
                return
            }

            Snackbar.make(self.binding.list, R.string.contacts_preferences_import_scheduled, duration: .long).show()

            self.closeFragment()
        }

        viewThemeUtils.material.colorMaterialButtonPrimaryBorderless(button: binding.restoreSelected)

        return view
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        fileDownloader?.unbind()
    }

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        coder.encode(listAdapter.getCheckedCalendarStringArray(), forKey: CHECKED_CALENDAR_ITEMS_ARRAY_KEY)
        coder.encode(listAdapter.getCheckedContactsIntArray(), forKey: CHECKED_CONTACTS_ITEMS_ARRAY_KEY)
    }

    @objc func onMessageEvent(_ event: VCardToggleEvent) {
        if event.getShowRestoreButton() {
            binding.contactlistRestoreSelectedContainer.isHidden = false
        } else {
            binding.contactlistRestoreSelectedContainer.isHidden = true
        }
    }

    func showRestoreButton(show: Bool) {
        binding.contactlistRestoreSelectedContainer.isHidden = !show
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let contactsPreferenceActivity = self.navigationController?.topViewController as? ContactsPreferenceActivity {
            contactsPreferenceActivity.setDrawerIndicatorEnabled(true)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        binding = nil
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let contactsPreferenceActivity = self.activity as? ContactsPreferenceActivity {
            contactsPreferenceActivity.setDrawerIndicatorEnabled(false)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        EventBus.default.register(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
        loadContactsTask?.cancel()
    }

    override func onOptionsItemSelected(_ item: MenuItem) -> Bool {
        var retval: Bool
        let itemId = item.itemId

        if itemId == android.R.id.home {
            closeFragment()
            retval = true
        } else if itemId == R.id.action_select_all {
            item.isChecked = !item.isChecked
            setSelectAllMenuItem(item, item.isChecked)
            listAdapter.selectAll(item.isChecked)
            retval = true
        } else {
            retval = super.onOptionsItemSelected(item)
        }

        return retval
    }

    func showLoadingMessage(_ showIt: Bool) {
        binding.loadingListContainer.isHidden = !showIt
    }

    private func setSelectAllMenuItem(selectAll: MenuItem, checked: Bool) {
        selectAll.isChecked = checked
        if checked {
            selectAll.icon = UIImage(named: "ic_select_none")
        } else {
            selectAll.icon = UIImage(named: "ic_select_all")
        }
    }

    private func importContacts(account: ContactsAccount) {
        backgroundJobManager.startImmediateContactsImport(account.getName(),
                                                          account.getType(),
                                                          getFile().getStoragePath(),
                                                          listAdapter.getCheckedContactsIntArray())

        Snackbar
            .make(
                binding.list,
                R.string.contacts_preferences_import_scheduled,
                Snackbar.LENGTH_LONG
            )
            .show()

        closeFragment()
    }

    private func importCalendar() {
        backgroundJobManager.startImmediateCalendarImport(listAdapter.getCheckedCalendarPathsArray())

        let snackbar = Snackbar.make(
            view: binding.list,
            text: R.string.contacts_preferences_import_scheduled,
            duration: Snackbar.LENGTH_LONG
        )
        snackbar.show()

        closeFragment()
    }

    private func closeFragment() {
        if let contactsPreferenceActivity = self.activity as? ContactsPreferenceActivity {
            contactsPreferenceActivity.onBackPressed()
        }
    }

    private func checkAndAskForContactsWritePermission() -> Bool {
        if !PermissionUtil.checkSelfPermission(context: self.view?.window?.rootViewController, permission: .writeContacts) {
            requestPermissions([.writeContacts], PermissionUtil.PERMISSIONS_WRITE_CONTACTS)
            return false
        } else {
            return true
        }
    }

    private func checkAndAskForCalendarWritePermission() -> Bool {
        if !PermissionUtil.checkSelfPermission(context: self.context, permission: .writeCalendar) {
            requestPermissions([.writeCalendar], PermissionUtil.PERMISSIONS_WRITE_CALENDAR)
            return false
        } else {
            return true
        }
    }

    override func onRequestPermissionsResult(_ requestCode: Int, _ permissions: [String], _ grantResults: [Int]) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if requestCode == PermissionUtil.PERMISSIONS_WRITE_CONTACTS {
            for (index, permission) in permissions.enumerated() {
                if permission.caseInsensitiveCompare(Manifest.permission.WRITE_CONTACTS) == .orderedSame {
                    if grantResults[index] >= 0 {
                        importContacts(selectedAccount)
                    } else {
                        if let view = self.view {
                            Snackbar.make(view, R.string.contactlist_no_permission, Snackbar.LENGTH_LONG).show()
                        } else {
                            Toast.makeText(self.context, R.string.contactlist_no_permission, Toast.LENGTH_LONG).show()
                        }
                    }
                    break
                }
            }
        }

        if requestCode == PermissionUtil.PERMISSIONS_WRITE_CALENDAR {
            for (index, permission) in permissions.enumerated() {
                if permission.caseInsensitiveCompare(Manifest.permission.WRITE_CALENDAR) == .orderedSame {
                    if grantResults[index] >= 0 {
                        importContacts(selectedAccount)
                    } else {
                        if let view = self.view {
                            Snackbar.make(view, R.string.contactlist_no_permission, Snackbar.LENGTH_LONG).show()
                        } else {
                            Toast.makeText(self.context, R.string.contactlist_no_permission, Toast.LENGTH_LONG).show()
                        }
                    }
                    break
                }
            }
        }
    }

    private func onDownloadUpdate(download: Transfer) {
        if let activity = self.activity, download.state == .completed {
            let ocFile = download.file

            if MimeTypeUtil.isVCard(ocFile) {
                setFile(ocFile)
                loadContactsTask = LoadContactsTask(fragment: self, file: ocFile)
                loadContactsTask?.execute()
            }
        }
    }

    func loadVCards(cards: [VCard]) {
        showLoadingMessage(false)
        vCards.removeAll()
        vCards.append(contentsOf: cards)
        listAdapter.replaceVcards(vCards)
    }

    static func getDisplayName(vCard: VCard) -> String {
        if let formattedName = vCard.getFormattedName() {
            return formattedName.getValue()
        } else if let telephoneNumbers = vCard.getTelephoneNumbers(), !telephoneNumbers.isEmpty {
            return telephoneNumbers[0].getText()
        } else if let emails = vCard.getEmails(), !emails.isEmpty {
            return emails[0].getValue()
        }
        
        return ""
    }

    func hasCalendarEntry() -> Bool {
        return listAdapter.hasCalendarEntry()
    }

    func setSelectedAccount(_ account: ContactsAccount) {
        selectedAccount = account
    }
}
