//
//  UpdateManager.swift
//  Harbr
//
//  Copyright (c) 2025 Alexander Hayworth
//  Licensed under the MIT License. See LICENSE file for details.
//

import Foundation
import os
import Sparkle

/// Thin wrapper around Sparkle's SPUStandardUpdaterController that only
/// initializes the controller once the Info.plist has a real EdDSA public
/// key and feed URL set — i.e. the project is actually ready to publish
/// updates. Until then `current` is nil and the "Check for Updates…" menu
/// item is disabled.
///
/// Why the runtime gate: the EdDSA public key, the appcast feed URL, and
/// the matching private key live outside the repo for security reasons,
/// so a fresh clone of Harbr should still build and run without
/// half-broken Sparkle behavior. The placeholder values shipped in
/// Resources/Info.plist (`REPLACE_WITH_…`) are detected here and short-
/// circuit the init.
///
/// When you DO want to enable updates:
///   1. Generate EdDSA keys:  `./bin/generate_keys` (from the Sparkle
///      release zip) — stores the private key in macOS Keychain and
///      prints the public key.
///   2. Replace `SUPublicEDKey` in Resources/Info.plist with the printed
///      public key.
///   3. Replace `SUFeedURL` with the URL where appcast.xml will live
///      (GitHub Pages, your landing page, etc.).
///   4. Commit and rebuild. UpdateManager.current will now be a live
///      controller, the menu item enables itself, and Sparkle will
///      check the feed at the cadence configured by SUScheduledCheckInterval
///      (default 86400 s).
@MainActor
final class UpdateManager {
    static let log = Logger(subsystem: "com.harbr.app", category: "UpdateManager")

    /// The live Sparkle controller, or nil if the app hasn't been
    /// configured for updates yet.
    let controller: SPUStandardUpdaterController?

    init() {
        if Self.isConfigured() {
            self.controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            Self.log.info("Sparkle updater started")
        } else {
            self.controller = nil
            Self.log.info("Sparkle config missing — updater not started (placeholder SUPublicEDKey / SUFeedURL)")
        }
    }

    var isAvailable: Bool { controller != nil }

    /// Wired up to a menu item via the standard Sparkle action.
    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }

    /// Returns true only when both the Info.plist public key and feed URL
    /// have been swapped out for real values. The `REPLACE_WITH_…` prefix
    /// is the convention used by Resources/Info.plist's placeholders.
    private static func isConfigured() -> Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !key.isEmpty,
              !key.hasPrefix("REPLACE_WITH_") else { return false }
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feed.isEmpty,
              !feed.hasPrefix("REPLACE_WITH_") else { return false }
        return true
    }
}
