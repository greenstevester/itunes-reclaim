# Spike 2 — iTunesLibrary under App Sandbox (2026-05-25)

## Question
Does `iTunesLibrary` (`ITLibrary`) work when the consuming app runs under the
macOS App Sandbox? This decides distribution: Mac App Store (sandbox required)
vs a direct notarized DMG (spec §4).

## What ran
The `reclaim-probe` bundle, ad-hoc signed **with App Sandbox entitlements**,
launched via LaunchServices in diagnostic mode (no CSV). See
`scripts/run-probe-sandboxed.sh` and `scripts/sandbox.entitlements`.

Entitlements applied (both Mac App Store-permitted):
- `com.apple.security.app-sandbox` = true
- `com.apple.security.assets.music.read-only` = true

(`NSAppleMusicUsageDescription` is in the bundle Info.plist, as in Spike 1.)

## Findings
- **GREEN.** Under the sandbox, `ITLibrary(apiVersion:)` opened and enumerated
  the full library — identical to the non-sandboxed run: 6551 media items, 6170
  songs, full metadata.
- **No `NSCocoaErrorDomain` 4097**, no XPC failure.
- **No sandbox denials** for the probe or for the
  `com.apple.amp.library.framework` mach-lookup — `log show` for "deny" /
  sandbox violations over the run window came back empty.
- No temporary-exception entitlement was needed; the standard music-read sandbox
  entitlement is sufficient for read access to the library.

## Decision
- [x] **GREEN: `iTunesLibrary` works under App Sandbox with the standard
  `com.apple.security.assets.music.read-only` entitlement → the Mac App Store
  route is viable.**
- [ ] RED: sandbox blocks library access → direct notarized DMG.

## Caveats / Phase 2 inputs
- Verified with **ad-hoc signing**; the sandbox was active and honored locally.
  Final confirmation comes at real App Store submission (Apple-issued
  certificate + provisioning profile), but the entitlement set used here is
  App-Store-permitted and nothing blocked library access.
- A user-facing TCC "Media & Apple Music" prompt is still required (Spike 1) —
  the sandbox entitlement and the TCC grant are separate gates; both are needed.
- Spike 1's signal caveats still apply: derive downloaded-vs-not from
  `location` / `locationType`, purchase status from the `kind` string (not the
  unpopulated `isPurchased` / `isCloud` flags), and revalidate cloud-only
  visibility on a Sync Library library.
