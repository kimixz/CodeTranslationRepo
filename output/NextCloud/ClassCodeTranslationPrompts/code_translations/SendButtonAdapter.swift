
import UIKit

class SendButtonAdapter: NSObject, UICollectionViewDataSource, UITableViewDelegate {
    
    private var sendButtonDataList: [SendButtonData]
    private var clickListener: ClickListener?
    
    init(sendButtonDataList: [SendButtonData], clickListener: ClickListener?) {
        self.sendButtonDataList = sendButtonDataList
        self.clickListener = clickListener
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return sendButtonDataList.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "SendButtonCell", for: indexPath) as! ViewHolder
        cell.bind(item: sendButtonDataList[indexPath.row])
        cell.bind(clickListener: clickListener)
        return cell
    }
    
    class ViewHolder: UICollectionViewCell {
        
        private var binding: SendButtonBinding!
        private var clickListener: ClickListener?
        private var sendButtonDataData: SendButtonData?
        
        func bind(item: SendButtonData) {
            sendButtonDataData = item
            binding.sendButtonIcon.image = item.getDrawable()
            binding.sendButtonText.text = item.getTitle()
        }
        
        func bind(clickListener: ClickListener?) {
            self.clickListener = clickListener
            self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onClick(_:))))
        }
        
        @objc func onClick(_ sender: UITapGestureRecognizer) {
            if let data = sendButtonDataData {
                clickListener?.onClick(sendButtonDataData: data)
            }
        }
    }
    
    protocol ClickListener {
        func onClick(sendButtonDataData: SendButtonData)
    }
}
