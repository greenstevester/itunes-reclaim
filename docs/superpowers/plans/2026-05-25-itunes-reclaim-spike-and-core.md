# itunes-reclaim — Phase 1 (Spike 1 + Core Logic) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify that `iTunesLibrary` exposes cloud-only items (Spike 1), then build and fully test the spike-independent core: a format-agnostic purchase importer and the purchase↔library reconciler.

**Architecture:** A Swift Package (`itunes-reclaim`) with a pure library target `ReclaimCore` (models, normalization, CSV parsing, importer, reconciler — no I/O, no frameworks) and an executable target `reclaim-probe` that links `iTunesLibrary` for the spike. The macOS app, `LibraryReader`, UI, and distribution are deferred to a Phase 2 plan written after Spike 1 resolves.

**Tech Stack:** Swift 5.9+, Swift Package Manager, XCTest, `iTunesLibrary` framework (probe only), macOS 13+.

**Spec:** `docs/superpowers/specs/2026-05-25-itunes-reclaim-design.md` (§6.2 importer, §6.3 reconciler, §9 spikes).

---

## File Structure

- `Package.swift` — package manifest: `ReclaimCore` (library), `ReclaimCoreTests` (tests), `reclaim-probe` (executable, links iTunesLibrary).
- `Sources/ReclaimCore/Models.swift` — `LibraryItem`, `PurchasedItem`, `Bucket`, `ReconResult`, `AlbumStatus`, `AlbumReport`.
- `Sources/ReclaimCore/Normalization.swift` — `normalize(_:)`.
- `Sources/ReclaimCore/CSV.swift` — `parseCSV(_:)`.
- `Sources/ReclaimCore/PurchaseImporter.swift` — `ColumnMapping`, `detectColumns(header:)`, `importPurchases(csv:mapping:)`, `ImportError`.
- `Sources/ReclaimCore/Reconciler.swift` — `Reconciler.reconcile(purchases:library:)`, `rollupByAlbum(_:)`.
- `Sources/reclaim-probe/main.swift` — Spike 1 probe.
- `Tests/ReclaimCoreTests/NormalizationTests.swift`
- `Tests/ReclaimCoreTests/CSVTests.swift`
- `Tests/ReclaimCoreTests/PurchaseImporterTests.swift`
- `Tests/ReclaimCoreTests/ReconcilerTests.swift`
- `docs/spikes/2026-05-25-itunes-library-cloud-visibility.md` — Spike 1 findings (created in Task 1).

---

## Task 1: Spike 1 — does `iTunesLibrary` surface cloud-only items?

This is an **exploratory spike, not TDD.** Its job is to discover the real `iTunesLibrary` API surface and confirm cloud-only items are visible. The probe code below uses the API names I believe are correct (`ITLibrary`, `allMediaItems`, `mediaKind`, `locationType`, `location`); **if they don't compile, adjust them — discovering the exact surface is the point.**

**Files:**
- Create: `Package.swift`
- Create: `Sources/ReclaimCore/Placeholder.swift` (temporary, so the library target has a source file)
- Create: `Sources/reclaim-probe/main.swift`
- Create: `docs/spikes/2026-05-25-itunes-library-cloud-visibility.md`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "itunes-reclaim",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ReclaimCore"),
        .testTarget(name: "ReclaimCoreTests", dependencies: ["ReclaimCore"]),
        .executableTarget(
            name: "reclaim-probe",
            dependencies: ["ReclaimCore"],
            linkerSettings: [.linkedFramework("iTunesLibrary")]
        ),
    ]
)
```

- [ ] **Step 2: Create `Sources/ReclaimCore/Placeholder.swift`** (removed in Task 2)

```swift
// Temporary so the target compiles before Models.swift exists. Deleted in Task 2.
enum ReclaimCorePlaceholder {}
```

- [ ] **Step 3: Create `Sources/reclaim-probe/main.swift`**

```swift
import Foundation
import iTunesLibrary

guard let library = try? ITLibrary(apiVersion: "1.0") else {
    FileHandle.standardError.write(Data("Failed to open ITLibrary — likely a Music-library permission prompt was denied, or the framework needs an entitlement. Note this in the findings doc.\n".utf8))
    exit(1)
}

let songs = library.allMediaItems.filter { $0.mediaKind == .kindSong }

var byLocationType: [String: Int] = [:]
for s in songs {
    let key: String
    switch s.locationType {
    case .file: key = "file"
    case .URL: key = "URL"
    case .remote: key = "remote"
    case .unknown: key = "unknown"
    @unknown default: key = "other"
    }
    byLocationType[key, default: 0] += 1
}

let nilLocation = songs.filter { $0.location == nil }.count

print("total songs: \(songs.count)")
print("by locationType: \(byLocationType)")
print("songs with nil location (download candidates): \(nilLocation)")
print("---- up to 10 examples with nil location ----")
for s in songs.filter({ $0.location == nil }).prefix(10) {
    print("  \(s.artist?.name ?? "?") — \(s.title)  [album: \(s.album.title ?? "?")] kind=\(s.kind ?? "?")")
}
```

- [ ] **Step 4: Build the probe**

Run: `swift build --product reclaim-probe`
Expected: builds. If `import iTunesLibrary` or any property fails, fix the API names (see note at top of this task) and rebuild.

- [ ] **Step 5: Run the probe against the real library** (beta tester #1's Mac)

Run: `swift run reclaim-probe`
Expected: a summary printed. macOS may show a "wants to access Music/Media library" prompt — **allow it**, and note in the findings doc whether a prompt appeared (this informs the Phase 2 permissions handling).

- [ ] **Step 6: Record findings in `docs/spikes/2026-05-25-itunes-library-cloud-visibility.md`**

```markdown
# Spike 1 — iTunesLibrary cloud-only visibility (2026-05-25)

## Question
Does `iTunesLibrary` enumerate cloud-only (not-downloaded) items, and expose a
reliable downloaded-vs-cloud signal?

## What ran
`swift run reclaim-probe` against the author's real Music library.

## Findings
- Permission prompt appeared: <yes/no — exact wording>
- total songs: <n>
- by locationType: <paste>
- songs with nil location: <n>
- The cloud-only signal we will use in Phase 2's LibraryReader: <e.g. `location == nil`, or `locationType == .remote`>

## Decision
- [ ] GREEN: cloud-only items are visible with a usable signal → proceed to Phase 2.
- [ ] RED: cloud-only items are NOT visible → STOP. Re-open the concept with the
      author (the instant-scan tier is not feasible as designed).
```

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/ReclaimCore/Placeholder.swift Sources/reclaim-probe/main.swift docs/spikes/2026-05-25-itunes-library-cloud-visibility.md
git commit -m "chore: add SwiftPM package skeleton and Spike 1 ITLibrary probe"
```

> **GATE:** If Spike 1 is RED, stop here and reconvene with the author. Tasks 2–6 (the importer/reconciler) are still valid for the deep-scan tier and may proceed regardless, but the product shape needs revisiting.

---

## Task 2: Models + `normalize`

**Files:**
- Delete: `Sources/ReclaimCore/Placeholder.swift`
- Create: `Sources/ReclaimCore/Models.swift`
- Create: `Sources/ReclaimCore/Normalization.swift`
- Test: `Tests/ReclaimCoreTests/NormalizationTests.swift`

- [ ] **Step 1: Delete the placeholder**

Run: `rm Sources/ReclaimCore/Placeholder.swift`

- [ ] **Step 2: Create `Sources/ReclaimCore/Models.swift`**

```swift
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
```

- [ ] **Step 3: Write the failing normalization test**

`Tests/ReclaimCoreTests/NormalizationTests.swift`:

```swift
import XCTest
@testable import ReclaimCore

final class NormalizationTests: XCTestCase {
    func testLowercasesAndTrims() {
        XCTAssertEqual(normalize("  Hello World  "), "hello world")
    }
    func testFoldsDiacritics() {
        XCTAssertEqual(normalize("Beyoncé"), "beyonce")
    }
    func testNormalizesAmpersand() {
        XCTAssertEqual(normalize("Simon & Garfunkel"), "simon and garfunkel")
    }
    func testStripsParentheticalNoise() {
        XCTAssertEqual(normalize("Song (Remastered 2011)"), "song")
        XCTAssertEqual(normalize("Album [Deluxe Edition]"), "album")
    }
    func testStripsFeaturing() {
        XCTAssertEqual(normalize("Track feat. Someone"), "track")
        XCTAssertEqual(normalize("Track featuring Someone Else"), "track")
    }
    func testCollapsesPunctuationAndWhitespace() {
        XCTAssertEqual(normalize("Rock'n'Roll!!  Now"), "rock n roll now")
    }
}
```

- [ ] **Step 4: Run it to verify it fails**

Run: `swift test --filter NormalizationTests`
Expected: FAIL — `normalize` is undefined.

- [ ] **Step 5: Create `Sources/ReclaimCore/Normalization.swift`**

```swift
import Foundation

/// Normalizes a title/artist/album for fuzzy matching: lowercase, fold diacritics,
/// `&`→`and`, drop `feat.`/`featuring …` segments, strip parenthetical/bracketed
/// noise, reduce punctuation to spaces, collapse whitespace. Stripping all
/// parentheticals can over-trim a rare title like "(Sittin' On) The Dock of the
/// Bay"; for matching, that trade-off favors recall and is acceptable.
public func normalize(_ s: String) -> String {
    var t = s.lowercased()
    t = t.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
    t = t.replacingOccurrences(of: "&", with: " and ")

    // Drop "feat. ..." / "featuring ..." through end of string.
    if let r = t.range(of: #"\b(feat\.?|featuring)\b.*$"#, options: .regularExpression) {
        t.removeSubrange(r)
    }
    // Remove (...) and [...] groups.
    t = t.replacingOccurrences(of: #"[\(\[][^\)\]]*[\)\]]"#, with: " ", options: .regularExpression)

    // Reduce anything that isn't a letter/number to a space.
    let scalars = t.unicodeScalars.map { scalar -> Character in
        CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
    }
    t = String(scalars)

    // Collapse runs of whitespace and trim.
    t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    return t.trimmingCharacters(in: .whitespaces)
}
```

- [ ] **Step 6: Run it to verify it passes**

Run: `swift test --filter NormalizationTests`
Expected: PASS (all 6).

- [ ] **Step 7: Commit**

```bash
git add Sources/ReclaimCore/Models.swift Sources/ReclaimCore/Normalization.swift Tests/ReclaimCoreTests/NormalizationTests.swift
git rm Sources/ReclaimCore/Placeholder.swift
git commit -m "feat: add core models and matching normalization"
```

---

## Task 3: CSV parser

**Files:**
- Create: `Sources/ReclaimCore/CSV.swift`
- Test: `Tests/ReclaimCoreTests/CSVTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ReclaimCoreTests/CSVTests.swift`:

```swift
import XCTest
@testable import ReclaimCore

final class CSVTests: XCTestCase {
    func testSimpleRows() {
        XCTAssertEqual(parseCSV("a,b,c\n1,2,3"), [["a","b","c"], ["1","2","3"]])
    }
    func testQuotedFieldWithComma() {
        XCTAssertEqual(parseCSV("\"a,b\",c"), [["a,b", "c"]])
    }
    func testEscapedQuotes() {
        XCTAssertEqual(parseCSV("\"she said \"\"hi\"\"\",x"), [["she said \"hi\"", "x"]])
    }
    func testCRLFLineEndings() {
        XCTAssertEqual(parseCSV("a,b\r\n1,2\r\n"), [["a","b"], ["1","2"]])
    }
    func testIgnoresTrailingBlankLine() {
        XCTAssertEqual(parseCSV("a,b\n1,2\n"), [["a","b"], ["1","2"]])
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter CSVTests`
Expected: FAIL — `parseCSV` is undefined.

- [ ] **Step 3: Create `Sources/ReclaimCore/CSV.swift`**

```swift
import Foundation

/// Minimal RFC 4180-ish CSV parser: handles quoted fields, escaped quotes (""),
/// commas inside quotes, and CRLF/LF line endings. Drops fully blank lines.
public func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var record: [String] = []
    var field = ""
    var inQuotes = false
    let chars = Array(text)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if inQuotes {
            if c == "\"" {
                if i + 1 < chars.count && chars[i + 1] == "\"" {
                    field.append("\"")
                    i += 1
                } else {
                    inQuotes = false
                }
            } else {
                field.append(c)
            }
        } else {
            switch c {
            case "\"":
                inQuotes = true
            case ",":
                record.append(field); field = ""
            case "\n":
                record.append(field); field = ""
                rows.append(record); record = []
            case "\r":
                break // part of CRLF; the \n handles the line break
            default:
                field.append(c)
            }
        }
        i += 1
    }
    if !field.isEmpty || !record.isEmpty {
        record.append(field)
        rows.append(record)
    }
    return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --filter CSVTests`
Expected: PASS (all 5).

- [ ] **Step 5: Commit**

```bash
git add Sources/ReclaimCore/CSV.swift Tests/ReclaimCoreTests/CSVTests.swift
git commit -m "feat: add minimal CSV parser"
```

---

## Task 4: Purchase importer (column auto-detect + import)

**Files:**
- Create: `Sources/ReclaimCore/PurchaseImporter.swift`
- Test: `Tests/ReclaimCoreTests/PurchaseImporterTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ReclaimCoreTests/PurchaseImporterTests.swift`:

```swift
import XCTest
@testable import ReclaimCore

final class PurchaseImporterTests: XCTestCase {
    func testDetectsCommonColumns() {
        let m = detectColumns(header: ["Item Title", "Artist Name", "Collection Name", "Purchase Date"])
        XCTAssertEqual(m.title, 0)
        XCTAssertEqual(m.artist, 1)
        XCTAssertEqual(m.album, 2)
        XCTAssertEqual(m.date, 3)
    }

    func testArtistNameDoesNotStealTitleColumn() {
        // "Artist Name" contains "name"; artist is detected first so title falls to "Song".
        let m = detectColumns(header: ["Artist Name", "Song", "Album"])
        XCTAssertEqual(m.artist, 0)
        XCTAssertEqual(m.title, 1)
        XCTAssertEqual(m.album, 2)
    }

    func testImportMapsRowsAndSkipsBlankTitles() throws {
        let csv = "Title,Artist,Album\nSong A,Band,Record\n,Band,Record\nSong B,Band,Record\n"
        let items = try importPurchases(csv: csv)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0], PurchasedItem(title: "Song A", artist: "Band", album: "Record"))
        XCTAssertEqual(items[1].title, "Song B")
    }

    func testHonorsExplicitMapping() throws {
        let csv = "col0,col1\nThe Artist,The Song\n"
        var mapping = ColumnMapping()
        mapping.title = 1
        mapping.artist = 0
        let items = try importPurchases(csv: csv, mapping: mapping)
        XCTAssertEqual(items[0], PurchasedItem(title: "The Song", artist: "The Artist"))
    }

    func testThrowsWhenNoTitleColumn() {
        let csv = "Foo,Bar\n1,2\n"
        XCTAssertThrowsError(try importPurchases(csv: csv)) { error in
            XCTAssertEqual(error as? ImportError, .noTitleColumn)
        }
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter PurchaseImporterTests`
Expected: FAIL — `ColumnMapping`/`detectColumns`/`importPurchases`/`ImportError` undefined.

- [ ] **Step 3: Create `Sources/ReclaimCore/PurchaseImporter.swift`**

```swift
import Foundation

public struct ColumnMapping: Equatable {
    public var title: Int?
    public var artist: Int?
    public var album: Int?
    public var date: Int?
    public var storeID: Int?
    public init() {}
}

public enum ImportError: Error, Equatable {
    case empty
    case noTitleColumn
}

/// Auto-detects column indices from a CSV header. Detection order matters:
/// storeID and artist are claimed before title so a "name"/"item" substring in
/// "Artist Name"/"Item ID" doesn't get mis-assigned to title.
public func detectColumns(header: [String]) -> ColumnMapping {
    let names = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
    var used = Set<Int>()

    func find(_ synonyms: [String]) -> Int? {
        for (i, name) in names.enumerated() where !used.contains(i) && synonyms.contains(name) {
            used.insert(i); return i
        }
        for (i, name) in names.enumerated()
        where !used.contains(i) && synonyms.contains(where: { name.contains($0) }) {
            used.insert(i); return i
        }
        return nil
    }

    var m = ColumnMapping()
    m.storeID = find(["content id", "item id", "adam id", "apple id"])
    m.artist  = find(["artist name", "artist"])
    m.album   = find(["collection name", "album", "collection"])
    m.date    = find(["purchase date", "transaction date", "order date", "date"])
    m.title   = find(["title", "name", "song", "track", "item", "description"])
    return m
}

private let dateFormats = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy"]

private func parseDate(_ raw: String) -> Date? {
    guard !raw.isEmpty else { return nil }
    if let d = ISO8601DateFormatter().date(from: raw) { return d }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    for fmt in dateFormats {
        f.dateFormat = fmt
        if let d = f.date(from: raw) { return d }
    }
    return nil
}

/// Parses a purchases CSV into canonical `PurchasedItem`s. Uses `mapping` if given,
/// otherwise auto-detects. Rows with a blank title are skipped.
public func importPurchases(csv: String, mapping: ColumnMapping? = nil) throws -> [PurchasedItem] {
    let rows = parseCSV(csv)
    guard let header = rows.first else { throw ImportError.empty }
    let map = mapping ?? detectColumns(header: header)
    guard let titleIdx = map.title else { throw ImportError.noTitleColumn }

    func cell(_ row: [String], _ idx: Int?) -> String {
        guard let i = idx, i >= 0, i < row.count else { return "" }
        return row[i].trimmingCharacters(in: .whitespaces)
    }

    return rows.dropFirst().compactMap { row in
        let title = cell(row, titleIdx)
        guard !title.isEmpty else { return nil }
        let store = cell(row, map.storeID)
        return PurchasedItem(
            title: title,
            artist: cell(row, map.artist),
            album: cell(row, map.album),
            purchaseDate: parseDate(cell(row, map.date)),
            storeID: store.isEmpty ? nil : store
        )
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --filter PurchaseImporterTests`
Expected: PASS (all 5).

- [ ] **Step 5: Commit**

```bash
git add Sources/ReclaimCore/PurchaseImporter.swift Tests/ReclaimCoreTests/PurchaseImporterTests.swift
git commit -m "feat: add format-agnostic purchase importer"
```

---

## Task 5: Reconciler — matching + bucketing

Matching rules (spec §6.3): a **strong-key** match (artist+album+title) is confident → `downloaded` if any matched item is downloaded, else `cloudOnly`. A **weak-key** match (artist+title only) is medium-confidence → `uncertain`. No match → `missing`. The bias is to never cry `missing` when a plausible match exists.

**Files:**
- Create: `Sources/ReclaimCore/Reconciler.swift`
- Test: `Tests/ReclaimCoreTests/ReconcilerTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ReclaimCoreTests/ReconcilerTests.swift`:

```swift
import XCTest
@testable import ReclaimCore

final class ReconcilerTests: XCTestCase {
    private func lib(_ title: String, _ artist: String, _ album: String,
                     downloaded: Bool, id: String) -> LibraryItem {
        LibraryItem(title: title, artist: artist, album: album, persistentID: id, isDownloaded: downloaded)
    }

    func testStrongMatchDownloaded() {
        let p = PurchasedItem(title: "Song", artist: "Band", album: "Record")
        let l = [lib("Song", "Band", "Record", downloaded: true, id: "A")]
        let r = Reconciler().reconcile(purchases: [p], library: l)
        XCTAssertEqual(r[0].bucket, .downloaded)
        XCTAssertEqual(r[0].matchedPersistentID, "A")
    }

    func testStrongMatchCloudOnly() {
        let p = PurchasedItem(title: "Song", artist: "Band", album: "Record")
        let l = [lib("Song", "Band", "Record", downloaded: false, id: "A")]
        let r = Reconciler().reconcile(purchases: [p], library: l)
        XCTAssertEqual(r[0].bucket, .cloudOnly)
    }

    func testStrongMatchSurvivesNoiseSuffix() {
        // Purchase title carries a remaster suffix the library lacks.
        let p = PurchasedItem(title: "Song (Remastered 2011)", artist: "Band", album: "Record (Deluxe)")
        let l = [lib("Song", "Band", "Record", downloaded: true, id: "A")]
        let r = Reconciler().reconcile(purchases: [p], library: l)
        XCTAssertEqual(r[0].bucket, .downloaded)
    }

    func testWeakMatchIsUncertain() {
        // Same artist+title, different album → weak match only.
        let p = PurchasedItem(title: "Song", artist: "Band", album: "Greatest Hits")
        let l = [lib("Song", "Band", "Original Album", downloaded: true, id: "A")]
        let r = Reconciler().reconcile(purchases: [p], library: l)
        XCTAssertEqual(r[0].bucket, .uncertain)
        XCTAssertEqual(r[0].matchedPersistentID, "A")
    }

    func testNoMatchIsMissing() {
        let p = PurchasedItem(title: "Ghost", artist: "Nobody", album: "Nowhere")
        let l = [lib("Song", "Band", "Record", downloaded: true, id: "A")]
        let r = Reconciler().reconcile(purchases: [p], library: l)
        XCTAssertEqual(r[0].bucket, .missing)
        XCTAssertNil(r[0].matchedPersistentID)
    }

    func testStrongMatchPrefersDownloadedDuplicate() {
        let p = PurchasedItem(title: "Song", artist: "Band", album: "Record")
        let l = [
            lib("Song", "Band", "Record", downloaded: false, id: "cloud"),
            lib("Song", "Band", "Record", downloaded: true, id: "local"),
        ]
        let r = Reconciler().reconcile(purchases: [p], library: l)
        XCTAssertEqual(r[0].bucket, .downloaded)
        XCTAssertEqual(r[0].matchedPersistentID, "local")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter ReconcilerTests`
Expected: FAIL — `Reconciler` undefined.

- [ ] **Step 3: Create `Sources/ReclaimCore/Reconciler.swift`**

```swift
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
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --filter ReconcilerTests`
Expected: PASS (all 6).

- [ ] **Step 5: Commit**

```bash
git add Sources/ReclaimCore/Reconciler.swift Tests/ReclaimCoreTests/ReconcilerTests.swift
git commit -m "feat: add purchase-to-library reconciler"
```

---

## Task 6: Album rollup

An album is `fullyDownloaded` when every track is downloaded, `fullyMissing` when every track is `missing`, otherwise `partiallyDownloaded` (the "partially on Apple Music" case). Grouping is by normalized (artist, album) of the purchase; the report's `artist`/`album` are the first purchase's original (un-normalized) strings, for display.

**Files:**
- Modify: `Sources/ReclaimCore/Reconciler.swift` (append `rollupByAlbum`)
- Test: `Tests/ReclaimCoreTests/ReconcilerTests.swift` (add a class)

- [ ] **Step 1: Write the failing test**

Append to `Tests/ReclaimCoreTests/ReconcilerTests.swift`:

```swift
final class AlbumRollupTests: XCTestCase {
    private func result(_ title: String, _ album: String, _ bucket: Bucket) -> ReconResult {
        ReconResult(purchase: PurchasedItem(title: title, artist: "Band", album: album),
                    bucket: bucket, matchedPersistentID: nil)
    }

    func testFullyDownloaded() {
        let reports = rollupByAlbum([result("T1", "Rec", .downloaded), result("T2", "Rec", .downloaded)])
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].status, .fullyDownloaded)
        XCTAssertEqual(reports[0].album, "Rec")
    }

    func testFullyMissing() {
        let reports = rollupByAlbum([result("T1", "Rec", .missing), result("T2", "Rec", .missing)])
        XCTAssertEqual(reports[0].status, .fullyMissing)
    }

    func testPartiallyDownloaded() {
        let reports = rollupByAlbum([result("T1", "Rec", .downloaded), result("T2", "Rec", .cloudOnly)])
        XCTAssertEqual(reports[0].status, .partiallyDownloaded)
    }

    func testGroupsSeparateAlbums() {
        let reports = rollupByAlbum([result("T1", "Rec A", .downloaded), result("T2", "Rec B", .missing)])
        XCTAssertEqual(reports.count, 2)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter AlbumRollupTests`
Expected: FAIL — `rollupByAlbum` undefined.

- [ ] **Step 3: Append `rollupByAlbum` to `Sources/ReclaimCore/Reconciler.swift`**

```swift
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
```

- [ ] **Step 4: Run the full suite to verify everything passes**

Run: `swift test`
Expected: PASS — all tests across Normalization, CSV, PurchaseImporter, Reconciler, AlbumRollup.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReclaimCore/Reconciler.swift Tests/ReclaimCoreTests/ReconcilerTests.swift
git commit -m "feat: add album-level rollup of reconciliation results"
```

---

## Done criteria for Phase 1

- Spike 1 findings doc records GREEN/RED with the concrete cloud-only signal to use in Phase 2.
- `swift test` is fully green; `ReclaimCore` parses any reasonable purchases CSV and buckets each purchase against a library snapshot, with album rollup.
- The core is exercisable against the author's real export + a hand-made library fixture (beta-tester-#1 validation).

## Phase 2 (separate plan, written after Spike 1 is GREEN)

`LibraryReader` over the real `iTunesLibrary` surface the spike confirmed; Spike 2 (App Sandbox viability); the SwiftUI app (instant-scan view, deep-scan flow, "Open in Music"); distribution (App Store vs notarized DMG, per Spike 2); then v2's iTunes Lookup store-availability check.
