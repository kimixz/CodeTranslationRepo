
import UIKit
import MaterialComponents

class OCFileListBottomSheetDialog: MDCBottomSheetController {

    private var binding: FileListActionsBottomSheetFragmentBinding!
    private let actions: OCFileListBottomSheetActions
    private let fileActivity: FileActivity
    private let deviceInfo: DeviceInfo
    private let user: User
    private let file: OCFile
    private let themeUtils: ThemeUtils
    private let viewThemeUtils: ViewThemeUtils
    private let editorUtils: EditorUtils
    private let appScanOptionalFeature: AppScanOptionalFeature

    init(fileActivity: FileActivity,
         actions: OCFileListBottomSheetActions,
         deviceInfo: DeviceInfo,
         user: User,
         file: OCFile,
         themeUtils: ThemeUtils,
         viewThemeUtils: ViewThemeUtils,
         editorUtils: EditorUtils,
         appScanOptionalFeature: AppScanOptionalFeature) {
        self.actions = actions
        self.fileActivity = fileActivity
        self.deviceInfo = deviceInfo
        self.user = user
        self.file = file
        self.themeUtils = themeUtils
        self.viewThemeUtils = viewThemeUtils
        self.editorUtils = editorUtils
        self.appScanOptionalFeature = appScanOptionalFeature
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        binding = FileListActionsBottomSheetFragmentBinding.inflate(getLayoutInflater())
        view = binding.root

        viewThemeUtils.platform.colorImageView(binding.menuIconUploadFiles, colorRole: .primary)
        viewThemeUtils.platform.colorImageView(binding.menuIconUploadFromApp, colorRole: .primary)
        viewThemeUtils.platform.colorImageView(binding.menuIconDirectCameraUpload, colorRole: .primary)
        viewThemeUtils.platform.colorImageView(binding.menuIconScanDocUpload, colorRole: .primary)
        viewThemeUtils.platform.colorImageView(binding.menuIconMkdir, colorRole: .primary)
        viewThemeUtils.platform.colorImageView(binding.menuIconAddFolderInfo, colorRole: .primary)

        binding.addToCloud.text = String(format: NSLocalizedString("add_to_cloud", comment: ""),
                                         themeUtils.getDefaultDisplayNameForRootFolder(context: self))

        if let capability = fileActivity.getCapabilities(),
           capability.getRichDocuments().isTrue(),
           capability.getRichDocumentsDirectEditing().isTrue(),
           capability.getRichDocumentsTemplatesAvailable().isTrue(),
           !file.isEncrypted() {
            binding.templates.isHidden = false
        }

        let json = ArbitraryDataProviderImpl(context: self)
            .getValue(user, key: ArbitraryDataProvider.DIRECT_EDITING)

        if !json.isEmpty,
           !file.isEncrypted() {
            let directEditing = try? JSONDecoder().decode(DirectEditing.self, from: Data(json.utf8))

            if let creators = directEditing?.getCreators(), !creators.isEmpty {
                binding.creatorsContainer.isHidden = false

                for creator in creators.values {
                    let creatorViewBinding = FileListActionsBottomSheetCreatorBinding.inflate(getLayoutInflater())
                    let creatorView = creatorViewBinding.root

                    creatorViewBinding.creatorName.text = String(format: NSLocalizedString("editor_placeholder", comment: ""),
                                                                 NSLocalizedString("create_new", comment: ""),
                                                                 creator.getName())

                    creatorViewBinding.creatorThumbnail.image = MimeTypeUtil.getFileTypeIcon(mimeType: creator.getMimetype(),
                                                                                             extension: creator.getExtension(),
                                                                                             context: creatorViewBinding.creatorThumbnail.context,
                                                                                             viewThemeUtils: viewThemeUtils)

                    creatorView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(creatorTapped(_:))))
                    binding.creators.addSubview(creatorView)
                }
            }
        }

        if !deviceInfo.hasCamera(context: self) {
            binding.menuDirectCameraUpload.isHidden = true
        }

        if editorUtils.isEditorAvailable(user: user, mimeType: MimeTypeUtil.MIMETYPE_TEXT_MARKDOWN),
           let file = file, !file.isEncrypted() {
            if file.getRichWorkspace() == nil || file.getRichWorkspace() != "" {
                binding.menuCreateRichWorkspace.isHidden = true
                binding.menuCreateRichWorkspaceDivider.isHidden = true
            } else {
                binding.menuCreateRichWorkspace.isHidden = false
                binding.menuCreateRichWorkspaceDivider.isHidden = false
            }
        } else {
            binding.menuCreateRichWorkspace.isHidden = true
            binding.menuCreateRichWorkspaceDivider.isHidden = true
        }

        setupClickListener()
        filterActionsForOfflineOperations()
    }

    @objc func creatorTapped(_ sender: UITapGestureRecognizer) {
        if let creatorView = sender.view as? FileListActionsBottomSheetCreatorBinding {
            actions.showTemplate(creator: creator, name: creatorView.creatorName.text ?? "")
            dismiss(animated: true, completion: nil)
        }
    }

    private func setupClickListener() {
        binding.menuCreateRichWorkspace.addTarget(self, action: #selector(createRichWorkspace), for: .touchUpInside)
        binding.menuMkdir.addTarget(self, action: #selector(createFolder), for: .touchUpInside)
        binding.menuUploadFromApp.addTarget(self, action: #selector(uploadFromApp), for: .touchUpInside)
        binding.menuDirectCameraUpload.addTarget(self, action: #selector(directCameraUpload), for: .touchUpInside)

        if appScanOptionalFeature.isAvailable() {
            binding.menuScanDocUpload.addTarget(self, action: #selector(scanDocUpload), for: .touchUpInside)
        } else {
            binding.menuScanDocUpload.isHidden = true
        }

        binding.menuUploadFiles.addTarget(self, action: #selector(uploadFiles), for: .touchUpInside)
        binding.menuNewDocument.addTarget(self, action: #selector(newDocument), for: .touchUpInside)
        binding.menuNewSpreadsheet.addTarget(self, action: #selector(newSpreadsheet), for: .touchUpInside)
        binding.menuNewPresentation.addTarget(self, action: #selector(newPresentation), for: .touchUpInside)
    }

    @objc private func createRichWorkspace() {
        actions.createRichWorkspace()
        dismiss()
    }

    @objc private func createFolder() {
        actions.createFolder()
        dismiss()
    }

    @objc private func uploadFromApp() {
        actions.uploadFromApp()
        dismiss()
    }

    @objc private func directCameraUpload() {
        actions.directCameraUpload()
        dismiss()
    }

    @objc private func scanDocUpload() {
        actions.scanDocUpload()
        dismiss()
    }

    @objc private func uploadFiles() {
        actions.uploadFiles()
        dismiss()
    }

    @objc private func newDocument() {
        actions.newDocument()
        dismiss()
    }

    @objc private func newSpreadsheet() {
        actions.newSpreadsheet()
        dismiss()
    }

    @objc private func newPresentation() {
        actions.newPresentation()
        dismiss()
    }

    private func filterActionsForOfflineOperations() {
        guard let file = file else { return }

        fileActivity.connectivityService.isNetworkAndServerAvailable { result in
            if file.isRootDirectory() {
                return
            }

            if !result || file.isOfflineOperation() {
                binding.menuCreateRichWorkspace.isHidden = true
                binding.menuUploadFromApp.isHidden = true
                binding.menuDirectCameraUpload.isHidden = true
                binding.menuScanDocUpload.isHidden = true
                binding.menuNewDocument.isHidden = true
                binding.menuNewSpreadsheet.isHidden = true
                binding.menuNewPresentation.isHidden = true
                binding.creatorsContainer.isHidden = true
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        binding = nil
    }
}
