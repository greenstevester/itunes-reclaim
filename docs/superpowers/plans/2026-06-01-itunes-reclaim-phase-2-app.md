---
title: itunes-reclaim — Phase 2 (SwiftUI App) Implementation Plan
date: 2026-06-01
status: ready for implementation
---

# itunes-reclaim — Phase 2 (SwiftUI App) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

---

## ⚠️ LOCAL EXPORT PROCESSING CHECKLIST

**These steps cannot be performed remotely — they require the author's Mac, the Music
library, and the Apple Data Export ZIP. No cloud agent can do them for you.**

- [ ] **Request the export** at [privacy.apple.com](https://privacy.apple.com) →
  "Request a copy of your data" → select **iTunes** (or "App Store, iTunes, iBooks").
  Expect up to **7 days** before the download link arrives by email.
- [ ] **Download and extract** the ZIP when the email arrives.
- [ ] **Locate the purchases CSV** — typically
  `iTunes/iTunes_-_Item_Purchases.csv` inside the ZIP.
- [ ] **Run the reconcile demo** against your real Music library (requires the Phase 1
  probe bundle to already be built via `scripts/run-probe.sh`):

  ```bash
  # From the repo root on your Mac
  ./scripts/run-probe.sh "$(pwd)/path/to/iTunes_-_Item_Purchases.csv"
  ```

  This launches the signed probe bundle, loads your Music library via `ITLibrary`,
  parses the CSV through `ReclaimCore.importPurchases` + `Reconciler`, and prints every
  purchase bucketed as `[DOWNLOADED]` / `[CLOUDONLY]` / `[MISSING]` / `[UNCERTAIN]`,
  followed by the album rollup. The `[MISSING]` rows are your lost purchases.
- [ ] **Capture the output** (copy/paste or `tee`) for comparison once the Phase 2 app
  is built. The Phase 2 app will surface the same results in a GUI.

---

**Goal:** Build the macOS SwiftUI app on top of Phase 1's `ReclaimCore` (26 tests, green)
and the two spikes. Deliverables: (a) `LibraryReader` wrapping `iTunesLibrary`; (b) the
deep-scan flow — guided export-explainer panel, CSV drop → `PurchaseImporter` → `Reconciler`
→ bucketed album/track results with "Open in Music" actions; (c) a Mac App Store–ready
signed bundle. The instant-scan tier is an open product decision documented in Task 8.

**Architecture:** Four units from the spec (§6), now all realised:

```
[ITLibrary] ──► LibraryReader ──────────────────────────────────┐
                                                                 ▼
dropped CSV ──► PurchaseImporter ──► Reconciler ──► [AlbumReport] ──► ResultsView
                     ▲                    ▲
              ColumnMappingView     (ReclaimCore — unchanged)
```

**Spike outcomes carried forward:**

- **Spike 1 (INCONCLUSIVE on cloud-only):** `ITLibrary` works only from a
  LaunchServices-launched signed `.app` (bare `swift run` → `NSCocoaErrorDomain 4097`).
  `isDownloaded` is derived from `location != nil && locationType == .file`. Purchase
  detection uses the `kind` string (e.g. `"Purchased AAC audio file"`). The `isCloud`
  and `isPurchased` flags are **not populated** — do not use them.
  **Cloud-only detection is unvalidated**: the author's library has no Sync Library /
  iCloud Music Library, so no cloud-only items were present to observe. The signal
  must be retested on a library with an active Apple Music subscription before
  cloud-only results are surfaced to users.
- **Spike 2 (GREEN):** App Sandbox with `com.apple.security.assets.music.read-only`
  is sufficient — Mac App Store route is viable.

**Distribution:** Mac App Store (primary). Developer-ID notarized DMG (fallback).

**Privacy:** No network calls in v1. `privacy.apple.com` is opened in the user's browser
via `NSWorkspace` — the app makes no outbound connections. "Open in Music" deep links
are handled locally by Music.app.

**Spec:** `docs/superpowers/specs/2026-05-25-itunes-reclaim-design.md`.

---

## File Structure (new and modified files)

### Modified
- `Sources/ReclaimCore/Models.swift` — rename `LibraryItem` → `LibraryTrack` **(Task 0)**
- `Sources/ReclaimCore/Reconciler.swift` — update parameter type to `[LibraryTrack]`
- `Tests/ReclaimCoreTests/ReconcilerTests.swift` — update helper return type
- `Sources/reclaim-probe/main.swift` — rename `toLibraryItem` → `toLibraryTrack`
- `Package.swift` — add `ReclaimLibrary` + `ReclaimLibraryTests` targets

### New — `ReclaimLibrary` target
- `Sources/ReclaimLibrary/LibraryReader.swift` — `LibraryError`, `mapItem`, `LibraryReader`
- `Tests/ReclaimLibraryTests/LibraryReaderTests.swift`

### New — App (Xcode project + SwiftUI sources)
- `itunes-reclaim.xcodeproj/` — Xcode app project (Task 2, manual)
- `itunes-reclaim/itunes-reclaim.entitlements`
- `itunes-reclaim/Info.plist`
- `Sources/App/iOSTunesReclaimApp.swift` — `@main` entry point
- `Sources/App/ContentView.swift` — top-level shell, library-load on `.task`
- `Sources/App/DeepScanViewModel.swift` — `@Observable` state machine
- `Sources/App/DeepScanView.swift` — export explainer + file drop zone
- `Sources/App/ColumnMappingViewModel.swift`
- `Sources/App/ColumnMappingView.swift`
- `Sources/App/ResultsViewModel.swift`
- `Sources/App/ResultsView.swift`
- `Sources/App/OpenInMusicAction.swift`
- `Sources/App/ErrorView.swift`
- `Tests/AppTests/DeepScanViewModelTests.swift`
- `Tests/AppTests/ColumnMappingViewModelTests.swift`
- `Tests/AppTests/ResultsViewModelTests.swift`
- `Tests/AppTests/OpenInMusicActionTests.swift`

---

## Task 0: Rename `LibraryItem` → `LibraryTrack` [MUST BE FIRST]

SwiftUI transitively imports `DeveloperToolsSupport`, which defines its own `LibraryItem`
type (used for Xcode Previews / Library content). Any file with both `import SwiftUI` and
`import ReclaimCore` hits an ambiguous-type compiler error and must qualify every use as
`ReclaimCore.LibraryItem`. Renaming to `LibraryTrack` eliminates the collision before any
SwiftUI code is written. It is also a more precise domain term ("track" is what Music.app
calls a song-kind media item).

**Files:**
- Modify: `Sources/ReclaimCore/Models.swift`
- Modify: `Sources/ReclaimCore/Reconciler.swift`
- Modify: `Tests/ReclaimCoreTests/ReconcilerTests.swift`
- Modify: `Sources/reclaim-probe/main.swift`

- [ ] **Step 1: Rename the struct in `Sources/ReclaimCore/Models.swift`**

Replace the `LibraryItem` struct with:

```swift
public struct LibraryTrack: Equatable {
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
```

All other types (`PurchasedItem`, `Bucket`, `ReconResult`, `AlbumStatus`, `AlbumReport`) are
unchanged.

- [ ] **Step 2: Update `Sources/ReclaimCore/Reconciler.swift`**

`reconcile(purchases:library:)` signature becomes:

```swift
public func reconcile(purchases: [PurchasedItem], library: [LibraryTrack]) -> [ReconResult]
```

Update the internal variable declarations (`for item in library` etc.) to match.

- [ ] **Step 3: Update `Tests/ReclaimCoreTests/ReconcilerTests.swift`**

Replace the helper at the top of `ReconcilerTests`:

```swift
private func lib(_ title: String, _ artist: String, _ album: String,
                 downloaded: Bool, id: String) -> LibraryTrack {
    LibraryTrack(title: title, artist: artist, album: album,
                 persistentID: id, isDownloaded: downloaded)
}
```

- [ ] **Step 4: Update `Sources/reclaim-probe/main.swift`**

Rename `toLibraryItem` → `toLibraryTrack` (return type and two call sites):

```swift
func toLibraryTrack(_ s: ITLibMediaItem) -> LibraryTrack {
    LibraryTrack(
        title: s.title,
        artist: s.artist?.name ?? "",
        album: s.album.title ?? "",
        albumArtist: s.album.albumArtist ?? "",
        trackNumber: s.trackNumber > 0 ? s.trackNumber : nil,
        persistentID: s.persistentID.stringValue,
        kind: s.kind ?? "",
        isDownloaded: s.location != nil
    )
}
```

Update the two call sites: `songs.map(toLibraryItem)` → `songs.map(toLibraryTrack)`.

- [ ] **Step 5: Verify no regressions**

```bash
swift test --filter ReclaimCoreTests
```
Expected: all 26 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ReclaimCore/Models.swift Sources/ReclaimCore/Reconciler.swift \
        Tests/ReclaimCoreTests/ReconcilerTests.swift Sources/reclaim-probe/main.swift
git commit -m "refactor: rename LibraryItem to LibraryTrack to avoid SwiftUI DeveloperToolsSupport collision"
```

---

## Task 1: `ReclaimLibrary` SPM Target — `LibraryReader`

`LibraryReader` wraps `ITLibrary` and produces `[LibraryTrack]`. The key design choice is
extracting the field translation into an `internal` pure function `mapItem(...)` that takes
**plain primitive values** (not `ITLibMediaItem`). This lets `ReclaimLibraryTests` unit-test
the download/purchase signal derivation without TCC access or a real library. The actual
`ITLibrary(apiVersion:)` call stays in `LibraryReader.fetchAll()` and is tested only via
the existing `scripts/run-probe.sh` integration path.

> **Reference:** `Sources/reclaim-probe/main.swift: toLibraryTrack(_:)` (after Task 0) is
> the validated mapping prototype. `LibraryReader` formalises it.

> **Cloud-only detection caveat (Spike 1 INCONCLUSIVE):** `isDownloaded` is structurally
> derived from `location != nil && locationTypeIsFile`. A library track with
> `isDownloaded == false` _should_ be cloud-only (in the library, not downloaded), but this
> was never observed on the author's Mac (no Sync Library). **Before surfacing cloud-only
> results to users**, retest on a Mac with an active Apple Music subscription and Sync
> Library enabled. Confirm that cloud-only tracks: (1) appear in `allMediaItems`, (2) have
> `location == nil`, (3) have `locationType != .file`. Until then, treat
> `isDownloaded == false` library results as suspect.

> **Do not use `isCloud` or `isPurchased`:** Spike 1 confirmed these flags are unpopulated
> by the modern Music backend. Derive purchase status from the `kind` string
> (`kind.lowercased().contains("purchased")`), and download status from
> `location`/`locationType`.

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ReclaimLibrary/LibraryReader.swift`
- Create: `Tests/ReclaimLibraryTests/LibraryReaderTests.swift`

- [ ] **Step 1: Update `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "itunes-reclaim",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ReclaimCore"),
        .testTarget(name: "ReclaimCoreTests", dependencies: ["ReclaimCore"]),
        .target(
            name: "ReclaimLibrary",
            dependencies: ["ReclaimCore"],
            linkerSettings: [.linkedFramework("iTunesLibrary")]
        ),
        .testTarget(name: "ReclaimLibraryTests", dependencies: ["ReclaimLibrary"]),
        .executableTarget(
            name: "reclaim-probe",
            dependencies: ["ReclaimCore"],
            linkerSettings: [.linkedFramework("iTunesLibrary")]
        ),
    ]
)
```

- [ ] **Step 2: Write the failing test**

`Tests/ReclaimLibraryTests/LibraryReaderTests.swift`:

```swift
import XCTest
@testable import ReclaimLibrary
import ReclaimCore

final class LibraryReaderMappingTests: XCTestCase {

    func testIsDownloadedWhenLocationPresentAndFile() {
        let t = mapItem(title: "S", artist: "A", album: "B", albumArtist: "",
                        trackNumber: 1, persistentID: "abc", kind: "MPEG audio file",
                        location: URL(string: "file:///Music/s.mp3"), locationTypeIsFile: true)
        XCTAssertTrue(t.isDownloaded)
    }

    func testIsNotDownloadedWhenLocationNil() {
        let t = mapItem(title: "S", artist: "A", album: "B", albumArtist: "",
                        trackNumber: nil, persistentID: "def", kind: "Purchased AAC audio file",
                        location: nil, locationTypeIsFile: false)
        XCTAssertFalse(t.isDownloaded)
    }

    func testIsNotDownloadedWhenLocationPresentButNotFile() {
        // A URL-type (non-file) location is not a local download.
        let t = mapItem(title: "S", artist: "A", album: "B", albumArtist: "",
                        trackNumber: nil, persistentID: "ghi", kind: "AAC audio file",
                        location: URL(string: "http://example.com/s.m4a"),
                        locationTypeIsFile: false)
        XCTAssertFalse(t.isDownloaded)
    }

    func testKindStringIsPreserved() {
        let t = mapItem(title: "S", artist: "A", album: "B", albumArtist: "",
                        trackNumber: nil, persistentID: "x",
                        kind: "Purchased AAC audio file",
                        location: URL(string: "file:///f.m4a"), locationTypeIsFile: true)
        XCTAssertEqual(t.kind, "Purchased AAC audio file")
    }

    func testPersistentIDIsPreserved() {
        let t = mapItem(title: "S", artist: "A", album: "B", albumArtist: "",
                        trackNumber: nil, persistentID: "unique99", kind: "",
                        location: nil, locationTypeIsFile: false)
        XCTAssertEqual(t.persistentID, "unique99")
    }

    func testZeroTrackNumberBecomesNil() {
        let t = mapItem(title: "S", artist: "A", album: "B", albumArtist: "",
                        trackNumber: 0, persistentID: "x", kind: "",
                        location: URL(string: "file:///f.mp3"), locationTypeIsFile: true)
        XCTAssertNil(t.trackNumber)
    }

    func testPositiveTrackNumberIsKept() {
        let t = mapItem(title: "S", artist: "A", album: "B", albumArtist: "",
                        trackNumber: 3, persistentID: "x", kind: "",
                        location: URL(string: "file:///f.mp3"), locationTypeIsFile: true)
        XCTAssertEqual(t.trackNumber, 3)
    }
}
```

- [ ] **Step 3: Run it to verify it fails**

```bash
swift test --filter ReclaimLibraryTests
```
Expected: FAIL — `ReclaimLibrary` module does not exist.

Note: if this target can't link `iTunesLibrary` on a non-Mac CI host, skip it with
`--skip ReclaimLibraryTests`. The mapping logic is still covered by these unit tests on
any Mac dev machine.

- [ ] **Step 4: Create `Sources/ReclaimLibrary/LibraryReader.swift`**

```swift
import Foundation
import iTunesLibrary
import ReclaimCore

// MARK: - Error

public enum LibraryError: Error, Equatable {
    /// NSCocoaErrorDomain 4097: process is not running from a LaunchServices-launched
    /// .app bundle. End-users never see this; developers do if they run `swift run`.
    case xpcUnavailable
    /// TCC denied: user declined the "Media & Apple Music" system prompt, or access
    /// was revoked in System Settings → Privacy & Security → Media & Apple Music.
    case accessDenied
    /// Any other failure (description preserved for display).
    case openFailed(String)
}

// MARK: - Mapping (internal — unit-tested in ReclaimLibraryTests without TCC)

/// Translates raw ITLibMediaItem field values into a LibraryTrack.
///
/// isDownloaded rule (validated by Spike 1 on a non-Sync-Library Mac):
///   `location != nil && locationTypeIsFile`
///
/// Cloud-only detection (location == nil, track present in library) is structurally
/// represented by isDownloaded == false, but has NOT been observed on a real
/// cloud-only item. Revalidate on a Sync Library library before relying on it.
func mapItem(
    title: String,
    artist: String,
    album: String,
    albumArtist: String,
    trackNumber: Int?,
    persistentID: String,
    kind: String,
    location: URL?,
    locationTypeIsFile: Bool
) -> LibraryTrack {
    LibraryTrack(
        title: title,
        artist: artist,
        album: album,
        albumArtist: albumArtist,
        trackNumber: (trackNumber ?? 0) > 0 ? trackNumber : nil,
        persistentID: persistentID,
        kind: kind,
        isDownloaded: location != nil && locationTypeIsFile
    )
}

// MARK: - LibraryReader

/// Wraps ITLibrary and returns every song-kind media item as a [LibraryTrack].
/// Must be called from inside a LaunchServices-launched .app bundle; a bare
/// swift run returns LibraryError.xpcUnavailable (NSCocoaErrorDomain 4097).
public struct LibraryReader {
    public init() {}

    public func fetchAll() throws -> [LibraryTrack] {
        let itLib: ITLibrary
        do {
            itLib = try ITLibrary(apiVersion: "1.0")
        } catch let e as NSError {
            switch (e.domain, e.code) {
            case (NSCocoaErrorDomain, 4097): throw LibraryError.xpcUnavailable
            case (NSCocoaErrorDomain, 257):  throw LibraryError.accessDenied
            default: throw LibraryError.openFailed(e.localizedDescription)
            }
        }

        return itLib.allMediaItems
            .filter { $0.mediaKind == .kindSong }
            .map { item in
                mapItem(
                    title: item.title,
                    artist: item.artist?.name ?? "",
                    album: item.album.title ?? "",
                    albumArtist: item.album.albumArtist ?? "",
                    trackNumber: item.trackNumber > 0 ? item.trackNumber : nil,
                    persistentID: item.persistentID.stringValue,
                    kind: item.kind ?? "",
                    location: item.location,
                    locationTypeIsFile: item.locationType == .file
                )
            }
    }
}
```

- [ ] **Step 5: Run the tests**

```bash
swift test --filter ReclaimLibraryTests
```
Expected: all 7 `LibraryReaderMappingTests` PASS.

- [ ] **Step 6: Run the full suite**

```bash
swift test
```
Expected: 26 ReclaimCoreTests + 7 ReclaimLibraryTests = **33 PASS**.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/ReclaimLibrary/ Tests/ReclaimLibraryTests/
git commit -m "feat: add ReclaimLibrary target with LibraryReader and mapItem unit tests"
```

---

## Task 2: Xcode App Project Skeleton + Entitlements

This task is a **manual Xcode GUI step** — there is no Swift source to write. It is a
prerequisite for Tasks 3–7 because App Sandbox entitlements and code signing cannot be
configured from SwiftPM alone.

**Files to be created (by Xcode):**
- `itunes-reclaim.xcodeproj/`
- `itunes-reclaim/itunes-reclaim.entitlements`
- `itunes-reclaim/Info.plist`

- [ ] **Step 1: Create a new macOS app in Xcode**

File → New → Project → macOS → App. Set:
- **Product Name:** `itunes-reclaim` (update to final product name when decided)
- **Bundle Identifier:** `<your-reverse-domain>.itunes-reclaim`
  (e.g. `net.greensill.itunes-reclaim` based on the author's domain)
- **Interface:** SwiftUI
- **Language:** Swift
- **Minimum Deployment:** macOS 13.0

Save the project at the **repo root** so that `itunes-reclaim.xcodeproj/` sits alongside
the existing `Package.swift`, `Sources/`, `Tests/`.

- [ ] **Step 2: Add the local Swift Package as a dependency**

In Xcode: File → Add Package Dependencies → "Add Local…" → select the repo root (the
directory containing `Package.swift`). Add both **ReclaimCore** and **ReclaimLibrary** to
the app target's "Frameworks, Libraries, and Embedded Content."

- [ ] **Step 3: Configure entitlements (Signing & Capabilities)**

In the app target → "Signing & Capabilities":
- Add **App Sandbox** capability (enabled).
- Under Sandbox, enable **Media Library** read-only.

The resulting `.entitlements` file must contain:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.assets.music.read-only</key>
    <true/>
</dict>
</plist>
```

This is the exact entitlement set used in Spike 2 (GREEN) — no additional entitlements
are needed.

- [ ] **Step 4: Add `NSAppleMusicUsageDescription` to `Info.plist`**

```xml
<key>NSAppleMusicUsageDescription</key>
<string>itunes-reclaim reads your Music library to identify which purchased
tracks are downloaded, cloud-only, or missing from your library.
Nothing leaves your Mac.</string>
```

Adjust the string to match the final product name once branding is decided.

- [ ] **Step 5: Point the app target at `Sources/App/`**

Delete the auto-generated `ContentView.swift` and `<AppName>App.swift` stubs Xcode
created. Add a folder reference to `Sources/App/` in the Xcode target's source list.

- [ ] **Step 6: Commit project files**

```bash
git add itunes-reclaim.xcodeproj/ itunes-reclaim/
git commit -m "chore: add Xcode app project with App Sandbox and music.read-only entitlements"
```

---

## Task 3: App Entry Point + `DeepScanViewModel`

`DeepScanViewModel` is the central state machine for the import→reconcile pipeline. It
receives `[LibraryTrack]` injected at startup (from `LibraryReader.fetchAll()`) and
processes a user-dropped CSV file through `ReclaimCore.importPurchases` →
`Reconciler.reconcile` → `rollupByAlbum`. Keeping the library tracks as an injected
property makes the view model fully testable without ITLibrary.

**Files:**
- Create: `Sources/App/iOSTunesReclaimApp.swift`
- Create: `Sources/App/ContentView.swift`
- Create: `Sources/App/DeepScanViewModel.swift`
- Create: `Tests/AppTests/DeepScanViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AppTests/DeepScanViewModelTests.swift`:

```swift
import XCTest
@testable import App   // module name = Xcode target name; adjust if different
import ReclaimCore

@MainActor
final class DeepScanViewModelTests: XCTestCase {

    private var vm: DeepScanViewModel!

    override func setUp() {
        vm = DeepScanViewModel()
        vm.libraryTracks = [
            LibraryTrack(title: "Song A", artist: "Band", album: "Record",
                         persistentID: "1", isDownloaded: true),
            LibraryTrack(title: "Song B", artist: "Band", album: "Record",
                         persistentID: "2", isDownloaded: false),
        ]
    }

    func testInitialPhaseIsIdle() {
        XCTAssertEqual(vm.phase, .idle)
    }

    func testAutoDetectableCSVMovesToDone() async throws {
        let url = try tempCSV("Title,Artist,Album\nSong A,Band,Record\nMissing,Nobody,Nowhere\n")
        await vm.processFile(url)
        guard case .done(let reports) = vm.phase else {
            XCTFail("Expected .done, got \(vm.phase)"); return
        }
        XCTAssertEqual(reports.count, 2)
    }

    func testUnreadableFileFails() async {
        await vm.processFile(URL(fileURLWithPath: "/nonexistent/x.csv"))
        guard case .failed = vm.phase else { XCTFail("Expected .failed"); return }
    }

    func testOpaqueHeaderMovesToAwaitingMapping() async throws {
        let url = try tempCSV("Col1,Col2,Col3\nv,v,v\n")
        await vm.processFile(url)
        guard case .awaitingMapping = vm.phase else {
            XCTFail("Expected .awaitingMapping"); return
        }
    }

    func testResetRestoresIdle() async throws {
        let url = try tempCSV("Title,Artist\nSong A,Band\n")
        await vm.processFile(url)
        vm.reset()
        XCTAssertEqual(vm.phase, .idle)
    }

    private func tempCSV(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".csv")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL — `DeepScanViewModel` is undefined.

- [ ] **Step 3: Create `Sources/App/DeepScanViewModel.swift`**

```swift
import Foundation
import Observation
import ReclaimCore

@MainActor
@Observable
public final class DeepScanViewModel {

    public enum Phase: Equatable {
        case idle
        case importing
        case awaitingMapping(header: [String], rawRows: [[String]])
        case reconciling
        case done([AlbumReport])
        case failed(String)
    }

    public var phase: Phase = .idle
    /// Injected at app startup from LibraryReader.fetchAll().
    public var libraryTracks: [LibraryTrack] = []
    /// Retained across awaitingMapping → applyMapping round-trip.
    private(set) var pendingCSVText: String = ""

    public init() {}

    public func processFile(_ url: URL) async {
        phase = .importing
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            phase = .failed("Could not read the file. Make sure it isn't open elsewhere.")
            return
        }
        await processText(text)
    }

    private func processText(_ text: String) async {
        let rows = parseCSV(text)
        guard let header = rows.first, !header.isEmpty else {
            phase = .failed("The file appears to be empty.")
            return
        }
        let mapping = detectColumns(header: header)
        pendingCSVText = text
        if mapping.title != nil {
            await reconcile(csvText: text, mapping: mapping)
        } else {
            phase = .awaitingMapping(header: header, rawRows: Array(rows.dropFirst()))
        }
    }

    /// Called from ColumnMappingView once the user has confirmed column assignments.
    public func applyMapping(_ mapping: ColumnMapping) async {
        await reconcile(csvText: pendingCSVText, mapping: mapping)
    }

    public func reset() {
        phase = .idle
        pendingCSVText = ""
    }

    private func reconcile(csvText: String, mapping: ColumnMapping) async {
        phase = .reconciling
        do {
            let purchases = try importPurchases(csv: csvText, mapping: mapping)
            guard !purchases.isEmpty else {
                phase = .failed("No purchases were found in the file.")
                return
            }
            let results = Reconciler().reconcile(purchases: purchases, library: libraryTracks)
            phase = .done(rollupByAlbum(results))
        } catch ImportError.noTitleColumn {
            phase = .failed("No title column found. Use the column-mapping step to assign one.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 4: Create `Sources/App/iOSTunesReclaimApp.swift`**

```swift
import SwiftUI

@main
struct ItunesReclaimApp: App {  // rename to match final product name
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 5: Create `Sources/App/ContentView.swift`** (shell — filled out by Tasks 4–7)

```swift
import SwiftUI
import ReclaimCore
import ReclaimLibrary

struct ContentView: View {
    @State private var vm = DeepScanViewModel()
    @State private var libraryError: LibraryError?

    var body: some View {
        Group {
            if let error = libraryError {
                libraryErrorView(error)
            } else {
                switch vm.phase {
                case .idle, .importing, .awaitingMapping, .reconciling:
                    DeepScanView(vm: vm)
                case .done(let reports):
                    ResultsView(reports: reports, reset: vm.reset)
                case .failed(let msg):
                    ErrorView(message: msg, reset: vm.reset)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .task { await loadLibrary() }
    }

    private func loadLibrary() async {
        do {
            vm.libraryTracks = try LibraryReader().fetchAll()
        } catch let e as LibraryError {
            libraryError = e
        } catch {}
    }

    @ViewBuilder
    private func libraryErrorView(_ error: LibraryError) -> some View {
        switch error {
        case .accessDenied:
            LibraryPermissionView()
        default:
            ErrorView(
                message: "Could not open the Music library (\(error)). Try restarting the app.",
                reset: { libraryError = nil }
            )
        }
    }
}
```

- [ ] **Step 6: Run the tests**

```bash
swift test --filter DeepScanViewModelTests
```
Expected: all 5 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/App/DeepScanViewModel.swift Sources/App/iOSTunesReclaimApp.swift \
        Sources/App/ContentView.swift Tests/AppTests/DeepScanViewModelTests.swift
git commit -m "feat: add DeepScanViewModel state machine and app entry point shell"
```

---

## Task 4: Deep-Scan Guided Panel (Export Explainer + File Drop)

`DeepScanView` is a single-screen guided panel that (a) explains the Apple Data Export
request process, links to `privacy.apple.com`, and sets the ~7-day expectation; (b)
provides a file-drop zone and "Open File…" button that accepts `.csv` / `.txt`; (c) shows
spinner states for `.importing` and `.reconciling`.

The `privacy.apple.com` link is opened via `NSWorkspace.shared.open(_:)` — the app itself
makes no network request; the system browser handles it. This satisfies the v1 privacy
principle and is App Review–safe.

**Files:**
- Create: `Sources/App/DeepScanView.swift`

- [ ] **Step 1: Create `Sources/App/DeepScanView.swift`**

```swift
import SwiftUI
import UniformTypeIdentifiers
import ReclaimCore

struct DeepScanView: View {
    @Bindable var vm: DeepScanViewModel
    @State private var isTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                explainerSection
                switch vm.phase {
                case .idle:
                    dropZoneSection
                case .importing:
                    progressView("Reading file…")
                case .awaitingMapping(let header, _):
                    ColumnMappingView(header: header, vm: vm)
                case .reconciling:
                    progressView("Comparing with your library…")
                case .done, .failed:
                    EmptyView()  // ContentView routes away from here
                }
            }
            .padding(32)
        }
    }

    // MARK: Explainer

    private var explainerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find your missing purchases")
                .font(.title).bold()
            Text("""
                To see which purchased tracks are missing from your library, you need \
                your Apple purchase history. Request a copy at **privacy.apple.com** — \
                look for **iTunes** (or "App Store, iTunes, iBooks") in the data types list.
                """)
                .fixedSize(horizontal: false, vertical: true)
            Text("The export takes up to 7 days and arrives by email as a ZIP file.")
                .foregroundStyle(.secondary)
            Button("Request my data at privacy.apple.com") {
                NSWorkspace.shared.open(URL(string: "https://privacy.apple.com")!)
            }
            .buttonStyle(.link)
            Divider().padding(.top, 4)
            Text("Once you have the ZIP, extract it, locate the purchases CSV \
                 (typically inside an **iTunes/** folder), and drop it below.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    // MARK: Drop Zone

    private var dropZoneSection: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .frame(height: 130)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 32))
                            .foregroundStyle(isTargeted ? .accent : .secondary)
                        Text("Drop your purchases CSV here")
                            .foregroundStyle(.secondary)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
            Button("Or choose a file…") { openFilePanel() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    private func progressView(_ label: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(label).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }

    // MARK: Helpers

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, _ in
            guard let url else { return }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: dest)
            Task { @MainActor in await vm.processFile(dest) }
        }
        return true
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await vm.processFile(url) }
        }
    }
}
```

No automated test for the view itself — test the drop-zone manually by dropping the Apple
export CSV on the running app. `DeepScanViewModelTests` covers the underlying state machine.

- [ ] **Step 2: Commit**

```bash
git add Sources/App/DeepScanView.swift
git commit -m "feat: add deep-scan guided panel with export explainer and file drop zone"
```

---

## Task 5: Column-Mapping Fallback

When `detectColumns` can't identify a title column, `DeepScanViewModel` transitions to
`.awaitingMapping`. `ColumnMappingView` presents a picker per field (title / artist /
album / date / storeID) so the user can assign them manually. On confirm,
`vm.applyMapping(_:)` resumes the pipeline.

**Files:**
- Create: `Sources/App/ColumnMappingViewModel.swift`
- Create: `Sources/App/ColumnMappingView.swift`
- Create: `Tests/AppTests/ColumnMappingViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/AppTests/ColumnMappingViewModelTests.swift`:

```swift
import XCTest
@testable import App
import ReclaimCore

final class ColumnMappingViewModelTests: XCTestCase {

    func testInitWithHeader() {
        let vm = ColumnMappingViewModel(header: ["track", "performer", "disc"])
        XCTAssertEqual(vm.header, ["track", "performer", "disc"])
        XCTAssertNil(vm.titleIndex)
    }

    func testIsValidOnlyWhenTitleAssigned() {
        var vm = ColumnMappingViewModel(header: ["A", "B"])
        XCTAssertFalse(vm.isValid)
        vm.titleIndex = 0
        XCTAssertTrue(vm.isValid)
    }

    func testMappingReflectsAllSelections() {
        var vm = ColumnMappingViewModel(header: ["X", "Y", "Z"])
        vm.titleIndex = 0; vm.artistIndex = 1; vm.albumIndex = 2
        let m = vm.mapping
        XCTAssertEqual(m.title, 0)
        XCTAssertEqual(m.artist, 1)
        XCTAssertEqual(m.album, 2)
        XCTAssertNil(m.date)
        XCTAssertNil(m.storeID)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL — `ColumnMappingViewModel` undefined.

- [ ] **Step 3: Create `Sources/App/ColumnMappingViewModel.swift`**

```swift
import Foundation
import Observation
import ReclaimCore

@Observable
public final class ColumnMappingViewModel {
    public let header: [String]
    public var titleIndex: Int?
    public var artistIndex: Int?
    public var albumIndex: Int?
    public var dateIndex: Int?
    public var storeIDIndex: Int?

    public var isValid: Bool { titleIndex != nil }

    public var mapping: ColumnMapping {
        var m = ColumnMapping()
        m.title   = titleIndex
        m.artist  = artistIndex
        m.album   = albumIndex
        m.date    = dateIndex
        m.storeID = storeIDIndex
        return m
    }

    public init(header: [String]) { self.header = header }
}
```

- [ ] **Step 4: Create `Sources/App/ColumnMappingView.swift`**

```swift
import SwiftUI
import ReclaimCore

struct ColumnMappingView: View {
    let header: [String]
    @Bindable var vm: DeepScanViewModel
    @State private var mapper: ColumnMappingViewModel

    init(header: [String], vm: DeepScanViewModel) {
        self.header = header
        self.vm = vm
        _mapper = State(initialValue: ColumnMappingViewModel(header: header))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Assign columns").font(.headline)
            Text("The file's column headers weren't recognised automatically. " +
                 "Tell us which column holds each piece of data.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, columnSpacing: 12, rowSpacing: 8) {
                row("Title (required)", index: $mapper.titleIndex)
                row("Artist",           index: $mapper.artistIndex)
                row("Album",            index: $mapper.albumIndex)
                row("Purchase date",    index: $mapper.dateIndex)
                row("Store ID",         index: $mapper.storeIDIndex)
            }

            HStack {
                Button("Cancel") { vm.reset() }
                Spacer()
                Button("Continue") { Task { await vm.applyMapping(mapper.mapping) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!mapper.isValid)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
    }

    private func row(_ label: String, index: Binding<Int?>) -> some View {
        GridRow {
            Text(label).frame(minWidth: 120, alignment: .trailing)
            Picker("", selection: index) {
                Text("(none)").tag(Optional<Int>.none)
                ForEach(Array(header.enumerated()), id: \.offset) { i, name in
                    Text(name).tag(Optional(i))
                }
            }
            .labelsHidden()
            .frame(minWidth: 180)
        }
    }
}
```

- [ ] **Step 5: Run the tests**

```bash
swift test --filter ColumnMappingViewModelTests
```
Expected: all 3 PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/App/ColumnMappingViewModel.swift Sources/App/ColumnMappingView.swift \
        Tests/AppTests/ColumnMappingViewModelTests.swift
git commit -m "feat: add manual column-mapping fallback for unrecognised CSV headers"
```

---

## Task 6: Results View, `ResultsViewModel`, and "Open in Music" Action

Results are displayed as a list of album cards ordered by actionability (fully-missing
first, then partial, then fully-downloaded). Each card shows album-level status; expanded,
it shows per-track rows with a bucket badge and an **"Open in Music"** button.

### "Open in Music" URL strategy

The app opens Music.app (or the iTunes Store page in Music.app) via `NSWorkspace.open(_:)`.
No network call originates from the app.

| Bucket | URL used | Rationale |
|---|---|---|
| `downloaded` | `music://` | Track is already local; just open Music.app for the user to verify |
| `cloudOnly` | `music://` | Track is in the library but not downloaded; user re-downloads inside Music |
| `missing` with `storeID` | `https://music.apple.com/song/{storeID}` | Deep-links to store page in Music.app on macOS |
| `missing` without `storeID` | `music://` | Fall back to opening Music.app |
| `uncertain` | `music://` | User verifies the match manually in Music |

> **Implementation spike (15 min before shipping):** Confirm that
> `https://music.apple.com/song/{id}` opens in Music.app rather than the browser on
> macOS 13–15 (it should, via the Music URL handler). If not, `itms://itunes.apple.com/
> WebObjects/MZStore.woa/wa/viewSoftware?id={storeID}` is the historical iTunes fallback.
> The URL is constructed in `OpenInMusicAction.url(for:storeID:)` — a one-line change to
> update the scheme once confirmed.

**Files:**
- Create: `Sources/App/OpenInMusicAction.swift`
- Create: `Sources/App/ResultsViewModel.swift`
- Create: `Sources/App/ResultsView.swift`
- Create: `Tests/AppTests/OpenInMusicActionTests.swift`
- Create: `Tests/AppTests/ResultsViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/AppTests/OpenInMusicActionTests.swift`:

```swift
import XCTest
@testable import App
import ReclaimCore

final class OpenInMusicActionTests: XCTestCase {

    let action = OpenInMusicAction()

    func testDownloadedReturnsMusicURL() {
        let url = action.url(for: .downloaded, storeID: nil)
        XCTAssertEqual(url?.scheme, "music")
    }

    func testCloudOnlyReturnsMusicURL() {
        let url = action.url(for: .cloudOnly, storeID: nil)
        XCTAssertEqual(url?.scheme, "music")
    }

    func testMissingWithStoreIDUsesHTTPS() {
        let url = action.url(for: .missing, storeID: "987654321")
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertTrue(url?.absoluteString.contains("987654321") == true)
    }

    func testMissingWithoutStoreIDFallsBackToMusicURL() {
        let url = action.url(for: .missing, storeID: nil)
        XCTAssertNotNil(url)
    }

    func testUncertainReturnsMusicURL() {
        let url = action.url(for: .uncertain, storeID: nil)
        XCTAssertEqual(url?.scheme, "music")
    }
}
```

`Tests/AppTests/ResultsViewModelTests.swift`:

```swift
import XCTest
@testable import App
import ReclaimCore

final class ResultsViewModelTests: XCTestCase {

    private func report(_ status: AlbumStatus, buckets: [Bucket]) -> AlbumReport {
        let results = buckets.enumerated().map { i, b in
            ReconResult(
                purchase: PurchasedItem(title: "T\(i)", artist: "Band", album: "Rec"),
                bucket: b,
                matchedPersistentID: b == .missing ? nil : "\(i)"
            )
        }
        return AlbumReport(artist: "Band", album: "Rec", status: status, results: results)
    }

    func testCounts() {
        let vm = ResultsViewModel(reports: [
            report(.fullyMissing,       buckets: [.missing, .missing]),
            report(.partiallyDownloaded, buckets: [.downloaded, .cloudOnly, .uncertain]),
            report(.fullyDownloaded,    buckets: [.downloaded]),
        ])
        XCTAssertEqual(vm.missingCount, 2)
        XCTAssertEqual(vm.cloudOnlyCount, 1)
        XCTAssertEqual(vm.uncertainCount, 1)
        XCTAssertEqual(vm.downloadedCount, 2)
    }

    func testActionableAlbumsFirst() {
        let vm = ResultsViewModel(reports: [
            report(.fullyDownloaded,    buckets: [.downloaded]),
            report(.fullyMissing,       buckets: [.missing]),
            report(.partiallyDownloaded, buckets: [.downloaded, .cloudOnly]),
        ])
        XCTAssertNotEqual(vm.sortedReports.first?.status, .fullyDownloaded)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Expected: FAIL — `OpenInMusicAction` and `ResultsViewModel` undefined.

- [ ] **Step 3: Create `Sources/App/OpenInMusicAction.swift`**

```swift
import Foundation
import AppKit
import ReclaimCore

public struct OpenInMusicAction {
    public init() {}

    /// Returns the URL to open in Music.app for a given reconciliation bucket.
    /// The caller provides `storeID` from `ReconResult.purchase.storeID` if available.
    public func url(for bucket: Bucket, storeID: String?) -> URL? {
        switch bucket {
        case .downloaded, .cloudOnly, .uncertain:
            return URL(string: "music://")
        case .missing:
            if let sid = storeID, !sid.isEmpty {
                // Opens the store page in Music.app on macOS (confirmed via spike before ship).
                return URL(string: "https://music.apple.com/song/\(sid)")
            }
            return URL(string: "music://")
        }
    }

    public func open(_ url: URL, workspace: NSWorkspace = .shared) {
        workspace.open(url)
    }
}
```

- [ ] **Step 4: Create `Sources/App/ResultsViewModel.swift`**

```swift
import Foundation
import Observation
import ReclaimCore

@Observable
public final class ResultsViewModel {
    public let reports: [AlbumReport]

    public var sortedReports: [AlbumReport] {
        let priority: [AlbumStatus: Int] = [.fullyMissing: 0, .partiallyDownloaded: 1, .fullyDownloaded: 2]
        return reports.sorted { (priority[$0.status] ?? 0) < (priority[$1.status] ?? 0) }
    }

    public var missingCount: Int     { tally(.missing) }
    public var cloudOnlyCount: Int   { tally(.cloudOnly) }
    public var uncertainCount: Int   { tally(.uncertain) }
    public var downloadedCount: Int  { tally(.downloaded) }

    public init(reports: [AlbumReport]) { self.reports = reports }

    private func tally(_ bucket: Bucket) -> Int {
        reports.flatMap(\.results).filter { $0.bucket == bucket }.count
    }
}
```

- [ ] **Step 5: Create `Sources/App/ResultsView.swift`**

```swift
import SwiftUI
import ReclaimCore

struct ResultsView: View {
    let reports: [AlbumReport]
    let reset: () -> Void
    @State private var vm: ResultsViewModel
    private let action = OpenInMusicAction()

    init(reports: [AlbumReport], reset: @escaping () -> Void) {
        self.reports = reports
        self.reset = reset
        _vm = State(initialValue: ResultsViewModel(reports: reports))
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            Divider()
            List(vm.sortedReports, id: \.album) { report in
                AlbumCard(report: report, action: action)
            }
            .listStyle(.inset)
            HStack {
                Spacer()
                Button("Start over", action: reset).padding()
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 20) {
            chip(count: vm.missingCount,    label: "missing",    color: .red)
            chip(count: vm.cloudOnlyCount,  label: "cloud-only", color: .orange)
            chip(count: vm.uncertainCount,  label: "uncertain",  color: .yellow)
            chip(count: vm.downloadedCount, label: "downloaded", color: .green)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func chip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)").bold()
            Text(label).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(6)
    }
}

// MARK: - Album card

private struct AlbumCard: View {
    let report: AlbumReport
    let action: OpenInMusicAction
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(report.results, id: \.purchase.title) { result in
                TrackRow(result: result, action: action).padding(.leading, 16)
            }
        } label: {
            HStack {
                Image(systemName: report.status.iconName)
                    .foregroundStyle(report.status.color).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.album.isEmpty ? "(no album)" : report.album).bold()
                    Text(report.artist).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(report.status.label)
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(report.status.color.opacity(0.15))
                    .cornerRadius(4)
            }
        }
    }
}

// MARK: - Track row

private struct TrackRow: View {
    let result: ReconResult
    let action: OpenInMusicAction

    var body: some View {
        HStack {
            Image(systemName: result.bucket.iconName)
                .foregroundStyle(result.bucket.color).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.purchase.title)
                if !result.purchase.artist.isEmpty {
                    Text(result.purchase.artist).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let url = action.url(for: result.bucket, storeID: result.purchase.storeID) {
                Button("Open in Music") { action.open(url) }
                    .buttonStyle(.plain).foregroundStyle(.accent).font(.caption)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Display helpers

private extension AlbumStatus {
    var label: String {
        switch self {
        case .fullyDownloaded:    return "Downloaded"
        case .partiallyDownloaded: return "Partial"
        case .fullyMissing:       return "Missing"
        }
    }
    var color: Color {
        switch self {
        case .fullyDownloaded:    return .green
        case .partiallyDownloaded: return .orange
        case .fullyMissing:       return .red
        }
    }
    var iconName: String {
        switch self {
        case .fullyDownloaded:    return "checkmark.circle.fill"
        case .partiallyDownloaded: return "exclamationmark.circle.fill"
        case .fullyMissing:       return "xmark.circle.fill"
        }
    }
}

private extension Bucket {
    var color: Color {
        switch self {
        case .downloaded: return .green
        case .cloudOnly:  return .orange
        case .missing:    return .red
        case .uncertain:  return .yellow
        }
    }
    var iconName: String {
        switch self {
        case .downloaded: return "checkmark.circle"
        case .cloudOnly:  return "cloud"
        case .missing:    return "xmark.circle"
        case .uncertain:  return "questionmark.circle"
        }
    }
}
```

- [ ] **Step 6: Run the tests**

```bash
swift test --filter "OpenInMusicActionTests|ResultsViewModelTests"
```
Expected: all 5 + 2 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/App/OpenInMusicAction.swift Sources/App/ResultsViewModel.swift \
        Sources/App/ResultsView.swift \
        Tests/AppTests/OpenInMusicActionTests.swift Tests/AppTests/ResultsViewModelTests.swift
git commit -m "feat: add bucketed results view with album rollup and Open-in-Music deep link"
```

---

## Task 7: Permission-Error + Empty-State Handling

Three failure modes need explicit screens:

1. **TCC denied (`LibraryError.accessDenied`):** a dedicated screen that directs the user
   to System Settings → Privacy & Security → Media & Apple Music.
2. **Other library error / pipeline failure:** a generic error screen with a "Try again"
   button that calls `reset()`.
3. **Empty purchases / empty library:** `DeepScanViewModel.reconcile` already emits
   `.failed("No purchases found")` for an empty purchases CSV. An empty library produces
   `[]` results and an empty `ResultsView` — add a friendly empty state there.

**Files:**
- Create: `Sources/App/ErrorView.swift`
- Modify: `Sources/App/ResultsView.swift` (add empty-results case)

- [ ] **Step 1: Create `Sources/App/ErrorView.swift`**

```swift
import SwiftUI

struct LibraryPermissionView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Music library access needed")
                .font(.title2).bold()
            Text("""
                This app needs permission to read your Music library.\n\
                Open **System Settings → Privacy & Security → Media & Apple Music** \
                and enable access for this app, then relaunch.
                """)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(
                    URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Media"
                    )!
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(48)
        .frame(maxWidth: 420)
    }
}

struct ErrorView: View {
    let message: String
    let reset: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36)).foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.title3).bold()
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again", action: reset)
                .buttonStyle(.borderedProminent)
        }
        .padding(48)
        .frame(maxWidth: 420)
    }
}
```

- [ ] **Step 2: Add empty-results state to `ResultsView`**

In the `body` of `ResultsView`, wrap the `List` with a conditional:

```swift
if vm.sortedReports.isEmpty {
    ContentUnavailableView(
        "No results",
        systemImage: "checkmark.circle",
        description: Text("All purchases matched downloaded tracks in your library.")
    )
} else {
    List(vm.sortedReports, id: \.album) { report in
        AlbumCard(report: report, action: action)
    }
    .listStyle(.inset)
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/App/ErrorView.swift Sources/App/ResultsView.swift
git commit -m "feat: add library-permission error screen and empty-results state"
```

---

## Task 8 (OPEN PRODUCT DECISION): Instant-Scan Tier

### Current status

The design spec (§6.4) describes an **instant scan** that, on launch, shows cloud-only /
not-downloaded library tracks without any user-supplied file — serving the "partially on
Apple Music" use case. Spike 1 found:

1. The author's library has **zero cloud-only items** (no Sync Library, no Apple Music
   subscription). The instant-scan tier cannot be validated against beta-tester #1's Mac.
2. The cloud-only signal (`location == nil && locationTypeIsFile == false`) is
   structurally sound but has **never been observed against a real cloud-only item**.
3. The author's lost purchases are **missing entirely** from the library (deep-scan case),
   not cloud-only. The instant-scan tier does not address their actual problem.

### Recommendation: defer to v1.1

Ship v1 with the deep-scan tier only. The instant-scan tier:
- Cannot be validated without a tester who has an Apple Music subscription with Sync
  Library enabled.
- Would require a second view (a tab or pre-scan results screen) that adds launch-time
  complexity without serving the validated use case.
- The spec's original "instant, on launch, no setup" premise assumed cloud-only items
  exist on the primary user's Mac — Spike 1 falsified this assumption for beta-tester #1.

The structural foundation already exists: `LibraryTrack.isDownloaded`, the `cloudOnly`
bucket in `Reconciler`, and `LibraryReader.fetchAll()` returning all songs. Implementing
the instant-scan view is a matter of adding a filter and a new tab once validated.

### Gate criterion

Before implementing the instant-scan tier for v1.1:

- [ ] Find a tester with an active Apple Music subscription and **Sync Library** enabled
  in Music → Settings → General.
- [ ] Run `scripts/run-probe.sh` (no CSV argument) on their Mac and capture the output.
- [ ] Confirm: (a) cloud-only songs appear in `allMediaItems`; (b) they have `location == nil`;
  (c) `locationType` is `.remote` or `.unknown`; (d) `isCloud` flag (note: still likely
  unpopulated — use `location` signal regardless); (e) the `kind` string for cloud-only
  tracks (to confirm they can be distinguished from pending-download local files).
- [ ] Update `docs/spikes/2026-05-25-itunes-library-cloud-visibility.md` with confirmed
  findings, changing the INCONCLUSIVE verdict to GREEN or RED.

### How it slots in once validated

1. In `ContentView`, add a second tab (or a pre-deep-scan landing view):
   `InstantScanView(tracks: vm.libraryTracks.filter { !$0.isDownloaded })`.
2. `InstantScanView` groups not-downloaded tracks by album (using `rollupByAlbum` on
   synthetic `ReconResult`s with `.cloudOnly` bucket) and shows "Open in Music" per track.
3. Add `InstantScanViewModelTests` covering the filter and grouping logic.
4. No `PurchaseImporter` or CSV involved — the instant scan is a pure `LibraryTrack`
   filter, reusing `AlbumCard` / `TrackRow` from `ResultsView`.

---

## Task 9: Distribution Configuration

### Mac App Store (primary — Spike 2 GREEN)

| Requirement | Where set | Status |
|---|---|---|
| App Sandbox | `.entitlements` | Done in Task 2 |
| `com.apple.security.assets.music.read-only` | `.entitlements` | Done in Task 2 |
| `NSAppleMusicUsageDescription` | `Info.plist` | Done in Task 2 |
| Media & Apple Music TCC prompt | Runtime (user action) | Required |
| Apple Developer Program ($99/yr) | Account | Required |
| App Store Connect listing | App Store Connect | At submission |

The ad-hoc sandboxed probe used in Spike 2 ran with exactly these entitlements and
produced zero sandbox denials — no additional entitlements are expected.

**Submission steps:**
- [ ] Archive with a Distribution certificate: Xcode → Product → Archive.
- [ ] Validate and upload via Xcode Organizer.
- [ ] In the App Review notes, explain that `com.apple.security.assets.music.read-only`
  is used to read the user's local Music library for purchase reconciliation — no
  streaming, no purchase automation, no data uploaded.

### Developer-ID Notarized DMG (fallback)

If App Store review unexpectedly rejects the music-library entitlement:

- Keep the same entitlement set (it is valid for Developer ID, not App Store–restricted).
- Sign with a Developer ID Application certificate instead of a Distribution certificate.
- Notarize: `xcrun notarytool submit <app>.zip --apple-id ... --team-id ...`
- Staple: `xcrun stapler staple <app>.app`
- Package: `hdiutil create -srcfolder <app>.app -o itunes-reclaim.dmg`

No code changes are required between the two distribution routes — only signing identity
and packaging differ.

---

## Done Criteria for Phase 2

- `LibraryTrack` rename is in place; `swift test` passes all 33+ tests.
- `LibraryReader.fetchAll()` builds and its mapping logic is unit-tested (7 new tests).
- The Xcode app builds, launches on the author's Mac, shows the TCC prompt, and loads
  the library without error.
- Dropping the Apple purchases CSV runs the full deep-scan pipeline end-to-end and shows
  bucketed results.
- Unrecognised CSV headers fall through to the manual column-mapping UI.
- Results screen shows albums sorted by actionability, with bucket badges and
  "Open in Music" buttons. Clicking "Open in Music" for a missing track opens Music.app
  (or its store page).
- `LibraryPermissionView` appears when TCC is denied; `ErrorView` covers other failures.
- Instant-scan tier is deferred with a documented gate criterion (Task 8).
- App Sandbox + `com.apple.security.assets.music.read-only` entitlements are in place
  for Mac App Store submission.

---

## ⚠️ Local Export Processing Checklist (repeated for visibility)

**Cannot be done remotely — must be run on the author's Mac once the export arrives.**

- [ ] Request export at privacy.apple.com → iTunes → wait up to 7 days
- [ ] Download + unzip the export
- [ ] Locate `iTunes/iTunes_-_Item_Purchases.csv` inside the ZIP
- [ ] `./scripts/run-probe.sh "$(pwd)/path/to/iTunes_-_Item_Purchases.csv"`
- [ ] Review `[MISSING]` rows — these are the lost purchases the Phase 2 app will surface
