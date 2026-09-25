import Foundation
import ImageIO
import UIKit

enum RiceImages {
    static func referencedIDs(in node: RiceNode) -> Set<String> {
        var ids: Set<String> = []
        if let asset = node.asset { ids.insert(asset) }
        for child in node.children ?? [] { ids.formUnion(referencedIDs(in: child)) }
        return ids
    }

    static func load(component: RiceComponent, theme: RiceManifest, data: (RiceAsset) -> Data?) -> [String: UIImage] {
        let ids = referencedIDs(in: component.root)
        var result: [String: UIImage] = [:]
        for asset in theme.assets where ids.contains(asset.id) {
            guard let bytes = data(asset), let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { continue }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                           kCGImageSourceThumbnailMaxPixelSize: 768,
                                           kCGImageSourceCreateThumbnailWithTransform: true]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                result[asset.id] = UIImage(cgImage: image)
            }
        }
        return result
    }
}
