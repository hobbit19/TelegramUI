import Foundation
import AsyncDisplayKit
import Display

final class ItemListSelectableControlNode: ASDisplayNode {
    private let checkNode: CheckNode
    
    init(strokeColor: UIColor, fillColor: UIColor, foregroundColor: UIColor) {
        self.checkNode = CheckNode(strokeColor: strokeColor, fillColor: fillColor, foregroundColor: foregroundColor, style: .plain)
        self.checkNode.isUserInteractionEnabled = false
        
        super.init()
        
        self.addSubnode(self.checkNode)
    }
    
    static func asyncLayout(_ node: ItemListSelectableControlNode?) -> (_ strokeColor: UIColor, _ fillColor: UIColor, _ foregroundColor: UIColor, _ selected: Bool) -> (CGFloat, (CGSize, Bool) -> ItemListSelectableControlNode) {
        return { strokeColor, fillColor, foregroundColor, selected in
            let resultNode: ItemListSelectableControlNode
            if let node = node {
                resultNode = node
            } else {
                resultNode = ItemListSelectableControlNode(strokeColor: strokeColor, fillColor: fillColor, foregroundColor: foregroundColor)
            }
            
            return (45.0, { size, animated in
                
                let checkSize = CGSize(width: 32.0, height: 32.0)
                resultNode.checkNode.frame = CGRect(origin: CGPoint(x: 12.0, y: floor((size.height - checkSize.height) / 2.0)), size: checkSize)
                resultNode.checkNode.setIsChecked(selected, animated: animated)
                return resultNode
            })
        }
    }
}
