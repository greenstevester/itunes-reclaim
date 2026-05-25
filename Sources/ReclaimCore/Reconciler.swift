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

/// Groups results by normalized (artist, album) and assigns an album-level status.
/// Report order follows first appearance of each album in `results`.
public func rollupByAlbum(_ results: [ReconResult]) -> [AlbumReport] {
    var order: [String] = []
    var groups: [String: [ReconResult]] = [:]
    for r in results {
        let key = "\(normalize(r.purchase.artist))|\(normalize(r.purchase.album))"
        if groups[key] == nil { order.append(key) }
        groups[key, default: []].append(r)
    }
    return order.map { key in
        let group = groups[key]!
        let status: AlbumStatus
        if group.allSatisfy({ $0.bucket == .downloaded }) {
            status = .fullyDownloaded
        } else if group.allSatisfy({ $0.bucket == .missing }) {
            status = .fullyMissing
        } else {
            status = .partiallyDownloaded
        }
        return AlbumReport(artist: group[0].purchase.artist,
                           album: group[0].purchase.album,
                           status: status,
                           results: group)
    }
}
