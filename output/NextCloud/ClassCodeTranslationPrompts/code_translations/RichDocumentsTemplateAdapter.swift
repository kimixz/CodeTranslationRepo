
import UIKit
import Glide

class RichDocumentsTemplateAdapter: UICollectionView, UICollectionViewDataSource, UICollectionViewDelegate {
    
    private var templateList: [Template] = []
    private var clickListener: ClickListener?
    private var context: Context
    private var type: ChooseRichDocumentsTemplateDialogFragment.Type
    private var currentAccountProvider: CurrentAccountProvider
    private var clientFactory: ClientFactory
    private var selectedTemplate: Template?
    private var viewThemeUtils: ViewThemeUtils
    
    init(type: ChooseRichDocumentsTemplateDialogFragment.Type,
         clickListener: ClickListener?,
         context: Context,
         currentAccountProvider: CurrentAccountProvider,
         clientFactory: ClientFactory,
         viewThemeUtils: ViewThemeUtils) {
        self.clickListener = clickListener
        self.type = type
        self.context = context
        self.currentAccountProvider = currentAccountProvider
        self.clientFactory = clientFactory
        self.viewThemeUtils = viewThemeUtils
        super.init(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        self.dataSource = self
        self.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return templateList.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "RichDocumentsTemplateAdapterViewHolder", for: indexPath) as! ViewHolder
        cell.setData(template: templateList[indexPath.row])
        return cell
    }
    
    func setTemplateList(_ templateList: [Template]) {
        self.templateList = templateList
    }
    
    func setTemplateAsActive(template: Template) {
        selectedTemplate = template
        reloadData()
    }
    
    func getSelectedTemplate() -> Template? {
        return selectedTemplate
    }
    
    class ViewHolder: UICollectionViewCell {
        
        private var binding: TemplateButtonBinding!
        private var template: Template?
        
        func bind(_ binding: TemplateButtonBinding) {
            self.binding = binding
            viewThemeUtils.files.themeTemplateCardView(binding.templateContainer)
            contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onClick)))
        }
        
        @objc func onClick() {
            if let clickListener = clickListener {
                clickListener.onClick(template: template)
            }
        }
        
        func setData(template: Template) {
            self.template = template
            
            let placeholder: Int
            
            switch type {
            case .DOCUMENT:
                placeholder = R.drawable.file_doc
            case .SPREADSHEET:
                placeholder = R.drawable.file_xls
            case .PRESENTATION:
                placeholder = R.drawable.file_ppt
            default:
                placeholder = R.drawable.file
            }
            
            Glide.with(context)
                .using(CustomGlideStreamLoader(user: currentAccountProvider.getUser(), clientFactory: clientFactory))
                .load(template.getThumbnailLink())
                .placeholder(placeholder)
                .error(placeholder)
                .into(binding.template)
            
            binding.templateName.text = template.getName()
            binding.templateContainer.isChecked = (template == selectedTemplate)
        }
    }
    
    protocol ClickListener {
        func onClick(template: Template?)
    }
}
