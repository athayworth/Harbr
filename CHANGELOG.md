# Changelog

All notable changes to Harbr are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Harbr follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions correspond to `CFBundleShortVersionString` in `Resources/Info.plist`,
so a release listed here matches what Sparkle reads from the running app.

## [Unreleased]

This section accumulates work that has merged to `main` but hasn't been
cut as a release yet. When the user is ready to ship, rename the heading
to the new version + release date and start a fresh `[Unreleased]` block.

### Added

- Foreign-process detection on the project rows. When a port is held
  by a process whose executable name doesn't plausibly match the
  project's `startCommand` (e.g. a stray Streamlit on a port
  configured for a Next.js project), the status dot turns yellow and
  the tooltip names the actual command. Docker-backed ports are
  exempt — any container publishing the port is assumed to be the
  user's. Lives in `HarbrApp.processMatchesStartCommand` and
  `HarbrApp.foreignCommandIfMismatch`, with a small lookup table of
  launcher → expected process for common toolchains (npm/pnpm/yarn
  → node, streamlit/uvicorn → python, etc.). The detail sheet's
  verdict line also flips to "Port held by X — not your project" so
  CPU/memory stats from someone else's process can't be misread as
  the user's project.
- Help tab in the desktop window. New fourth sidebar item with short,
  plain-language explanations of the terms Harbr surfaces in its UI —
  Port, CPU%, Memory (RAM), macOS memory pressure, trend sparklines,
  the verdict labels (compiling / idle / climbing / heavy memory / hot
  CPU), health checks, Docker stats, and auto-restart. Content lives
  next to the code that produces those terms (`HarbrMainWindow.helpSections`)
  so the wording is one screen away from the verdict engine that
  generates the labels.
- Sparkle 2.x scaffolding for in-app auto-updates. `Package.swift`
  pulls Sparkle; `UpdateManager` initializes
  `SPUStandardUpdaterController` only when Info.plist's
  `SUPublicEDKey` and `SUFeedURL` have been swapped from
  `REPLACE_WITH_…` to real values, so the app still builds and runs
  on a fresh clone. "Check for Updates…" menu item shows in the
  Harbr menu and is disabled until those keys are filled in. The
  appcast template ships as `docs/appcast.xml` with a worked
  example of an `<item>` block for a release.
- `scripts/notarize.sh` for producing a notarized, stapled,
  distributable `dist/Harbr.app.zip`. Reads four env vars
  (`CODESIGN_IDENTITY`, `APPLE_ID`, `APP_SPECIFIC_PASSWORD`,
  `TEAM_ID`), enforces hardened runtime + timestamp on the
  signature, submits via `xcrun notarytool --wait`, staples, and
  re-zips. Refuses ad-hoc signing so it can't be misused.
- Docker-aware CPU + memory stats. When a project's port is held by
  the Docker Desktop proxy (`com.docker.backend`) the existing
  PS-based path reads near-zero CPU and a few hundred KB of memory
  regardless of real load. Harbr now shells out to `docker ps` +
  `docker stats` once per poll cycle, joins the host port → container
  mapping with the project list, and substitutes the container's real
  numbers wherever they're available. PS-based stats remain the path
  for non-Docker projects, and the whole feature is a no-op if Docker
  isn't installed or the daemon is stopped.
- Per-project detail view, opened by double-clicking a row in the
  Projects table. Hosts CPU + memory sparklines over the full 1-hour
  buffer (720 samples), live stats, env vars, and Start/Stop /
  Restart / View Logs actions. View Logs jumps the main window to the
  Activity tab focused on that port.
- First-launch permission explanation. Before macOS surfaces the bare
  "Harbr would like to send notifications" and "control Terminal"
  prompts, Harbr now shows a one-time alert explaining what each is
  for. Gated by the `com.harbr.app.didShowPermissionExplanation`
  UserDefaults key.
- macOS memory pressure indicator. The menu bar sailboat repaints
  orange on `.warning` and red on `.critical` via a
  `DispatchSource.MemoryPressureEvent` source, with a tooltip
  stating the level. Driven by macOS, not project-level memory.
- Per-project memory warning: the Projects table's Memory column
  tints red and adds a tooltip ("contributing to system slowness")
  for any row above the 2 GB heavy threshold.
- Persisted main window frame and last selected tab. Frame uses
  `NSWindow.setFrameAutosaveName`; tab is stored under
  `com.harbr.app.mainWindowLastTab`.
- Verdict engine + system health banner on the Projects tab.
  Surfaces "compiling", "idle Xh", "climbing", "heavy memory",
  "hot CPU" inline next to each project name; the banner
  aggregates anything needing attention.
- "Starting…" state shown for the brief window between Start being
  clicked and the port binding, so slow-booting frameworks read as
  intentional rather than broken.

### Changed

- Double-click on a project row now opens the detail view instead
  of toggling start/restart. Use the row's primary action button
  (or the detail view's Start/Stop button) for the previous behavior.

### Fixed

- App failed to launch after Sparkle was added: SwiftPM emits an
  `@executable_path` rpath that doesn't reach `/Contents/Frameworks/`,
  so dyld couldn't resolve Sparkle.framework. `install.sh` and
  `notarize.sh` now embed Sparkle.framework into `/Contents/Frameworks/`
  via `ditto` and rewrite the rpath via `install_name_tool
  -add_rpath @executable_path/../Frameworks` before codesigning.
- Duplicate Harbr instances at login. `LSMultipleInstancesProhibited`
  is now set in `Info.plist`, so even if both Harbr's own LaunchAgent
  and a stale SMAppService login item fire at login, macOS refuses
  to start a second instance.
- Activity tab freezing on pathological log output. `LogReader.tail`
  now caps any single line at 8 KB with an ellipsis marker, so a
  10 MB minified single-line burst no longer wedges NSTextView.
- Race in `HarbrMainWindow` open/close lifecycle. A late `onDismiss`
  callback from a torn-down window can no longer null out a newer
  window the user just opened — guarded with an identity check on
  `currentMainWindow`.

### Defense in depth / hygiene

- MIT license headers added to `Sources/Harbr/SafeProcess.swift`,
  `Sources/HarbrSafe/HarbrSafe.m`, and
  `Sources/HarbrSafe/include/HarbrSafe.h` for parity with
  `main.swift`.

## [2.0.0] - 2026-02-14

Initial public release. The menu bar dropdown plus the desktop
window (Projects + Activity + Settings tabs), launch-at-login
support, log capture per project, and the safety bridge that
keeps subprocess failures from crashing the app are all part of
this baseline.

[Unreleased]: https://github.com/athayworth/Harbr/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/athayworth/Harbr/releases/tag/v2.0.0
