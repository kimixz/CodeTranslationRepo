
protocol ShareeListAdapterListener {
    func copyLink(share: OCShare)
    
    func showSharingMenuActionSheet(share: OCShare)
    
    func copyInternalLink()
    
    func createPublicShareLink()
    
    func createSecureFileDrop()
    
    func requestPasswordForShare(share: OCShare, askForPassword: Bool)
    
    func showPermissionsDialog(share: OCShare)
    
    func showProfileBottomSheet(user: User, shareWith: String)
}
