# Harbr TODO

Tracked work for getting Harbr from "polished side project" to "shippable
indie utility." Reordered roughly by sequencing for a public launch.
Last updated by Claude session on 2026-06-04.

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

- [ ] **First-launch permission explanation banner.** Before macOS
  shows the bare "Harbr would like to control Terminal" /
  "Harbr would like to send notifications" prompts, surface a one-
  time in-app banner explaining what they're for and that approving
  makes the app work. Especially important for vibe coders who don't
  recognize the system prompts. Gate via a UserDefaults bool so it
  only shows on first run.

- [ ] **Persist desktop window frame + last selected tab.** Save
  `NSStringFromRect(window.frame)` and `currentTab.rawValue` to
  UserDefaults on `windowWillClose`; restore in `buildWindow` before
  the first `switchTo()` call. Without this, every session repeats
  the same "resize the window, click Activity" dance.

- [ ] **Surface memory pressure + per-project memory warnings.**
  System-level memory pressure indicator in the menu bar (small
  symbol when macOS is under pressure). Per-project: highlight rows
  using > 2 GB in red, with a "this project is contributing to
  system slowness" hover hint. Comes out of the 2026-06-04 freeze
  diagnosis where a user couldn't tell which of their stacked dev
  servers was about to tip the system over.

## P2 — defensive / hygiene

- [ ] **Cap log line length in `LogReader.tail`.** A dev server that
  emits a 10 MB single line (minified progress bars, webpack with no
  newlines) can freeze the Activity refresh timer when `NSTextView`
  tries to render it. After splitting on newlines, truncate any line
  over 8 KB with an ellipsis marker. Safer than capping the whole
  read because long-but-bounded lines (compiler errors with full
  paths) shouldn't get cropped — only pathological single-line outputs.

- [ ] **Guard rapid open/close lifecycle of `HarbrMainWindow`.** If
  the user double-clicks "Open Harbr" or hits ⌘0 twice fast, an
  in-flight `onDismiss` callback from the first window could land
  after the second is set up and null out `currentMainWindow`. Add
  `guard app?.currentMainWindow === self else { return }` identity
  check at the top of the closure.

- [ ] **Add MIT license headers** to `Sources/Harbr/SafeProcess.swift`,
  `Sources/HarbrSafe/HarbrSafe.m`, and `Sources/HarbrSafe/HarbrSafe.h`.
  `main.swift` has the standard 6-line MIT header; the other source
  files don't. Trivial but matters for legal clarity.

## P3 — code health (defer until it actually hurts)

- [ ] **Extract `HarbrMainWindow` tabs into separate files.**
  `main.swift` is at ~3700 lines now; `HarbrMainWindow` alone is
  ~700. Split into `Sources/Harbr/MainWindow/ProjectsTab.swift`,
  `ActivityTab.swift`, `SettingsTab.swift`, `MainWindow.swift`
  (coordinator + sidebar). Same SwiftPM single-target structure,
  just more files. Defer until a new tab or redesign forces the
  issue.
