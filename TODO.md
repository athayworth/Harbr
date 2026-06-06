# Harbr TODO

Tracked work for getting Harbr from "polished side project" to "shippable
indie utility." Reordered roughly by sequencing for a public launch.
Last updated by Claude session on 2026-06-06.

## Externally blocked — need you, not the code

These can't ship from inside the session — they need an account, a key,
a domain, or a screenshot only you can take. The code scaffolding for
each is in place where it makes sense (see sub-bullets); the blocking
work is what's left.

### Apple notarization
- [x] **`scripts/notarize.sh` scaffolded** (2026-06-06). Builds a fresh
  bundle under `dist/`, signs with Developer ID + hardened runtime +
  timestamp, submits to `xcrun notarytool --wait`, staples, and
  re-zips for distribution. Refuses ad-hoc identity so it can't be
  accidentally pointed at a non-notarizable build.
- [ ] **Get the Apple Developer account ($99/yr).** Without it nothing
  else in this section works — `notarytool` requires an enrolled Apple
  ID, an app-specific password, and a 10-character Team ID. Output to
  unblock: those three values, exported into the shell when you run
  `notarize.sh`.
- [ ] **First notarized run.** Confirms the script works end-to-end,
  produces `dist/Harbr.app.zip`, and that fresh-Mac Gatekeeper accepts
  the bundle without a Right-Click → Open dance.

### Sparkle auto-update
- [x] **Sparkle 2.x added as a SwiftPM dependency** in `Package.swift`
  with `from: "2.6.0"`. SourceKit resolves it; `swift build` links
  cleanly.
- [x] **`UpdateManager` wrapper** in `Sources/Harbr/UpdateManager.swift`.
  Initializes `SPUStandardUpdaterController` only when both
  `SUPublicEDKey` and `SUFeedURL` in Info.plist have been replaced
  with real (non-`REPLACE_WITH_`) values. Wires a "Check for
  Updates…" item into the app menu directly under About; it shows
  as disabled until the keys are filled in, so the affordance is
  discoverable but doesn't lie.
- [x] **Info.plist placeholders** (`SUFeedURL`, `SUPublicEDKey`) added
  with `REPLACE_WITH_…` sentinels so `UpdateManager` can detect
  unconfigured state.
- [x] **`docs/appcast.xml` template** committed with a commented-out
  `<item>` showing what each release entry should look like
  (`enclosure url`, `length`, `sparkle:edSignature`).
- [ ] **Generate EdDSA signing keys.** Run the Sparkle `generate_keys`
  tool from a Sparkle release zip. Private key goes into the macOS
  Keychain (don't commit, don't email, don't paste in chat); public
  key replaces `SUPublicEDKey` in Resources/Info.plist.
- [ ] **Pick the appcast hosting URL** and replace `SUFeedURL`. GitHub
  Pages on the Harbr repo is the lowest-effort option:
  `https://athayworth.github.io/Harbr/appcast.xml`. The landing page
  domain (when it exists) is a reasonable upgrade.
- [ ] **Cut the first Sparkle-aware release.** After notarization +
  keys: zip the stapled bundle, upload to a GitHub Release tagged
  `vX.Y.Z`, fill in the appcast template with the URL + EdDSA
  signature + byte length, push appcast.xml. Subsequent releases
  repeat that loop.

### Landing page
- [ ] **Build a landing page** (harbr.app, a section on the studio site,
  or a Vercel one-pager). Hero screenshot, three-feature pitch,
  download button to the notarized zip, link to GitHub, link to
  CHANGELOG. Pure design + copy work; nothing in the repo blocks it,
  but nothing in the repo can do it either. Without an install
  destination that isn't a `git clone`, there's nowhere to point
  people in a tweet.

### README screenshots
- [ ] **Add README screenshots of the menu bar dropdown + desktop
  window.** Three shots in light + dark mode: (1) menu bar dropdown
  with project list + CPU/MEM suffix, (2) desktop window's Projects
  tab with sparklines, (3) Activity tab with Next.js logs streaming.
  Store under `docs/screenshots/`. Has to be taken from your running
  app — Claude can't capture the macOS window itself.

## P0 — shipped

- [x] **Add `CHANGELOG.md` with versioned release notes** in
  Keep-a-Changelog format. Shipped 2026-06-05. `[Unreleased]`
  accumulates everything merged since 2.0.0; `[2.0.0]` documents
  the published baseline. Sparkle-readable. When cutting the next
  release, rename `[Unreleased]` → `[X.Y.Z] - YYYY-MM-DD` and
  start a fresh `[Unreleased]` block. The intermediate work that
  landed between the 2.0.0 cut and this changelog (commits from
  Feb–early June 2026) is intentionally bundled under
  `[Unreleased]` rather than split into invented version numbers
  that never actually shipped.

## P1 — polish that closes the "feels paid" gap

- [x] **In-app Help tab for non-technical users.** Shipped 2026-06-06
  as a fourth sidebar tab on the desktop window, with short
  plain-language explanations of every term Harbr surfaces (Port,
  CPU%, Memory, macOS memory pressure, trend sparkline, the five
  verdict labels, health checks, Docker stats, auto-restart). Content
  lives in `HarbrMainWindow.helpSections` next to the verdict engine
  so wording stays in sync as labels evolve. Built for vibe coders
  who ship features with an LLM but haven't memorized what "memory
  pressure" formally means.

- [x] **Per-project detail view with bigger CPU + memory charts.**
  Shipped 2026-06-05 as `ProjectDetailWindow`, opened as a sheet
  from the Projects table's double-click handler. CPU sparkline
  pinned to 100, memory sparkline auto-scales to peak × 1.1 so
  flat-low projects don't render as a wall of fill. Live-refreshes
  at 1 Hz from the existing 720-sample buffers. Action row:
  Start/Stop (toggles on the live state), Restart, View Logs
  (closes the sheet and focuses the Activity tab on this port via
  `HarbrMainWindow.focusActivity(forPort:)`), Done. Env vars list
  is a read-only NSTextView. Layout has not been visually verified
  end-to-end — needs an eyeball pass on first build.

- [x] **First-launch permission explanation banner.** Shipped
  2026-06-05 as an NSAlert run from `applicationDidFinishLaunching`,
  gated by the `com.harbr.app.didShowPermissionExplanation`
  UserDefaults key so it fires exactly once per user. Explains both
  the Notifications and the Terminal-control prompts before macOS
  surfaces them. Notification request is deferred until the alert
  is dismissed so the system prompt doesn't race the explainer.

- [x] **Persist desktop window frame + last selected tab.** Shipped
  2026-06-05. Frame uses NSWindow's built-in `setFrameAutosaveName`
  pair (autosave + `setFrameUsingName` at build, falling back to
  `center()` on first run). Tab persists via UserDefaults key
  `com.harbr.app.mainWindowLastTab`, written on `windowWillClose`
  and read in `buildWindow` before the first `switchTo()`.

- [x] **Surface memory pressure + per-project memory warnings.**
  Shipped 2026-06-05. Menu bar icon repaints via
  `DispatchSource.makeMemoryPressureSource` — orange palette on
  `.warning`, red on `.critical`, normal template otherwise, with
  a tooltip stating the level. Projects table mem column now tints
  red and adds a "contributing to system slowness" tooltip for
  rows above the 2 GB heavy threshold.

## P2 — defensive / hygiene

- [x] **Cap log line length in `LogReader.tail`.** Shipped 2026-06-05.
  Per-line cap at 8 KB (`maxLineBytes`) applied via a private
  `capLine` helper after the newline split, so multi-KB compiler
  errors still render in full but a pathological 10 MB minified
  line gets truncated with an ellipsis + byte-count marker before
  it reaches NSTextView.

- [x] **Block second instance via `LSMultipleInstancesProhibited`.**
  Added to `Resources/Info.plist` (and patched into the installed
  `/Applications/Harbr.app/Contents/Info.plist`) on 2026-06-04. Fixes
  the duplicate menu-bar-icon bug where a stale SMAppService login
  item and Harbr's own LaunchAgent both fire at login and macOS
  happily starts two copies of the same bundle. With this key,
  macOS refuses the second launch regardless of how many login
  mechanisms register the app — defense in depth vs. trying to
  reconcile the two registration paths. Existing duplicate PIDs
  must still be killed manually for the current session; this only
  prevents recurrence at next login.

- [x] **Guard rapid open/close lifecycle of `HarbrMainWindow`.**
  Shipped 2026-06-05. `openMainWindow` now captures the freshly
  built window into the `onDismiss` closure as a weak reference and
  guards `currentMainWindow === window` before nulling, so a late
  dismiss from a torn-down window can't clobber a newer one the
  user just opened.

- [x] **Add MIT license headers** to `Sources/Harbr/SafeProcess.swift`,
  `Sources/HarbrSafe/HarbrSafe.m`, and
  `Sources/HarbrSafe/include/HarbrSafe.h` (true path — the TODO
  originally listed the header without the `include/` segment).
  Shipped 2026-06-05.

## P3 — code health (defer until it actually hurts)

- [ ] **Extract `HarbrMainWindow` tabs into separate files.**
  `main.swift` is at ~3700 lines now; `HarbrMainWindow` alone is
  ~700. Split into `Sources/Harbr/MainWindow/ProjectsTab.swift`,
  `ActivityTab.swift`, `SettingsTab.swift`, `MainWindow.swift`
  (coordinator + sidebar). Same SwiftPM single-target structure,
  just more files. Defer until a new tab or redesign forces the
  issue.
