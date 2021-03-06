import Foundation
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore

class ChatMessageMediaBubbleContentNode: ChatMessageBubbleContentNode {
    override var supportsMosaic: Bool {
        return true
    }
    
    private let interactiveImageNode: ChatMessageInteractiveMediaNode
    private let dateAndStatusNode: ChatMessageDateAndStatusNode
    private var selectionNode: GridMessageSelectionNode?
    private var highlightedState: Bool = false
    
    private var media: Media?
    
    override var visibility: ListViewItemNodeVisibility {
        didSet {
            self.interactiveImageNode.visibility = self.visibility
        }
    }
    
    required init() {
        self.interactiveImageNode = ChatMessageInteractiveMediaNode()
        self.dateAndStatusNode = ChatMessageDateAndStatusNode()
        
        super.init()
        
        self.addSubnode(self.interactiveImageNode)
        
        self.interactiveImageNode.activateLocalContent = { [weak self] in
            if let strongSelf = self {
                if let item = strongSelf.item {
                    let _ = item.controllerInteraction.openMessage(item.message)
                }
            }
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func asyncLayoutContent() -> (_ item: ChatMessageBubbleContentItem, _ layoutConstants: ChatMessageItemLayoutConstants, _ preparePosition: ChatMessageBubblePreparePosition, _ messageSelection: Bool?, _ constrainedSize: CGSize) -> (ChatMessageBubbleContentProperties, CGSize?, CGFloat, (CGSize, ChatMessageBubbleContentPosition) -> (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation) -> Void))) {
        let interactiveImageLayout = self.interactiveImageNode.asyncLayout()
        let statusLayout = self.dateAndStatusNode.asyncLayout()
        
        return { item, layoutConstants, preparePosition, selection, constrainedSize in
            var selectedMedia: Media?
            var automaticDownload: Bool = false
            for media in item.message.media {
                if let telegramImage = media as? TelegramMediaImage {
                    selectedMedia = telegramImage
                    automaticDownload = shouldDownloadMediaAutomatically(settings: item.controllerInteraction.automaticMediaDownloadSettings, peerType: item.associatedData.automaticDownloadPeerType, networkType: item.associatedData.automaticDownloadNetworkType, media: telegramImage)
                } else if let telegramFile = media as? TelegramMediaFile {
                    selectedMedia = telegramFile
                    automaticDownload = shouldDownloadMediaAutomatically(settings: item.controllerInteraction.automaticMediaDownloadSettings, peerType: item.associatedData.automaticDownloadPeerType, networkType: item.associatedData.automaticDownloadNetworkType, media: telegramFile)
                }
            }
            
            let bubbleInsets: UIEdgeInsets
            let sizeCalculation: InteractiveMediaNodeSizeCalculation
            
            switch preparePosition {
                case .linear:
                    if case .color = item.presentationData.theme.wallpaper {
                        bubbleInsets = UIEdgeInsets()
                    } else {
                        bubbleInsets = layoutConstants.image.bubbleInsets
                    }
                    
                    sizeCalculation = .constrained(CGSize(width: constrainedSize.width - bubbleInsets.left - bubbleInsets.right, height: constrainedSize.height))
                case .mosaic:
                    bubbleInsets = UIEdgeInsets()
                    sizeCalculation = .unconstrained
            }
            
            let (unboundSize, initialWidth, refineLayout) = interactiveImageLayout(item.account, item.presentationData.theme.theme, item.presentationData.strings, item.message, selectedMedia!, automaticDownload, item.controllerInteraction.automaticMediaDownloadSettings.autoplayGifs, sizeCalculation, layoutConstants)
            
            var forceFullCorners = false
            if let media = selectedMedia as? TelegramMediaFile, media.isAnimated {
                forceFullCorners = true
            }
            
            let contentProperties = ChatMessageBubbleContentProperties(hidesSimpleAuthorHeader: true, headerSpacing: 7.0, hidesBackground: .emptyWallpaper, forceFullCorners: forceFullCorners, forceAlignment: .none)
            
            return (contentProperties, unboundSize, initialWidth + bubbleInsets.left + bubbleInsets.right, { constrainedSize, position in
                var updatedPosition: ChatMessageBubbleContentPosition = position
                if forceFullCorners, case .linear = updatedPosition {
                    updatedPosition = .linear(top: .None(.None(.None)), bottom: .None(.None(.None)))
                }
                
                let imageCorners = chatMessageBubbleImageContentCorners(relativeContentPosition: updatedPosition, normalRadius: layoutConstants.image.defaultCornerRadius, mergedRadius: layoutConstants.image.mergedCornerRadius, mergedWithAnotherContentRadius: layoutConstants.image.contentMergedCornerRadius)
                
                let (refinedWidth, finishLayout) = refineLayout(CGSize(width: constrainedSize.width - bubbleInsets.left - bubbleInsets.right, height: constrainedSize.height), imageCorners)
                
                return (refinedWidth + bubbleInsets.left + bubbleInsets.right, { boundingWidth in
                    let (imageSize, imageApply) = finishLayout(boundingWidth - bubbleInsets.left - bubbleInsets.right)
                    
                    var edited = false
                    var sentViaBot = false
                    var viewCount: Int?
                    for attribute in item.message.attributes {
                        if let _ = attribute as? EditedMessageAttribute {
                            if case .mosaic = preparePosition {
                            } else {
                                edited = true
                            }
                        } else if let attribute = attribute as? ViewCountMessageAttribute {
                            viewCount = attribute.count
                        } else if let _ = attribute as? InlineBotMessageAttribute {
                            sentViaBot = true
                        }
                    }
                    if let author = item.message.author as? TelegramUser, author.botInfo != nil {
                        sentViaBot = true
                    }
                    
                    let dateText = stringForMessageTimestampStatus(message: item.message, dateTimeFormat: item.presentationData.dateTimeFormat, strings: item.presentationData.strings)
                    
                    let statusType: ChatMessageDateAndStatusType?
                    switch position {
                        case .linear(_, .None):
                            if item.message.effectivelyIncoming(item.account.peerId) {
                                statusType = .ImageIncoming
                            } else {
                                if item.message.flags.contains(.Failed) {
                                    statusType = .ImageOutgoing(.Failed)
                                } else if item.message.flags.isSending && !item.message.isSentOrAcknowledged {
                                    statusType = .ImageOutgoing(.Sending)
                                } else {
                                    statusType = .ImageOutgoing(.Sent(read: item.read))
                                }
                            }
                        case .mosaic:
                            statusType = nil
                        default:
                            statusType = nil
                    }
                    
                    let imageLayoutSize = CGSize(width: imageSize.width + bubbleInsets.left + bubbleInsets.right, height: imageSize.height + bubbleInsets.top + bubbleInsets.bottom)
                    
                    var statusSize = CGSize()
                    var statusApply: ((Bool) -> Void)?
                    
                    if let statusType = statusType {
                        let (size, apply) = statusLayout(item.presentationData.theme, item.presentationData.strings, edited && !sentViaBot, viewCount, dateText, statusType, CGSize(width: 200.0, height: CGFloat.greatestFiniteMagnitude))
                        statusSize = size
                        statusApply = apply
                    }
                    
                    var layoutWidth = imageLayoutSize.width
                    if case .constrained = sizeCalculation {
                        layoutWidth = max(layoutWidth, statusSize.width + bubbleInsets.left + bubbleInsets.right + layoutConstants.image.statusInsets.left + layoutConstants.image.statusInsets.right)
                    }
                    
                    let layoutSize = CGSize(width: layoutWidth, height: imageLayoutSize.height)
                    
                    return (layoutSize, { [weak self] animation in
                        if let strongSelf = self {
                            strongSelf.item = item
                            strongSelf.media = selectedMedia
                            
                            let imageFrame = CGRect(origin: CGPoint(x: bubbleInsets.left, y: bubbleInsets.top), size: imageSize)
                            var transition: ContainedViewLayoutTransition = .immediate
                            if case let .System(duration) = animation {
                                transition = .animated(duration: duration, curve: .spring)
                            }
                            
                            transition.updateFrame(node: strongSelf.interactiveImageNode, frame: imageFrame)
                            
                            if let statusApply = statusApply {
                                if strongSelf.dateAndStatusNode.supernode == nil {
                                    strongSelf.interactiveImageNode.addSubnode(strongSelf.dateAndStatusNode)
                                }
                                var hasAnimation = true
                                if case .None = animation {
                                    hasAnimation = false
                                }
                                statusApply(hasAnimation)
 
                                let dateAndStatusFrame = CGRect(origin: CGPoint(x: layoutSize.width - bubbleInsets.right - layoutConstants.image.statusInsets.right - statusSize.width, y: layoutSize.height -  bubbleInsets.bottom - layoutConstants.image.statusInsets.bottom - statusSize.height), size: statusSize)
                                
                                strongSelf.dateAndStatusNode.frame = dateAndStatusFrame
                                strongSelf.dateAndStatusNode.bounds = CGRect(origin: CGPoint(), size: dateAndStatusFrame.size)
                            } else if strongSelf.dateAndStatusNode.supernode != nil {
                                strongSelf.dateAndStatusNode.removeFromSupernode()
                            }
                            
                            imageApply(transition)
                            
                            if let selection = selection {
                                if let selectionNode = strongSelf.selectionNode {
                                    selectionNode.frame = imageFrame
                                    selectionNode.updateSelected(selection, animated: animation.isAnimated)
                                } else {
                                    let selectionNode = GridMessageSelectionNode(theme: item.presentationData.theme.theme, toggle: { value in
                                        item.controllerInteraction.toggleMessagesSelection([item.message.id], value)
                                    })
                                    strongSelf.selectionNode = selectionNode
                                    strongSelf.addSubnode(selectionNode)
                                    selectionNode.frame = imageFrame
                                    selectionNode.updateSelected(selection, animated: false)
                                    if animation.isAnimated {
                                        selectionNode.animateIn()
                                    }
                                }
                            } else if let selectionNode = strongSelf.selectionNode {
                                strongSelf.selectionNode = nil
                                if animation.isAnimated {
                                    selectionNode.animateOut(completion: { [weak selectionNode] in
                                        selectionNode?.removeFromSupernode()
                                    })
                                } else {
                                    selectionNode.removeFromSupernode()
                                }
                            }
                        }
                    })
                })
            })
        }
    }
    
    override func transitionNode(messageId: MessageId, media: Media) -> (ASDisplayNode, () -> UIView?)? {
        if self.item?.message.id == messageId, let currentMedia = self.media, currentMedia.isEqual(to: media) {
            let interactiveImageNode = self.interactiveImageNode
            return (self.interactiveImageNode, { [weak interactiveImageNode] in
                return interactiveImageNode?.view.snapshotContentTree(unhide: true)
            })
        }
        return nil
    }
    
    override func peekPreviewContent(at point: CGPoint) -> (Message, ChatMessagePeekPreviewContent)? {
        if let message = self.item?.message, let currentMedia = self.media, !message.containsSecretMedia {
            if self.interactiveImageNode.frame.contains(point), self.interactiveImageNode.isReadyForInteractivePreview() {
                return (message, .media(currentMedia))
            }
        }
        return nil
    }
    
    override func updateHiddenMedia(_ media: [Media]?) -> Bool {
        var mediaHidden = false
        if let currentMedia = self.media, let media = media {
            for item in media {
                if item.isSemanticallyEqual(to: currentMedia) {
                    mediaHidden = true
                    break
                }
            }
        }
        
        self.interactiveImageNode.isHidden = mediaHidden
        return mediaHidden
    }
    
    override func tapActionAtPoint(_ point: CGPoint) -> ChatMessageBubbleContentTapAction {
        return .none
    }
    
    override func animateInsertion(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
    }
    
    override func animateAdded(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
    }
    
    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false)
    }
    
    override func animateInsertionIntoBubble(_ duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
    }
    
    override func updateHighlightedState(animated: Bool) -> Bool {
        guard let item = self.item else {
            return false
        }
        let highlighted = item.controllerInteraction.highlightedState?.messageStableId == item.message.stableId
        
        if self.highlightedState != highlighted {
            self.highlightedState = highlighted
            
            if highlighted {
                self.interactiveImageNode.setOverlayColor(item.presentationData.theme.theme.chat.bubble.mediaHighlightOverlayColor, animated: false)
            } else {
                self.interactiveImageNode.setOverlayColor(nil, animated: animated)
            }
        }
        
        return false
    }
}
