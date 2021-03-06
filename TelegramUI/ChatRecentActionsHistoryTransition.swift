import Foundation
import Display
import TelegramCore
import Postbox

enum ChatRecentActionsEntryContentIndex: Int32 {
    case header = 0
    case content = 1
}

struct ChatRecentActionsEntryId: Hashable, Comparable {
    let eventId: AdminLogEventId
    let contentIndex: ChatRecentActionsEntryContentIndex
    
    static func ==(lhs: ChatRecentActionsEntryId, rhs: ChatRecentActionsEntryId) -> Bool {
        return lhs.eventId == rhs.eventId && lhs.contentIndex == rhs.contentIndex
    }
    
    static func <(lhs: ChatRecentActionsEntryId, rhs: ChatRecentActionsEntryId) -> Bool {
        if lhs.eventId != rhs.eventId {
            return lhs.eventId < rhs.eventId
        } else {
            return lhs.contentIndex.rawValue < rhs.contentIndex.rawValue
        }
    }
    
    var hashValue: Int {
        return self.eventId.hashValue &+ 31 &* self.contentIndex.rawValue.hashValue
    }
}

private func eventNeedsHeader(_ event: AdminLogEvent) -> Bool {
    switch event.action {
        case .changeAbout, .changeUsername, .editMessage, .deleteMessage:
            return true
        case let .updatePinned(message):
            if message != nil {
                return true
            } else {
                return false
            }
        default:
            return false
    }
}

private func appendAttributedText(text: (String, [(Int, NSRange)]), generateEntities: (Int) -> [MessageTextEntityType], to string: inout String, entities: inout [MessageTextEntity]) {
    for (index, range) in text.1 {
        for type in generateEntities(index) {
            entities.append(MessageTextEntity(range: (string.count + range.lowerBound) ..< (string.count + range.upperBound), type: type))
        }
    }
    string.append(text.0)
}

private func appendAttributedText(text: String, withEntities: [MessageTextEntityType], to string: inout String, entities: inout [MessageTextEntity]) {
    for type in withEntities {
        entities.append(MessageTextEntity(range: string.count ..< (string.count + text.count), type: type))
    }
    string.append(text)
}

private func filterOriginalMessageFlags(_ message: Message) -> Message {
    return message.withUpdatedFlags([.Incoming])
}

private func filterMessageChannelPeer(_ peer: Peer) -> Peer {
    if let peer = peer as? TelegramChannel {
        return TelegramChannel(id: peer.id, accessHash: peer.accessHash, title: peer.title, username: peer.username, photo: peer.photo, creationDate: peer.creationDate, version: peer.version, participationStatus: peer.participationStatus, info: .group(TelegramChannelGroupInfo(flags: [])), flags: peer.flags, restrictionInfo: peer.restrictionInfo, adminRights: peer.adminRights, bannedRights: peer.bannedRights, peerGroupId: peer.peerGroupId)
    }
    return peer
}

struct ChatRecentActionsEntry: Comparable, Identifiable {
    let id: ChatRecentActionsEntryId
    let presentationData: ChatPresentationData
    let entry: ChannelAdminEventLogEntry
    
    static func ==(lhs: ChatRecentActionsEntry, rhs: ChatRecentActionsEntry) -> Bool {
        if lhs.id != rhs.id {
            return false
        }
        if lhs.entry != rhs.entry {
            return false
        }
        return true
    }
    
    static func <(lhs: ChatRecentActionsEntry, rhs: ChatRecentActionsEntry) -> Bool {
        if lhs.entry.event.date != rhs.entry.event.date {
            return lhs.entry.event.date < rhs.entry.event.date
        } else {
            return lhs.id < rhs.id
        }
    }
    
    var stableId: ChatRecentActionsEntryId {
        return self.id
    }
    
    func item(account: Account, peer: Peer, controllerInteraction: ChatControllerInteraction) -> ListViewItem {
        switch self.entry.event.action {
            case let .changeTitle(_, new):
                var peers = SimpleDictionary<PeerId, Peer>()
                var author: Peer?
                if let peer = self.entry.peers[self.entry.event.peerId] {
                    author = peer
                    peers[peer.id] = peer
                }
                peers[peer.id] = peer
                
                let action = TelegramMediaActionType.titleUpdated(title: new)
                let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: "", attributes: [], media: [TelegramMediaAction(action: action)], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
            case let .changeAbout(prev, new):
                var peers = SimpleDictionary<PeerId, Peer>()
                var author: Peer?
                if let peer = self.entry.peers[self.entry.event.peerId] {
                    author = peer
                    peers[peer.id] = peer
                }
                peers[peer.id] = peer
                
                switch self.id.contentIndex {
                    case .header:
                        var text: String = ""
                        var entities: [MessageTextEntity] = []
                        if let peer = peer as? TelegramChannel, case .broadcast = peer.info {
                            appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessageChangedChannelAbout(author?.displayTitle ?? ""), generateEntities: { index in
                                if index == 0, let author = author {
                                    return [.TextMention(peerId: author.id)]
                                }
                                return []
                            }, to: &text, entities: &entities)
                        } else {
                            appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessageChangedGroupAbout(author?.displayTitle ?? ""), generateEntities: { index in
                                if index == 0, let author = author {
                                    return [.TextMention(peerId: author.id)]
                                }
                                return []
                            }, to: &text, entities: &entities)
                        }
                        let action = TelegramMediaActionType.customText(text: text, entities: entities)
                        let message = Message(stableId: 0, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: "", attributes: [], media: [TelegramMediaAction(action: action)], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                        return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
                    case .content:
                        let peers = SimpleDictionary<PeerId, Peer>()
                        let attributes: [MessageAttribute] = []
                        let prevMessage = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: prev, attributes: [], media: [], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                        
                        let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: new, attributes: attributes, media: [], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                        return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false), additionalContent: !prev.isEmpty ? .eventLogPreviousDescription(prevMessage) : nil)
                }
            case let .changeUsername(prev, new):
                var peers = SimpleDictionary<PeerId, Peer>()
                var author: Peer?
                if let peer = self.entry.peers[self.entry.event.peerId] {
                    author = peer
                    peers[peer.id] = peer
                }
                
                switch self.id.contentIndex {
                    case .header:
                        var text: String = ""
                        var entities: [MessageTextEntity] = []
                        if let peer = peer as? TelegramChannel, case .broadcast = peer.info {
                            appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessageChangedChannelUsername(author?.displayTitle ?? ""), generateEntities: { index in
                                if index == 0, let author = author {
                                    return [.TextMention(peerId: author.id)]
                                }
                                return []
                            }, to: &text, entities: &entities)
                        } else {
                            appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessageChangedGroupUsername(author?.displayTitle ?? ""), generateEntities: { index in
                                if index == 0, let author = author {
                                    return [.TextMention(peerId: author.id)]
                                }
                                return []
                            }, to: &text, entities: &entities)
                        }
                        let action: TelegramMediaActionType = TelegramMediaActionType.customText(text: text, entities: entities)
                        let message = Message(stableId: 0, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: "", attributes: [], media: [TelegramMediaAction(action: action)], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                        return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
                    case .content:
                        var previousAttributes: [MessageAttribute] = []
                        var attributes: [MessageAttribute] = []
                        
                        let prevText = "https://t.me/\(prev)"
                        previousAttributes.append(TextEntitiesMessageAttribute(entities: [MessageTextEntity(range: 0 ..< prevText.count, type: .Url)]))
                        
                        let text: String
                        if !new.isEmpty {
                            text = "https://t.me/\(new)"
                            attributes.append(TextEntitiesMessageAttribute(entities: [MessageTextEntity(range: 0 ..< text.count, type: .Url)]))
                        } else {
                            text = self.presentationData.strings.Channel_AdminLog_EmptyMessageText
                            attributes.append(TextEntitiesMessageAttribute(entities: [MessageTextEntity(range: 0 ..< text.count, type: .Italic)]))
                        }
                        
                        let prevMessage = Message(stableId: 0, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: prevText, attributes: previousAttributes, media: [], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                        let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: text, attributes: attributes, media: [], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                        return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false), additionalContent: !prev.isEmpty ? .eventLogPreviousLink(prevMessage) : nil)
                }
            case let .changePhoto(_, new):
                var peers = SimpleDictionary<PeerId, Peer>()
                var author: Peer?
                if let peer = self.entry.peers[self.entry.event.peerId] {
                    author = peer
                    peers[peer.id] = peer
                }
                peers[peer.id] = peer
                
                var photo: TelegramMediaImage?
                if !new.isEmpty {
                    photo = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 0), representations: new, reference: nil, partialReference: nil)
                }
                
                let action = TelegramMediaActionType.photoUpdated(image: photo)
                let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: "", attributes: [], media: [TelegramMediaAction(action: action)], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
            case let .toggleInvites(value):
                var peers = SimpleDictionary<PeerId, Peer>()
                var author: Peer?
                if let peer = self.entry.peers[self.entry.event.peerId] {
                    author = peer
                    peers[peer.id] = peer
                }
                var text: String = ""
                var entities: [MessageTextEntity] = []
                if value {
                    appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessageToggleInvitesOn(author?.displayTitle ?? ""), generateEntities: { index in
                        if index == 0, let author = author {
                            return [.TextMention(peerId: author.id)]
                        }
                        return []
                    }, to: &text, entities: &entities)
                } else {
                    appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessageToggleInvitesOff(author?.displayTitle ?? ""), generateEntities: { index in
                        if index == 0, let author = author {
                            return [.TextMention(peerId: author.id)]
                        }
                        return []
                    }, to: &text, entities: &entities)
                }
                let action = TelegramMediaActionType.customText(text: text, entities: entities)
                let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: "", attributes: [], media: [TelegramMediaAction(action: action)], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
            case let .toggleSignatures(value):
                var peers = SimpleDictionary<PeerId, Peer>()
                var author: Peer?
                if let peer = self.entry.peers[self.entry.event.peerId] {
                    author = peer
                    peers[peer.id] = peer
                }
                var text: String = ""
                var entities: [MessageTextEntity] = []
                if value {
                    appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessageToggleSignaturesOn(author?.displayTitle ?? ""), generateEntities: { index in
                        if index == 0, let author = author {
                            return [.TextMention(peerId: author.id)]
                        }
                        return []
                    }, to: &text, entities: &entities)
                } else {
                    appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessageToggleSignaturesOff(author?.displayTitle ?? ""), generateEntities: { index in
                        if index == 0, let author = author {
                            return [.TextMention(peerId: author.id)]
                        }
                        return []
                    }, to: &text, entities: &entities)
                }
                let action = TelegramMediaActionType.customText(text: text, entities: entities)
                let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: "", attributes: [], media: [TelegramMediaAction(action: action)], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
            case let .updatePinned(message):
                switch self.id.contentIndex {
                    case .header:
                        var peers = SimpleDictionary<PeerId, Peer>()
                        var author: Peer?
                        if let peer = self.entry.peers[self.entry.event.peerId] {
                            author = peer
                            peers[peer.id] = peer
                        }
                        var text: String = ""
                        var entities: [MessageTextEntity] = []

                        appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessagePinned(author?.displayTitle ?? ""), generateEntities: { index in
                            if index == 0, let author = author {
                                return [.TextMention(peerId: author.id)]
                            }
                            return []
                        }, to: &text, entities: &entities)
                        
                        let action = TelegramMediaActionType.customText(text: text, entities: entities)
                        let message = Message(stableId: 0, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: "", attributes: [], media: [TelegramMediaAction(action: action)], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                        return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
                    case .content:
                        if let message = message {
                            var peers = SimpleDictionary<PeerId, Peer>()
                            var attributes: [MessageAttribute] = []
                            for attribute in message.attributes {
                                if let attribute = attribute as? TextEntitiesMessageAttribute {
                                    attributes.append(attribute)
                                }
                            }
                            for attribute in attributes {
                                for peerId in attribute.associatedPeerIds {
                                    if let peer = self.entry.peers[peerId] {
                                        peers[peer.id] = peer
                                    }
                                }
                            }
                            let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: message.author, text: message.text, attributes: attributes, media: message.media, peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                            return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
                        } else {
                            var peers = SimpleDictionary<PeerId, Peer>()
                            var author: Peer?
                            if let peer = self.entry.peers[self.entry.event.peerId] {
                                author = peer
                                peers[peer.id] = peer
                            }
                            
                            var text: String = ""
                            var entities: [MessageTextEntity] = []
                            
                            appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessageUnpinned(author?.displayTitle ?? ""), generateEntities: { index in
                                if index == 0, let author = author {
                                    return [.TextMention(peerId: author.id)]
                                }
                                return []
                            }, to: &text, entities: &entities)
                            
                            let action = TelegramMediaActionType.customText(text: text, entities: entities)
                            
                            let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: 0), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: "", attributes: [], media: [TelegramMediaAction(action: action)], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                            return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
                        }
                }
            case let .editMessage(prev, message):
                switch self.id.contentIndex {
                    case .header:
                        var peers = SimpleDictionary<PeerId, Peer>()
                        var author: Peer?
                        if let peer = self.entry.peers[self.entry.event.peerId] {
                            author = peer
                            peers[peer.id] = peer
                        }
                        
                        var text: String = ""
                        var entities: [MessageTextEntity] = []
                        
                        var mediaUpdated = false
                        if prev.media.count == message.media.count {
                            for i in 0 ..< prev.media.count {
                                if !prev.media[i].isEqual(to: message.media[i]) {
                                    mediaUpdated = true
                                    break
                                }
                            }
                        } else {
                            mediaUpdated = true
                        }
                        
                        let titleText: (String, [(Int, NSRange)])
                        if mediaUpdated || message.media.isEmpty {
                            titleText = self.presentationData.strings.Channel_AdminLog_MessageEdited(author?.displayTitle ?? "")
                        } else {
                            titleText = self.presentationData.strings.Channel_AdminLog_CaptionEdited(author?.displayTitle ?? "")
                        }
                        
                        appendAttributedText(text: titleText, generateEntities: { index in
                            if index == 0, let author = author {
                                return [.TextMention(peerId: author.id)]
                            }
                            return []
                        }, to: &text, entities: &entities)
                        
                        let action = TelegramMediaActionType.customText(text: text, entities: entities)
                        
                        let message = Message(stableId: 0, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: "", attributes: [], media: [TelegramMediaAction(action: action)], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                        return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
                    case .content:
                        var peers = SimpleDictionary<PeerId, Peer>()
                        var attributes: [MessageAttribute] = []
                        for attribute in message.attributes {
                            if let attribute = attribute as? TextEntitiesMessageAttribute {
                                attributes.append(attribute)
                            }
                        }
                        for attribute in attributes {
                            for peerId in attribute.associatedPeerIds {
                                if let peer = self.entry.peers[peerId] {
                                    peers[peer.id] = peer
                                }
                            }
                        }
                        let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: message.author, text: message.text, attributes: attributes, media: message.media, peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                        return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: filterOriginalMessageFlags(message), read: true, selection: .none, isAdmin: false), additionalContent: !prev.text.isEmpty || !message.text.isEmpty ? .eventLogPreviousMessage(filterOriginalMessageFlags(prev)) : nil)
                }
            case let .deleteMessage(message):
                switch self.id.contentIndex {
                    case .header:
                        var peers = SimpleDictionary<PeerId, Peer>()
                        var author: Peer?
                        if let peer = self.entry.peers[self.entry.event.peerId] {
                            author = peer
                            peers[peer.id] = peer
                        }
                        peers[peer.id] = peer
                        
                        var text: String = ""
                        var entities: [MessageTextEntity] = []
                        
                        appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessageDeleted(author?.displayTitle ?? ""), generateEntities: { index in
                            if index == 0, let author = author {
                                return [.TextMention(peerId: author.id)]
                            }
                            return []
                        }, to: &text, entities: &entities)
                        
                        let action = TelegramMediaActionType.customText(text: text, entities: entities)
                        
                        let message = Message(stableId: 0, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: "", attributes: [], media: [TelegramMediaAction(action: action)], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                        return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
                    case .content:
                        var peers = SimpleDictionary<PeerId, Peer>()
                        var attributes: [MessageAttribute] = []
                        for attribute in message.attributes {
                            if let attribute = attribute as? TextEntitiesMessageAttribute {
                                attributes.append(attribute)
                            }
                        }
                        for attribute in attributes {
                            for peerId in attribute.associatedPeerIds {
                                if let peer = self.entry.peers[peerId] {
                                    peers[peer.id] = peer
                                }
                            }
                        }
                        for media in message.media {
                            for peerId in media.peerIds {
                                if let peer = self.entry.peers[peerId] {
                                    peers[peer.id] = peer
                                }
                            }
                        }
                        let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: message.author, text: message.text, attributes: attributes, media: message.media, peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                        return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
                }
            case .participantJoin, .participantLeave:
                var peers = SimpleDictionary<PeerId, Peer>()
                var author: Peer?
                if let peer = self.entry.peers[self.entry.event.peerId] {
                    author = peer
                    peers[peer.id] = peer
                }
                peers[peer.id] = peer
                
                let action: TelegramMediaActionType
                if case .participantJoin = self.entry.event.action {
                    action = TelegramMediaActionType.addedMembers(peerIds: [self.entry.event.peerId])
                } else {
                    action = TelegramMediaActionType.removedMembers(peerIds: [self.entry.event.peerId])
                }
                let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: "", attributes: [], media: [TelegramMediaAction(action: action)], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
            case let .participantInvite(participant):
                var peers = SimpleDictionary<PeerId, Peer>()
                var author: Peer?
                if let peer = self.entry.peers[self.entry.event.peerId] {
                    author = peer
                    peers[peer.id] = peer
                }
                peers[peer.id] = peer
                for (_, peer) in participant.peers {
                    peers[peer.id] = peer
                }
                peers[participant.peer.id] = participant.peer
                
                let action: TelegramMediaActionType
                action = TelegramMediaActionType.addedMembers(peerIds: [participant.peer.id])
                let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: "", attributes: [], media: [TelegramMediaAction(action: action)], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
            case let .participantToggleBan(prev, new):
                var peers = SimpleDictionary<PeerId, Peer>()
                var attributes: [MessageAttribute] = []
                
                var author: Peer?
                if let peer = self.entry.peers[self.entry.event.peerId] {
                    author = peer
                    peers[peer.id] = peer
                }
                peers[peer.id] = filterMessageChannelPeer(peer)
                
                var text: String = ""
                var entities: [MessageTextEntity] = []
                
                let isBroadcast: Bool
                if let peer = peer as? TelegramChannel {
                    switch peer.info {
                    case .broadcast:
                        isBroadcast = true
                    case .group:
                        isBroadcast = false
                    }
                } else {
                    isBroadcast = false
                }
                
                if case let .member(_, _, _, prevBanInfo) = prev.participant {
                    if case let .member(_, _, _, newBanInfo) = new.participant {
                        let newFlags = newBanInfo?.rights.flags ?? []
                        
                        var addedRights = newBanInfo?.rights.flags ?? []
                        var removedRights:TelegramChannelBannedRightsFlags = []
                        if let prevBanInfo = prevBanInfo {
                            addedRights = addedRights.subtracting(prevBanInfo.rights.flags)
                            removedRights = prevBanInfo.rights.flags.subtracting(newBanInfo?.rights.flags ?? [])
                        }
                        
                        if (prevBanInfo == nil || !prevBanInfo!.rights.flags.contains(.banReadMessages)) && newFlags.contains(.banReadMessages) {
                            appendAttributedText(text: new.peer.addressName == nil ? self.presentationData.strings.Channel_AdminLog_MessageKickedName(new.peer.displayTitle) : self.presentationData.strings.Channel_AdminLog_MessageKickedNameUsername(new.peer.displayTitle, "@" + new.peer.addressName!), generateEntities: { index in
                                var result: [MessageTextEntityType] = []
                                if index == 0 {
                                    result.append(.TextMention(peerId: new.peer.id))
                                } else if index == 1 {
                                    result.append(.Mention)
                                }
                                return result
                            }, to: &text, entities: &entities)
                            text += "\n"
                        } else if isBroadcast, newBanInfo == nil, prevBanInfo != nil {
                            appendAttributedText(text: new.peer.addressName == nil ? self.presentationData.strings.Channel_AdminLog_MessageUnkickedName(new.peer.displayTitle) : self.presentationData.strings.Channel_AdminLog_MessageUnkickedNameUsername(new.peer.displayTitle, "@" + new.peer.addressName!), generateEntities: { index in
                                var result: [MessageTextEntityType] = []
                                if index == 0 {
                                    result.append(.TextMention(peerId: new.peer.id))
                                } else if index == 1 {
                                    result.append(.Mention)
                                }
                                return result
                            }, to: &text, entities: &entities)
                        } else {
                            appendAttributedText(text: new.peer.addressName == nil ? self.presentationData.strings.Channel_AdminLog_MessageRestrictedName(new.peer.displayTitle) : self.presentationData.strings.Channel_AdminLog_MessageRestrictedNameUsername(new.peer.displayTitle, "@" + new.peer.addressName!), generateEntities: { index in
                                var result: [MessageTextEntityType] = []
                                if index == 0 {
                                    result.append(.TextMention(peerId: new.peer.id))
                                } else if index == 1 {
                                    result.append(.Mention)
                                }
                                return result
                            }, to: &text, entities: &entities)
                            text += "\n"
                            
                            if let newBanInfo = newBanInfo, newBanInfo.rights.untilDate != 0 && newBanInfo.rights.untilDate != Int32.max {
                                let formatter = DateFormatter()
                                formatter.locale = Locale(identifier: self.presentationData.strings.languageCode)
                                formatter.dateFormat = "E, d MMM HH:mm"
                                let dateString = formatter.string(from: Date(timeIntervalSince1970: Double(newBanInfo.rights.untilDate)))
                                
                                if prevBanInfo?.rights.flags != newBanInfo.rights.flags {
                                    text += self.presentationData.strings.Channel_AdminLog_MessageRestrictedUntil(dateString).0
                                } else {
                                    text += self.presentationData.strings.Channel_AdminLog_MessageRestrictedNewSetting(dateString).0
                                }
                                text += "\n"
                            } else {
                                if prevBanInfo?.rights.flags != newBanInfo?.rights.flags {
                                    text += self.presentationData.strings.Channel_AdminLog_MessageRestrictedForever
                                } else {
                                    text += self.presentationData.strings.Channel_AdminLog_MessageRestrictedNewSetting(self.presentationData.strings.Channel_AdminLog_MessageRestrictedForever).0
                                }
                                text += "\n"
                            }
                            
                            let prevFlags = prevBanInfo?.rights.flags ?? []
                            
                            let order: [(TelegramChannelBannedRightsFlags, String)] = [
                                (.banReadMessages, self.presentationData.strings.Channel_AdminLog_BanReadMessages),
                                (.banSendMessages, self.presentationData.strings.Channel_AdminLog_BanSendMessages),
                                (.banSendMedia, self.presentationData.strings.Channel_AdminLog_BanSendMedia),
                                (.banSendStickers, self.presentationData.strings.Channel_AdminLog_BanSendStickers),
                                (.banSendGifs, self.presentationData.strings.Channel_AdminLog_BanSendGifs),
                                (.banEmbedLinks, self.presentationData.strings.Channel_AdminLog_BanEmbedLinks),
                            ]
                            
                            for (flag, string) in order {
                                if addedRights.contains(flag) {
                                    text += "\n-"
                                    appendAttributedText(text: string, withEntities: [.Italic], to: &text, entities: &entities)
                                }
                                if removedRights.contains(flag) {
                                    text += "\n+"
                                    appendAttributedText(text: string, withEntities: [.Italic], to: &text, entities: &entities)
                                }
                            }
                        }
                    }
                }
                
                if !entities.isEmpty {
                    attributes.append(TextEntitiesMessageAttribute(entities: entities))
                }
            
                for attribute in attributes {
                    for peerId in attribute.associatedPeerIds {
                        if let peer = self.entry.peers[peerId] {
                            peers[peer.id] = peer
                        }
                    }
                }
                let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: text, attributes: attributes, media: [], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
            case let .participantToggleAdmin(prev, new):
                var peers = SimpleDictionary<PeerId, Peer>()
                var attributes: [MessageAttribute] = []
                
                var author: Peer?
                if let peer = self.entry.peers[self.entry.event.peerId] {
                    author = peer
                    peers[peer.id] = peer
                }
                peers[peer.id] = filterMessageChannelPeer(peer)
                
                var text: String = ""
                var entities: [MessageTextEntity] = []
                
                appendAttributedText(text: new.peer.addressName == nil ? self.presentationData.strings.Channel_AdminLog_MessagePromotedName(new.peer.displayTitle) : self.presentationData.strings.Channel_AdminLog_MessagePromotedNameUsername(new.peer.displayTitle, "@" + new.peer.addressName!), generateEntities: { index in
                    var result: [MessageTextEntityType] = []
                    if index == 0 {
                        result.append(.TextMention(peerId: new.peer.id))
                    } else if index == 1 {
                        result.append(.Mention)
                    }
                    return result
                }, to: &text, entities: &entities)
                text += "\n"
                
                if case let .member(_, _, prevAdminRights, _) = prev.participant {
                    if case let .member(_, _, newAdminRights, _) = new.participant {
                        let prevFlags = prevAdminRights?.rights.flags ?? []
                        let newFlags = newAdminRights?.rights.flags ?? []
                        
                        let order: [(TelegramChannelAdminRightsFlags, String)]
                        
                        if let peer = peer as? TelegramChannel, case .broadcast = peer.info {
                            order = [
                                (.canChangeInfo, self.presentationData.strings.Channel_AdminLog_CanChangeInfo),
                                (.canPostMessages, self.presentationData.strings.Channel_AdminLog_CanSendMessages),
                                (.canDeleteMessages, self.presentationData.strings.Channel_AdminLog_CanDeleteMessages),
                                (.canEditMessages, self.presentationData.strings.Channel_AdminLog_CanEditMessages),
                                (.canInviteUsers, self.presentationData.strings.Channel_AdminLog_CanInviteUsers),
                                (.canAddAdmins, self.presentationData.strings.Channel_AdminLog_CanAddAdmins)
                            ]
                        } else {
                            order = [
                                (.canChangeInfo, self.presentationData.strings.Channel_AdminLog_CanChangeInfo),
                                (.canDeleteMessages, self.presentationData.strings.Channel_AdminLog_CanDeleteMessages),
                                (.canBanUsers, self.presentationData.strings.Channel_AdminLog_CanBanUsers),
                                (.canPinMessages, self.presentationData.strings.Channel_AdminLog_CanPinMessages),
                                (.canChangeInviteLink, self.presentationData.strings.Channel_AdminLog_CanInviteUsers),
                                (.canAddAdmins, self.presentationData.strings.Channel_AdminLog_CanAddAdmins)
                            ]
                        }
                        
                        for (flag, string) in order {
                            if prevFlags.contains(flag) != newFlags.contains(flag) {
                                text += "\n"
                                if !prevFlags.contains(flag) {
                                    text += "+"
                                } else {
                                    text += "-"
                                }
                                appendAttributedText(text: string, withEntities: [.Italic], to: &text, entities: &entities)
                            }
                        }
                    }
                }
            
                if !entities.isEmpty {
                    attributes.append(TextEntitiesMessageAttribute(entities: entities))
                }
                
                for attribute in attributes {
                    for peerId in attribute.associatedPeerIds {
                        if let peer = self.entry.peers[peerId] {
                            peers[peer.id] = peer
                        }
                    }
                }
                let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: text, attributes: attributes, media: [], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
            case let .changeStickerPack(_, new):
                var peers = SimpleDictionary<PeerId, Peer>()
                var author: Peer?
                if let peer = self.entry.peers[self.entry.event.peerId] {
                    author = peer
                    peers[peer.id] = peer
                }
                var text: String = ""
                var entities: [MessageTextEntity] = []
                
                if new != nil {
                    appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessageChangedGroupStickerPack(author?.displayTitle ?? ""), generateEntities: { index in
                        if index == 0, let author = author {
                            return [.TextMention(peerId: author.id)]
                        }
                        return []
                    }, to: &text, entities: &entities)
                } else {
                    appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessageRemovedGroupStickerPack(author?.displayTitle ?? ""), generateEntities: { index in
                        if index == 0, let author = author {
                            return [.TextMention(peerId: author.id)]
                        }
                        return []
                    }, to: &text, entities: &entities)
                }
                let action = TelegramMediaActionType.customText(text: text, entities: entities)
                
                let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: "", attributes: [], media: [TelegramMediaAction(action: action)], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
            case let .togglePreHistoryHidden(value):
                var peers = SimpleDictionary<PeerId, Peer>()
                var author: Peer?
                if let peer = self.entry.peers[self.entry.event.peerId] {
                    author = peer
                    peers[peer.id] = peer
                }
                
                var text: String = ""
                var entities: [MessageTextEntity] = []
                
                if !value {
                    appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessageGroupPreHistoryVisible(author?.displayTitle ?? ""), generateEntities: { index in
                        if index == 0, let author = author {
                            return [.TextMention(peerId: author.id)]
                        }
                        return []
                    }, to: &text, entities: &entities)
                } else {
                    appendAttributedText(text: self.presentationData.strings.Channel_AdminLog_MessageGroupPreHistoryHidden(author?.displayTitle ?? ""), generateEntities: { index in
                        if index == 0, let author = author {
                            return [.TextMention(peerId: author.id)]
                        }
                        return []
                    }, to: &text, entities: &entities)
                }
                let action = TelegramMediaActionType.customText(text: text, entities: entities)
                
                let message = Message(stableId: self.entry.stableId, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(bitPattern: self.entry.stableId)), globallyUniqueId: self.entry.event.id, groupingKey: nil, groupInfo: nil, timestamp: self.entry.event.date, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, author: author, text: "", attributes: [], media: [TelegramMediaAction(action: action)], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [])
                return ChatMessageItem(presentationData: self.presentationData, account: account, chatLocation: .peer(peer.id), associatedData: ChatMessageItemAssociatedData(automaticDownloadPeerType: .channel, automaticDownloadNetworkType: .cellular, isRecentActions: true), controllerInteraction: controllerInteraction, content: .message(message: message, read: true, selection: .none, isAdmin: false))
        }
    }
}

func chatRecentActionsEntries(entries: [ChannelAdminEventLogEntry], presentationData: ChatPresentationData) -> [ChatRecentActionsEntry] {
    var result: [ChatRecentActionsEntry] = []
    for entry in entries.reversed() {
        result.append(ChatRecentActionsEntry(id: ChatRecentActionsEntryId(eventId: entry.event.id, contentIndex: .content), presentationData: presentationData, entry: entry))
        if eventNeedsHeader(entry.event) {
            result.append(ChatRecentActionsEntry(id: ChatRecentActionsEntryId(eventId: entry.event.id, contentIndex: .header), presentationData: presentationData, entry: entry))
        }
    }
    
    assert(result == result.sorted().reversed())
    return result
}

struct ChatRecentActionsHistoryTransition {
    let filteredEntries: [ChatRecentActionsEntry]
    let type: ChannelAdminEventLogUpdateType
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
    let canLoadEarlier: Bool
    let displayingResults: Bool
    let isEmpty: Bool
}

func chatRecentActionsHistoryPreparedTransition(from fromEntries: [ChatRecentActionsEntry], to toEntries: [ChatRecentActionsEntry], type: ChannelAdminEventLogUpdateType, canLoadEarlier: Bool, displayingResults: Bool, account: Account, peer: Peer, controllerInteraction: ChatControllerInteraction) -> ChatRecentActionsHistoryTransition {
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries)
    
    let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
    let insertions = indicesAndItems.map { ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(account: account, peer: peer, controllerInteraction: controllerInteraction), directionHint: nil) }
    let updates = updateIndices.map { ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(account: account, peer: peer, controllerInteraction: controllerInteraction), directionHint: nil) }
    
    return ChatRecentActionsHistoryTransition(filteredEntries: toEntries, type: type, deletions: deletions, insertions: insertions, updates: updates, canLoadEarlier: canLoadEarlier, displayingResults: displayingResults, isEmpty: toEntries.isEmpty)
}
