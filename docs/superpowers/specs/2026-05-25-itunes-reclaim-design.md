---
title: itunes-reclaim — design spec
date: 2026-05-25
status: approved (pending spec review)
---

# itunes-reclaim — Design Spec

> Working name. Product branding is a later decision.

## 1. Problem

People who bought music from the iTunes Store over the years find that some of
those purchases are now **only partially present in Apple Music** (in the library
but not downloaded — greyed out / cloud-only) or **gone from the library
entirely**. Apple's purchase history shows the items, but there is no built-in way
to see, in one place, *which purchased albums and tracks are missing or
un-downloaded* so the owner can reclaim them.

## 2. Goal

A free, public **macOS app** that, for a non-technical user, surfaces:

1. **Cloud-only / not-downloaded** tracks already in their library — instantly, on
   launch, with no setup. *(Covers "partially on Apple Music.")*
2. **Purchases missing from the library entirely** — via an opt-in flow that
   ingests the user's Apple data export. *(Covers "not at all.")*

Each result offers an **"Open in Music"** action so the user can re-download it
themselves.

## 3. Non-goals (v1)

- **No automated re-download.** Report-only. "Open in Music" is a deep link, not
  automation.
- **No purchase-history extraction.** The app does not scrape Apple or reverse the
  Store API. The deep scan consumes a file the user supplies.
- No SQLite/history, no MCP, no receipt-email import, no Windows/iOS.
- No store-availability check (deferred to v2 — see §11).

## 4. Audience & distribution

Public, aimed at **non-technical users**. **Beta tester #1 is the author**, whose
own lost purchases are the first real test case (see §10).

- **Apple Developer Program** ($99/yr) is required either way.
- **App Store vs direct DMG is decided by Spike 2** (§9):
  - If `iTunesLibrary` works under **App Sandbox** → **Mac App Store** (best
    non-tech UX: one-click install, auto-trust, auto-update).
  - If not → **direct notarized DMG**, Developer ID signing, hardened runtime.

## 5. Privacy principle

**Everything stays on the Mac. Nothing is uploaded.** No network calls in v1.
This is a product promise (trust for a stranger dropping in their Apple
transaction history) and an App Store-review asset. (v2's store-availability check
is the first feature that would introduce a network call; it must be opt-in and
clearly disclosed.)

## 6. Architecture

Four units with clean boundaries. The two pure units carry the logic and the risk
and are heavily tested; the framework boundary is isolated behind one type.

### 6.1 `LibraryReader` (framework boundary)
Wraps the `iTunesLibrary` framework (`ITLibrary` / `ITLibMediaItem`). Produces a
canonical list:

```
LibraryItem {
  title, artist, album, albumArtist: String
  trackNumber: Int?
  persistentID: String
  kind: String              // used to flag Store purchases vs Apple Music adds
  isDownloaded: Bool        // derived from local file presence / cloud status
}
```

`isDownloaded` derivation is **Spike 1** — the assumption is that a cloud-only item
appears in the library with no local `location`, but this must be confirmed.

### 6.2 `PurchaseImporter` (pure)
Parses a user-supplied CSV/JSON export and **auto-detects columns** from the header
against synonym sets (e.g. title ← {title, name, item, song, description}; artist ←
{artist, "artist name"}; album ← {album, collection}; date ← {date, "purchase
date", "transaction date"}; storeID ← {"content id", "item id", "adam id"}).
Produces:

```
PurchasedItem { title, artist, album: String; purchaseDate: Date?; storeID: String? }
```

**Fallback:** if headers can't be auto-mapped, the GUI shows a **manual
column-mapping** step (the user picks which column is title/artist/album). This
keeps the importer format-agnostic across the Apple export, neapel's capture, or
any other source.

### 6.3 `Reconciler` (pure — the core risk)
Normalizes both sides, matches, and buckets. Normalization: lowercase, strip
diacritics, collapse whitespace/punctuation, normalize `&`↔`and`, and strip known
noise suffixes (`(Deluxe)`, `(Remastered 2011)`, `(Expanded Edition)`,
`(Bonus Track[s])`, `feat./featuring …`, `Explicit`/`Clean`).

Match keys, strongest first:
1. (normArtist, normAlbum, normTitle) — track-level, high confidence
2. (normArtist, normTitle) — fallback, medium confidence

Buckets per purchased item:
- **downloaded** — matched a library item that is downloaded
- **cloud-only** — matched a library item that is not downloaded
- **missing** — no library match at all
- **uncertain** — matched only on the weak key, or multiple ambiguous candidates

**Bias:** when a plausible (even weak) match exists, prefer **uncertain** over
**missing**. A false "missing" wastes the user's time hunting for something they
own; surfacing it as uncertain lets them eyeball it.

**Album rollup:** results group by (normArtist, normAlbum) and report each album as
*fully downloaded / partially downloaded / fully missing*, matching the user's
mental model ("albums are missing").

### 6.4 UI (SwiftUI views + view models)
- **Instant scan** (core): on launch, `LibraryReader` → list of cloud-only /
  not-downloaded tracks, grouped by album, each with **Open in Music**.
- **Deep scan** (opt-in): guided panel that (a) explains and links the
  privacy.apple.com export request, setting the ~7-day expectation, (b) accepts a
  dropped file → `PurchaseImporter` (with manual-mapping fallback) →
  `Reconciler` → bucketed results, **missing** and **uncertain** highlighted.

## 7. Data flow

```
Launch ─▶ LibraryReader ─▶ [LibraryItem] ─▶ instant-scan view (cloud-only)
Deep scan: dropped file ─▶ PurchaseImporter ─▶ [PurchasedItem] ┐
                                                                ├▶ Reconciler ─▶ buckets ─▶ deep-scan view
                              LibraryReader ─▶ [LibraryItem] ───┘
```

## 8. Error handling

- **Library access denied / `iTunesLibrary` unavailable** → explain how to grant
  access (TCC/Music permission — exact prompt confirmed in Spike 1) rather than
  failing silently.
- **Unparseable file / no recognizable columns** → fall through to manual column
  mapping; if still impossible, a clear, specific error.
- **Empty library / empty purchases** → friendly empty states, not blank screens.

## 9. Feasibility spikes (plan step 1 — do these first)

1. **Cloud-only visibility.** Confirm `iTunesLibrary` enumerates cloud-only
   (not-downloaded) items and exposes a reliable downloaded-vs-cloud signal. If it
   only returns local files, the instant scan loses its point and the concept needs
   rework.
2. **Sandbox viability.** Confirm whether `iTunesLibrary` works under App Sandbox.
   Decides App Store vs direct DMG (§4).

Both run against the author's real library (§10).

## 10. Validation (beta tester #1 = author)

The author's own Mac is the first end-to-end test: their real library drives the
spikes, and their actual lost purchases (the original motivation) are the first
deep-scan input once an export is available. "Reclaimed albums I can verify in
Music" is the success criterion for v1.

## 11. Testing

XCTest. `PurchaseImporter` and `Reconciler` are pure → table-driven tests with
fixture CSVs (varied headers, noise-suffix cases, ambiguous matches) and synthetic
libraries covering every bucket. `LibraryReader` is exercised via a recorded
snapshot fixture plus manual verification against the real library.

## 12. Deferred (explicit YAGNI)

- **Store-availability check** (v2): for each missing item, query the public
  iTunes Lookup API to flag *gone-from-store* vs *re-downloadable*. Adds the first
  network call — opt-in, disclosed.
- SQLite history, receipt-email import, auto-download, Windows/iOS, auto-update
  mechanism (e.g. Sparkle) if the DMG route wins.

## 13. Open questions

- Product name / branding.
- App Store vs direct DMG — resolved by Spike 2.
- Pricing — assumed free for v1.
