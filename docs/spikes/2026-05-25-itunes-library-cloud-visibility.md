# Spike 1 — iTunesLibrary cloud-only visibility (2026-05-25)

## Question
Does `iTunesLibrary` enumerate cloud-only (not-downloaded) items, and expose a
reliable downloaded-vs-cloud signal?

## What ran
`reclaim-probe` (executable target in this package) linked against
`iTunesLibrary`, run against the author's real Music library.
Environment: macOS 26.3, Xcode 26.4, Swift 6.3.

## How to run (important — a bare `swift run` does NOT work)
`ITLibrary(apiVersion:)` from a plain SwiftPM executable fails with
`NSCocoaErrorDomain` code **4097** ("Couldn't communicate with a helper
application"; XPC service `com.apple.amp.library.framework`) — with **no TCC
prompt**. The media-library XPC service rejects a non-bundled client, even with
`NSAppleMusicUsageDescription` embedded via linker `-sectcreate` and ad-hoc
signing.

The probe only succeeds when wrapped in a code-signed `.app` bundle that carries
`NSAppleMusicUsageDescription` and is launched via **LaunchServices**, so macOS
attributes the Media & Apple Music (TCC) request to the bundle. See
`scripts/run-probe.sh` (build → bundle → ad-hoc sign → `open -W`).

## Findings
- **Permission prompt appeared: yes** — the standard "access Apple Music / your
  media library" TCC prompt, on first LaunchServices launch of the signed
  bundle. Author clicked Allow. (A bare CLI gets no prompt and a hard 4097.)
- total media items (all kinds): **6551**
- total songs: **6170**
- by locationType: **{"file": 6170}** — every song is a local file
- songs with nil location: **0**
- isCloud songs: **0**; isPurchased songs: **0**; isDRMProtected songs: **0**
  — these boolean flags are **not populated** by the modern Music backend and
  are unreliable, even though 955 songs carry the `kind` string
  `"Purchased AAC audio file"`.
- song `kind` strings: 2640 MPEG, 2284 AAC, **955 "Purchased AAC audio file"**,
  286 "Matched AAC audio file" (leftover iTunes Match downloads), 4 WAV, 1 AIFF
- distinguished "Purchased" playlist exists but holds only **11 items** (the
  recent store-purchases sidebar list, not an all-time purchase record) — not
  useful as a purchase source.

### Why there were no cloud-only items to observe
Music → Settings → General shows **no "Sync Library" option** (it only appears
with an active Apple Music or iTunes Match subscription), "Apple Music" display
is off, and "Automatic Downloads" is on. The author has **no iCloud Music
Library**, so there are **no in-library cloud-only items on this Mac**. The
all-`.file` result is correct behaviour, not a framework limitation.

### Real lost-purchase case found
"Kontor Sunset Chill 2019: Winter Edition" (Various Artists; purchased
13 Jan 2019; invoice MMZDG10557) is **entirely absent** from the library —
confirmed both in Music.app and by the probe (0 items match "sunset chill
2019"). This is the **deep-scan** case (purchase gone from the library), not the
instant-scan (cloud-only) case.

## Decision
- [ ] GREEN: cloud-only items are visible with a usable signal → proceed to Phase 2.
- [ ] RED: cloud-only items are NOT visible → STOP.
- [x] **INCONCLUSIVE on cloud-only visibility / instant-scan tier NEEDS REWORK.**

`iTunesLibrary` itself works (from a signed bundle) and reads the local library
with full, accurate metadata. But:

1. The cloud-only-visibility question is **untestable on the author's library**
   — it contains zero cloud-only items (no Sync Library). It stays **open** and
   must be retested on an Apple Music / Sync Library library before the
   instant-scan tier can be relied on.
2. The plan's assumed signal (`location == nil` / `locationType == .remote`) is
   the wrong one regardless; `isCloud`/`isPurchased` are unpopulated. The
   reliable purchase signal is the `kind` **string**.
3. The instant-scan tier's premise **does not hold for the primary beta
   tester** — their lost purchases are missing-entirely (deep-scan), not
   cloud-only. The instant-scan tier needs a product rethink.

Per the author's call (2026-05-25): **proceed with Tasks 2–6** (purchase
importer + reconciler), which are spike-independent and directly serve the
validated deep-scan case. Instant-scan tier reopened with the author.

## Phase 2 inputs captured
- iTunesLibrary requires a code-signed `.app` (not a CLI) + `NSAppleMusicUsageDescription`
  + a user-allowed TCC prompt. Bare binaries get XPC 4097. This pre-informs
  Spike 2 (App Sandbox viability).
- `LibraryReader.isDownloaded` should derive from `location != nil` /
  `locationType == .file`; purchase detection from the `kind` string, not
  `isPurchased`. Cloud detection must be revalidated on a Sync Library library.
