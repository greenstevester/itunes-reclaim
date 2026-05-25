import Foundation
import iTunesLibrary

let library: ITLibrary
do {
    library = try ITLibrary(apiVersion: "1.0")
} catch {
    let nsError = error as NSError
    FileHandle.standardError.write(Data("Failed to open ITLibrary.\n".utf8))
    FileHandle.standardError.write(Data("  localizedDescription: \(error.localizedDescription)\n".utf8))
    FileHandle.standardError.write(Data("  domain: \(nsError.domain)  code: \(nsError.code)\n".utf8))
    FileHandle.standardError.write(Data("  userInfo: \(nsError.userInfo)\n".utf8))
    exit(1)
}

func locName(_ t: ITLibMediaItemLocationType) -> String {
    switch t {
    case .file: return "file"
    case .URL: return "URL"
    case .remote: return "remote"
    case .unknown: return "unknown"
    @unknown default: return "other"
    }
}

let all = library.allMediaItems
let songs = all.filter { $0.mediaKind == .kindSong }

var byLocationType: [String: Int] = [:]
var cloud = 0, purchased = 0, drm = 0
var cloudNilLocation = 0, cloudWithLocation = 0
var byKind: [String: Int] = [:]
for s in songs {
    byLocationType[locName(s.locationType), default: 0] += 1
    byKind[s.kind ?? "<nil>", default: 0] += 1
    if s.isCloud {
        cloud += 1
        if s.location == nil { cloudNilLocation += 1 } else { cloudWithLocation += 1 }
    }
    if s.isPurchased { purchased += 1 }
    if s.isDRMProtected { drm += 1 }
}
let nilLocation = songs.filter { $0.location == nil }.count

print("total media items (all kinds): \(all.count)")
print("total songs: \(songs.count)")
print("by locationType: \(byLocationType)")
print("songs with nil location: \(nilLocation)")
print("isCloud songs: \(cloud)  (nil location: \(cloudNilLocation), with location: \(cloudWithLocation))")
print("isPurchased songs: \(purchased)")
print("isDRMProtected songs: \(drm)")

print("---- song 'kind' strings (count desc) ----")
for (k, v) in byKind.sorted(by: { $0.value > $1.value }) {
    print("  \(v)\t\(k)")
}

if let purchases = library.allPlaylists.first(where: { $0.distinguishedKind.rawValue == 16 }) {
    let items = purchases.items
    let pCloud = items.filter { $0.isCloud }.count
    let pNil = items.filter { $0.location == nil }.count
    print("---- distinguished 'Purchases' playlist: \"\(purchases.name)\" ----")
    print("  items: \(items.count)  isCloud: \(pCloud)  nil-location: \(pNil)")
} else {
    print("---- no distinguished 'Purchases' playlist found ----")
}

print("---- up to 12 isCloud examples ----")
for s in songs.filter({ $0.isCloud }).prefix(12) {
    let loc = s.location == nil ? "nil" : "yes"
    print("  cloud=\(s.isCloud) loc=\(loc) locType=\(locName(s.locationType)) purch=\(s.isPurchased) drm=\(s.isDRMProtected) — \(s.artist?.name ?? "?") / \(s.title) [\(s.album.title ?? "?")] kind=\(s.kind ?? "?")")
}

print("---- up to 12 nil-location examples ----")
for s in songs.filter({ $0.location == nil }).prefix(12) {
    print("  cloud=\(s.isCloud) purch=\(s.isPurchased) — \(s.artist?.name ?? "?") / \(s.title) [\(s.album.title ?? "?")] kind=\(s.kind ?? "?")")
}

// Optional filter (passed via `open --args <substring>`): dump every matching
// media item with full fields, so we can see whether a specific (e.g. freshly
// un-downloaded) album appears at all and how it is flagged.
let filter = CommandLine.arguments.dropFirst().joined(separator: " ")
    .trimmingCharacters(in: .whitespaces).lowercased()
if !filter.isEmpty {
    func matches(_ s: ITLibMediaItem) -> Bool {
        [s.title, s.artist?.name ?? "", s.album.title ?? "", s.album.albumArtist ?? ""]
            .contains { $0.lowercased().contains(filter) }
    }
    let hits = all.filter(matches)
    print("==== FILTER \"\(filter)\": \(hits.count) matching media item(s) across all kinds ====")
    for s in hits.prefix(60) {
        let loc = s.location?.path ?? "nil"
        print("  cloud=\(s.isCloud) purch=\(s.isPurchased) drm=\(s.isDRMProtected) locType=\(locName(s.locationType)) kind=\(s.kind ?? "?")")
        print("    \(s.artist?.name ?? "?") / \(s.title) [album: \(s.album.title ?? "?")]  location=\(loc)")
    }
}
