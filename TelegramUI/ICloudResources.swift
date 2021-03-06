import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

public struct ICloudFileResourceId: MediaResourceId {
    public let urlData: String
    
    public var uniqueId: String {
        return "icloud-\(persistentHash32(self.urlData))"
    }
    
    public var hashValue: Int {
        return self.uniqueId.hashValue
    }
    
    public func isEqual(to: MediaResourceId) -> Bool {
        if let to = to as? ICloudFileResourceId {
            return self.urlData == to.urlData
        } else {
            return false
        }
    }
}

public class ICloudFileResource: TelegramMediaResource {
    public let urlData: String
    
    public init(urlData: String) {
        self.urlData = urlData
    }
    
    public required init(decoder: PostboxDecoder) {
        self.urlData = decoder.decodeStringForKey("url", orElse: "")
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.urlData, forKey: "url")
    }
    
    public var id: MediaResourceId {
        return ICloudFileResourceId(urlData: self.urlData)
    }
    
    public func isEqual(to: TelegramMediaResource) -> Bool {
        if let to = to as? ICloudFileResource {
            if self.urlData != to.urlData {
                return false
            }
            return true
        } else {
            return false
        }
    }
}

struct ICloudFileDescription {
    let urlData: String
    let fileName: String
    let fileSize: Int
}

private func desctiptionWithUrl(_ url: URL) -> ICloudFileDescription? {
    if #available(iOSApplicationExtension 9.0, *) {
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        
        guard let urlData = try? url.bookmarkData(options: URL.BookmarkCreationOptions.suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return nil
        }
        
        guard let values = try? url.resourceValues(forKeys: Set([.fileSizeKey])), let fileSize = values.fileSize else {
            return nil
        }
        
        guard let fileName = (url.lastPathComponent as NSString).removingPercentEncoding else {
            return nil
        }
        
        let result = ICloudFileDescription(urlData: urlData.base64EncodedString(), fileName: fileName, fileSize: fileSize)
        
        url.stopAccessingSecurityScopedResource()
        
        return result
    } else {
        return nil
    }
}

func iCloudFileDescription(_ url: URL) -> Signal<ICloudFileDescription?, NoError> {
    return Signal { subscriber in
        var isRemote = false
        var isCurrent = true
        
        if let values = try? url.resourceValues(forKeys: Set([URLResourceKey.ubiquitousItemDownloadingStatusKey])), let status = values.ubiquitousItemDownloadingStatus {
            isRemote = true
            if status != URLUbiquitousItemDownloadingStatus.current {
                isCurrent = false
            }
        }
        
        if !isRemote || isCurrent {
            subscriber.putNext(desctiptionWithUrl(url))
            subscriber.putCompletion()
            return EmptyDisposable
        } else {
            let query = NSMetadataQuery()
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope, NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope]
            query.predicate = NSPredicate(format: "%K.lastPathComponent == %@", NSMetadataItemFSNameKey, url.lastPathComponent)
            query.valueListAttributes = [NSMetadataItemFSSizeKey]
            
            let observer = NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: OperationQueue.main, using: { notification in
                query.disableUpdates()
                
                guard let metadataItem = query.results.first as? NSMetadataItem else {
                    query.enableUpdates()
                    return
                }
                
                query.stop()
                
                guard let fileSize = metadataItem.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber, fileSize != 0 else {
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                
                subscriber.putNext(desctiptionWithUrl(url))
                subscriber.putCompletion()
            })
            
            query.start()
            
            return ActionDisposable {
                Queue.mainQueue().async {
                    query.stop()
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
    }
}

private final class ICloudFileResourceCopyItem: MediaResourceDataFetchCopyLocalItem {
    private let url: URL
    
    init(url: URL) {
        self.url = url
    }
    
    deinit {
        self.url.stopAccessingSecurityScopedResource()
    }
    
    func copyTo(url: URL) -> Bool {
        var success = true
        do {
            try FileManager.default.copyItem(at: self.url, to: url)
        } catch {
            success = false
        }
        return success
    }
}

func fetchICloudFileResource(resource: ICloudFileResource) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError> {
    return Signal { subscriber in
        subscriber.putNext(.reset)
        
        guard let urlData = Data(base64Encoded: resource.urlData) else {
            subscriber.putCompletion()
            return EmptyDisposable
        }
        
        var bookmarkDataIsStale = false
        guard let resolvedUrl = try? URL(resolvingBookmarkData: urlData, bookmarkDataIsStale: &bookmarkDataIsStale), let url = resolvedUrl else {
            subscriber.putCompletion()
            return EmptyDisposable
        }
        
        var isRemote = false
        var isCurrent = true
        
        if let values = try? url.resourceValues(forKeys: Set([URLResourceKey.ubiquitousItemDownloadingStatusKey])), let status = values.ubiquitousItemDownloadingStatus {
            isRemote = true
            if status != URLUbiquitousItemDownloadingStatus.current {
                isCurrent = false
            }
        }
        
        guard url.startAccessingSecurityScopedResource() else {
            subscriber.putCompletion()
            return EmptyDisposable
        }
        
        if !isRemote || isCurrent {
            //url.stopAccessingSecurityScopedResource()
            
            subscriber.putNext(.copyLocalItem(ICloudFileResourceCopyItem(url: url)))
            subscriber.putCompletion()
            return EmptyDisposable
        }
        
        let fileCoordinator = NSFileCoordinator(filePresenter: nil)
        let fileAccessIntent = NSFileAccessIntent.readingIntent(with: url, options: [.withoutChanges])
        fileCoordinator.coordinate(with: [fileAccessIntent], queue: OperationQueue.main, byAccessor: { error in
            if error == nil {
                //url.stopAccessingSecurityScopedResource()
                
                subscriber.putNext(.copyLocalItem(ICloudFileResourceCopyItem(url: url)))
                subscriber.putCompletion()
            } else {
                subscriber.putCompletion()
            }
        })
        
        return ActionDisposable {
            fileCoordinator.cancel()
        }
    }
}
