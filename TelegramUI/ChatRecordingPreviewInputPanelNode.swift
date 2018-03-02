import Foundation
import AsyncDisplayKit
import Display
import TelegramCore
import Postbox
import SwiftSignalKit

private func generatePauseIcon(_ theme: PresentationTheme) -> UIImage? {
    return generateTintedImage(image: UIImage(bundleImageName: "GlobalMusicPlayer/MinimizedPause"), color: theme.chat.inputPanel.actionControlForegroundColor)
}

private func generatePlayIcon(_ theme: PresentationTheme) -> UIImage? {
    return generateTintedImage(image: UIImage(bundleImageName: "GlobalMusicPlayer/MinimizedPlay"), color: theme.chat.inputPanel.actionControlForegroundColor)
}

final class ChatRecordingPreviewInputPanelNode: ChatInputPanelNode {
    private let deleteButton: HighlightableButtonNode
    private let sendButton: HighlightableButtonNode
    private let playButton: HighlightableButtonNode
    private let pauseButton: HighlightableButtonNode
    private let waveformButton: ASButtonNode
    private let waveformBackgroundNode: ASImageNode
    
    private let waveformNode: AudioWaveformNode
    private let waveformForegroundNode: AudioWaveformNode
    private let waveformScubberNode: MediaPlayerScrubbingNode
    
    private var presentationInterfaceState: ChatPresentationInterfaceState?
    
    private var mediaPlayer: MediaPlayer?
    private let durationLabel: MediaPlayerTimeTextNode
    
    private let statusDisposable = MetaDisposable()
    
    init(theme: PresentationTheme) {
        self.deleteButton = HighlightableButtonNode()
        self.deleteButton.displaysAsynchronously = false
        self.deleteButton.setImage(generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Acessory Panels/MessageSelectionThrash"), color: theme.chat.inputPanel.panelControlAccentColor), for: [])
        
        self.sendButton = HighlightableButtonNode()
        self.sendButton.displaysAsynchronously = false
        self.sendButton.setImage(PresentationResourcesChat.chatInputPanelSendButtonImage(theme), for: [])
        
        self.waveformBackgroundNode = ASImageNode()
        self.waveformBackgroundNode.isLayerBacked = true
        self.waveformBackgroundNode.displaysAsynchronously = false
        self.waveformBackgroundNode.displayWithoutProcessing = true
        self.waveformBackgroundNode.image = generateStretchableFilledCircleImage(diameter: 33.0, color: theme.chat.inputPanel.actionControlFillColor)
        
        self.playButton = HighlightableButtonNode()
        self.playButton.displaysAsynchronously = false
        self.playButton.setImage(generatePlayIcon(theme), for: [])
        self.pauseButton = HighlightableButtonNode()
        self.pauseButton.displaysAsynchronously = false
        self.pauseButton.setImage(generatePauseIcon(theme), for: [])
        self.pauseButton.isHidden = true
        
        self.waveformButton = ASButtonNode()
        
        self.waveformNode = AudioWaveformNode()
        self.waveformNode.isLayerBacked = true
        self.waveformForegroundNode = AudioWaveformNode()
        self.waveformForegroundNode.isLayerBacked = true
        
        self.waveformScubberNode = MediaPlayerScrubbingNode(content: .custom(backgroundNode: self.waveformNode, foregroundContentNode: self.waveformForegroundNode))
        
        self.durationLabel = MediaPlayerTimeTextNode(textColor: theme.chat.inputPanel.actionControlForegroundColor)
        self.durationLabel.alignment = .right
        self.durationLabel.mode = .normal
        
        super.init()
        
        self.addSubnode(self.deleteButton)
        self.addSubnode(self.sendButton)
        self.addSubnode(self.waveformBackgroundNode)
        self.addSubnode(self.waveformScubberNode)
        self.addSubnode(self.playButton)
        self.addSubnode(self.pauseButton)
        self.addSubnode(self.durationLabel)
        self.addSubnode(self.waveformButton)
        
        self.deleteButton.addTarget(self, action: #selector(self.deletePressed), forControlEvents: [.touchUpInside])
        self.sendButton.addTarget(self, action: #selector(self.sendPressed), forControlEvents: [.touchUpInside])
        
        self.waveformButton.addTarget(self, action: #selector(self.waveformPressed), forControlEvents: .touchUpInside)
    }
    
    deinit {
        self.mediaPlayer?.pause()
        self.statusDisposable.dispose()
    }
    
    @objc func buttonPressed() {
        self.interfaceInteraction?.deleteChat()
    }
    
    override func updateLayout(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, maxHeight: CGFloat, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState) -> CGFloat {
        if self.presentationInterfaceState != interfaceState {
            var updateWaveform = false
            if self.presentationInterfaceState?.recordedMediaPreview != interfaceState.recordedMediaPreview {
                updateWaveform = true
            }
            self.presentationInterfaceState = interfaceState
            
            if let recordedMediaPreview = interfaceState.recordedMediaPreview, updateWaveform {
                self.waveformNode.setup(color: interfaceState.theme.chat.inputPanel.actionControlForegroundColor.withAlphaComponent(0.5), waveform: recordedMediaPreview.waveform)
                self.waveformForegroundNode.setup(color: interfaceState.theme.chat.inputPanel.actionControlForegroundColor, waveform: recordedMediaPreview.waveform)
                
                if self.mediaPlayer != nil {
                    self.mediaPlayer?.pause()
                }
                if let account = self.account {
                    let mediaPlayer = MediaPlayer(audioSessionManager: account.telegramApplicationContext.mediaManager.audioSession, postbox: account.postbox, resource: recordedMediaPreview.resource, streamable: false, video: false, preferSoftwareDecoding: false, enableSound: true)
                    self.mediaPlayer = mediaPlayer
                    self.durationLabel.defaultDuration = Double(recordedMediaPreview.duration)
                    self.durationLabel.status = mediaPlayer.status
                    self.waveformScubberNode.status = mediaPlayer.status
                    self.statusDisposable.set((mediaPlayer.status
                        |> deliverOnMainQueue).start(next: { [weak self] status in
                        if let strongSelf = self {
                            switch status.status {
                                case .playing, .buffering(_, true):
                                    strongSelf.playButton.isHidden = true
                                default:
                                    strongSelf.playButton.isHidden = false
                            }
                            strongSelf.pauseButton.isHidden = !strongSelf.playButton.isHidden
                        }
                    }))
                }
            }
        }
        
        let panelHeight: CGFloat = 47.0
        
        transition.updateFrame(node: self.deleteButton, frame: CGRect(origin: CGPoint(x: leftInset, y: -1.0), size: CGSize(width: 48.0, height: 47.0)))
        transition.updateFrame(node: self.sendButton, frame: CGRect(origin: CGPoint(x: width - rightInset - 43.0 - UIScreenPixel, y: -UIScreenPixel), size: CGSize(width: 44.0, height: panelHeight)))
        transition.updateFrame(node: self.playButton, frame: CGRect(origin: CGPoint(x: leftInset + 52.0, y: 10.0), size: CGSize(width: 26.0, height: 26.0)))
        transition.updateFrame(node: self.pauseButton, frame: CGRect(origin: CGPoint(x: leftInset + 50.0, y: 10.0), size: CGSize(width: 26.0, height: 26.0)))
        transition.updateFrame(node: self.waveformBackgroundNode, frame: CGRect(origin: CGPoint(x: leftInset + 45.0, y: 7.0 - UIScreenPixel), size: CGSize(width: width - leftInset - rightInset - 90.0, height: 33.0)))
        transition.updateFrame(node: self.waveformButton, frame: CGRect(origin: CGPoint(x: leftInset + 45.0, y: 0.0), size: CGSize(width: width - leftInset - rightInset - 90.0, height: panelHeight)))
        transition.updateFrame(node: self.waveformScubberNode, frame: CGRect(origin: CGPoint(x: leftInset + 45.0 + 35.0, y: 7.0 + floor((33.0 - 13.0) / 2.0)), size: CGSize(width: width - leftInset - rightInset - 90.0 - 45.0 - 40.0, height: 13.0)))
        transition.updateFrame(node: self.durationLabel, frame: CGRect(origin: CGPoint(x: width - rightInset - 90.0 - 4.0, y: 15.0), size: CGSize(width: 35.0, height: 20.0)))
        
        return panelHeight
    }
    
    @objc func deletePressed() {
        self.interfaceInteraction?.deleteRecordedMedia()
    }
    
    @objc func sendPressed() {
        self.interfaceInteraction?.sendRecordedMedia()
    }
    
    @objc func waveformPressed() {
        self.mediaPlayer?.togglePlayPause()
    }
    
    override func minimalHeight(interfaceState: ChatPresentationInterfaceState) -> CGFloat {
        return 47.0
    }
}
