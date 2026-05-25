import Foundation

public struct LibraryItem: Equatable {
    public let title: String
    public let artist: String
    public let album: String
    public let albumArtist: String
    public let trackNumber: Int?
    public let persistentID: String
    public let kind: String
    public let isDownloaded: Bool

    public init(title: String, artist: String, album: String, albumArtist: String = "",
                trackNumber: Int? = nil, persistentID: String, kind: String = "",
                isDownloaded: Bool) {
        self.title = title; self.artist = artist; self.album = album
        self.albumArtist = albumArtist; self.trackNumber = trackNumber
        self.persistentID = persistentID; self.kind = kind; self.isDownloaded = isDownloaded
    }
}

public struct PurchasedItem: Equatable {
    public let title: String
    public let artist: String
    public let album: String
    public let purchaseDate: Date?
    public let storeID: String?

    public init(title: String, artist: String = "", album: String = "",
                purchaseDate: Date? = nil, storeID: String? = nil) {
        self.title = title; self.artist = artist; self.album = album
        self.purchaseDate = purchaseDate; self.storeID = storeID
    }
}

public enum Bucket: String, Equatable {
    case downloaded, cloudOnly, missing, uncertain
}

public struct ReconResult: Equatable {
    public let purchase: PurchasedItem
    public let bucket: Bucket
    public let matchedPersistentID: String?

    public init(purchase: PurchasedItem, bucket: Bucket, matchedPersistentID: String?) {
        self.purchase = purchase; self.bucket = bucket
        self.matchedPersistentID = matchedPersistentID
    }
}

public enum AlbumStatus: String, Equatable {
    case fullyDownloaded, partiallyDownloaded, fullyMissing
}

public struct AlbumReport: Equatable {
    public let artist: String
    public let album: String
    public let status: AlbumStatus
    public let results: [ReconResult]

    public init(artist: String, album: String, status: AlbumStatus, results: [ReconResult]) {
        self.artist = artist; self.album = album; self.status = status; self.results = results
    }
}
