import Foundation

public struct Reconciler {
    public init() {}

    private func strongKey(_ artist: String, _ album: String, _ title: String) -> String {
        "\(normalize(artist))|\(normalize(album))|\(normalize(title))"
    }
    private func weakKey(_ artist: String, _ title: String) -> String {
        "\(normalize(artist))|\(normalize(title))"
    }

    public func reconcile(purchases: [PurchasedItem], library: [LibraryItem]) -> [ReconResult] {
        var strong: [String: [LibraryItem]] = [:]
        var weak: [String: [LibraryItem]] = [:]
        for item in library {
            strong[strongKey(item.artist, item.album, item.title), default: []].append(item)
            weak[weakKey(item.artist, item.title), default: []].append(item)
        }

        return purchases.map { p in
            if let matches = strong[strongKey(p.artist, p.album, p.title)], !matches.isEmpty {
                let downloaded = matches.first(where: { $0.isDownloaded })
                if let d = downloaded {
                    return ReconResult(purchase: p, bucket: .downloaded, matchedPersistentID: d.persistentID)
                }
                return ReconResult(purchase: p, bucket: .cloudOnly, matchedPersistentID: matches[0].persistentID)
            }
            if let matches = weak[weakKey(p.artist, p.title)], !matches.isEmpty {
                return ReconResult(purchase: p, bucket: .uncertain, matchedPersistentID: matches[0].persistentID)
            }
            return ReconResult(purchase: p, bucket: .missing, matchedPersistentID: nil)
        }
    }
}
