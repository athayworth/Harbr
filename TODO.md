# Harbr TODO

Tracked work for getting Harbr from "polished side project" to "shippable
indie utility." Reordered roughly by sequencing for a public launch.
Last updated by Claude session on 2026-06-05.

## P0 — required to actually ship publicly

These four unlock distribution. Without them, the app can be cloned and
built but isn't really *offered* to anyone.

- [ ] **Get an Apple Developer account ($99/yr) and notarize Harbr.app.**
  Single biggest unlock — without it every downloader hits Gatekeeper's
  "can't verify developer" warning. `scripts/install.sh` already accepts a
  `CODESIGN_IDENTITY` env var; need to add a `scripts/notarize.sh` that
  signs, zips, submits to `xcrun notarytool`, waits, and staples the ticket.
  Output: a `Harbr.app.zip` users can download and just double-click.

- [ ] **Integrate Sparkle for in-app auto-updates.** SwiftPM dep on
  Sparkle 2.x. Generate EdDSA signing keys (private key outside the
  repo), host `appcast.xml` on GitHub Pages or the landing page, wire
  `SUUpdater.shared` to the feed URL. Each release becomes: build →
  notarize → zip → upload to GitHub Releases → append release notes
  to `appcast.xml` → commit. Without Sparkle users freeze on whatever
  version they first installed.

- [ ] **Add `CHANGELOG.md` with versioned release notes** in
  Keep-a-Changelog format. Backfill this session's work into versions
  for each meaningful slice. Sparkle will eat from this format directly.

- [ ] **Build a landing page** (harbr.app, a section on the author's
  studio site, or even a Vercel one-pager). Hero screenshot, three-feature
  pitch, download button to the notarized zip, link to GitHub, link to
  CHANGELOG. Without an install destination that isn't a `git clone`,
  there's nowhere to point people in a tweet.

## P1 — polish that closes the "feels paid" gap

- [ ] **Add README screenshots of the menu bar dropdown + desktop
  window.** Three shots in light + dark mode: (1) menu bar dropdown
  with project list + CPU/MEM suffix, (2) desktop window's Projects
  tab with sparklines, (3) Activity tab with Next.js logs streaming.
  Store under `docs/screenshots/`. README's "Features" section is
  mostly bullets right now — visuals would do more work than the
  bullets do.

- [ ] **Per-project detail view with bigger CPU + memory charts.**
  Double-click a row in the Projects table → sheet or replacement
  pane with: name + port header, large CPU chart (last hour, 5s
  samples = 720 points), large memory chart, uptime, last-restart
  timestamp, action buttons, env vars list. The sparkline buffer
  already exists for CPU; extend to memory + a longer window.
  Optionally embed the Activity log scoped to this project, so the
  detail view is the single-project deep dive.

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
