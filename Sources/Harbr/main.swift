//
//  main.swift
//  Harbr
//
//  Copyright (c) 2025 Alexander Hayworth
//  Licensed under the MIT License. See LICENSE file for details.
//

import Cocoa
import Foundation
import os
import UserNotifications

// MARK: - Data Models

/// Supported terminal applications.
enum TerminalApp: String, Codable, CaseIterable {
    case terminal = "Terminal"
    case iterm = "iTerm"
    case warp = "Warp"

    var displayName: String { rawValue }

    var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm: return "com.googlecode.iterm2"
        case .warp: return "dev.warp.Warp-Stable"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
}

/// Represents a development project with its server configuration.
struct Project: Codable {
    let name: String
    let port: Int
    let directory: String
    let startCommand: String
    let group: String?
    let healthCheckUrl: String?
    let envVars: [String: String]?
    let autoRestart: Bool?

    /// Whether to auto-restart if the server crashes.
    var shouldAutoRestart: Bool { autoRestart ?? false }

    /// Creates a project with default optional values.
    init(name: String, port: Int, directory: String, startCommand: String,
         group: String? = nil, healthCheckUrl: String? = nil,
         envVars: [String: String]? = nil, autoRestart: Bool? = nil) {
        self.name = name
        self.port = port
        self.directory = directory
        self.startCommand = startCommand
        self.group = group
        self.healthCheckUrl = healthCheckUrl
        self.envVars = envVars
        self.autoRestart = autoRestart
    }
}

/// Application configuration containing all tracked projects.
struct Config: Codable {
    var projects: [Project]
    var terminalApp: TerminalApp?
    var notificationsEnabled: Bool?
    var launchAtLoginEnabled: Bool?

    /// The terminal to use, defaulting to Terminal.app if not set.
    var terminal: TerminalApp {
        get { terminalApp ?? .terminal }
        set { terminalApp = newValue }
    }

    /// Whether to show notifications when servers start/stop.
    var notifications: Bool {
        get { notificationsEnabled ?? true }
        set { notificationsEnabled = newValue }
    }

    /// Whether to launch at login.
    var launchAtLogin: Bool {
        get { launchAtLoginEnabled ?? false }
        set { launchAtLoginEnabled = newValue }
    }
}

// MARK: - Project Editor Window

/// A modal window for adding or editing project configurations.
class ProjectEditorWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var nameField: NSTextField?
    var portField: NSTextField?
    var directoryField: NSTextField?
    var startCommandField: NSTextField?
    var groupField: NSTextField?
    var healthCheckField: NSTextField?
    var autoRestartCheckbox: NSButton?
    var onSave: ((Project) -> Void)?
    /// Called when the editor is dismissed (save, cancel, or window close button).
    var onDismiss: (() -> Void)?
    private var didDismiss = false
    private var existingEnvVars: [String: String]?

    @MainActor init(project: Project? = nil, onSave: @escaping (Project) -> Void) {
        super.init()
        self.onSave = onSave
        self.existingEnvVars = project?.envVars

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 370),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = project == nil ? "Add Project" : "Edit Project"
        window.center()
        window.delegate = self
        window.isMovableByWindowBackground = true
        // ARC owns the window's lifetime; without this, AppKit also releases on close,
        // causing a double-free with pending CoreAnimation transform animations.
        window.isReleasedWhenClosed = false
        self.window = window

        guard let windowContentView = window.contentView else {
            print("Error: Failed to initialize window content view")
            return
        }
        let contentView = NSView(frame: windowContentView.bounds)

        let labelWidth: CGFloat = 110
        let fieldX: CGFloat = 130
        let fieldWidth: CGFloat = 290
        let rowHeight: CGFloat = 36
        var currentY: CGFloat = 200

        // Name field
        let nameLabel = NSTextField(labelWithString: "Name")
        nameLabel.frame = NSRect(x: 20, y: currentY, width: labelWidth, height: 20)
        nameLabel.alignment = .right
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(nameLabel)

        nameField = NSTextField(frame: NSRect(x: fieldX, y: currentY - 2, width: fieldWidth, height: 24))
        nameField?.stringValue = project?.name ?? ""
        nameField?.placeholderString = "My App"
        nameField?.font = NSFont.systemFont(ofSize: 13)
        nameField?.bezelStyle = .roundedBezel
        if let field = nameField {
            contentView.addSubview(field)
        }

        currentY -= rowHeight

        // Port field
        let portLabel = NSTextField(labelWithString: "Port")
        portLabel.frame = NSRect(x: 20, y: currentY, width: labelWidth, height: 20)
        portLabel.alignment = .right
        portLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(portLabel)

        portField = NSTextField(frame: NSRect(x: fieldX, y: currentY - 2, width: 80, height: 24))
        portField?.stringValue = project.map { "\($0.port)" } ?? ""
        portField?.placeholderString = "3000"
        portField?.font = NSFont.systemFont(ofSize: 13)
        portField?.bezelStyle = .roundedBezel
        if let field = portField {
            contentView.addSubview(field)
        }

        currentY -= rowHeight

        // Directory field
        let directoryLabel = NSTextField(labelWithString: "Directory")
        directoryLabel.frame = NSRect(x: 20, y: currentY, width: labelWidth, height: 20)
        directoryLabel.alignment = .right
        directoryLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(directoryLabel)

        directoryField = NSTextField(frame: NSRect(x: fieldX, y: currentY - 2, width: fieldWidth - 50, height: 24))
        directoryField?.stringValue = project?.directory ?? ""
        directoryField?.placeholderString = "~/Projects/my-app"
        directoryField?.font = NSFont.systemFont(ofSize: 13)
        directoryField?.bezelStyle = .roundedBezel
        if let field = directoryField {
            contentView.addSubview(field)
        }

        let browseButton = NSButton(frame: NSRect(x: fieldX + fieldWidth - 44, y: currentY - 3, width: 44, height: 26))
        browseButton.title = "..."
        browseButton.bezelStyle = .rounded
        browseButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        browseButton.target = self
        browseButton.action = #selector(browseDirectory)
        contentView.addSubview(browseButton)

        currentY -= rowHeight

        // Start command field
        let commandLabel = NSTextField(labelWithString: "Command")
        commandLabel.frame = NSRect(x: 20, y: currentY, width: labelWidth, height: 20)
        commandLabel.alignment = .right
        commandLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(commandLabel)

        startCommandField = NSTextField(frame: NSRect(x: fieldX, y: currentY - 2, width: fieldWidth, height: 24))
        startCommandField?.stringValue = project?.startCommand ?? ""
        startCommandField?.placeholderString = "npm run dev"
        startCommandField?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        startCommandField?.bezelStyle = .roundedBezel
        if let field = startCommandField {
            contentView.addSubview(field)
        }

        currentY -= rowHeight

        // Group field
        let groupLabel = NSTextField(labelWithString: "Group")
        groupLabel.frame = NSRect(x: 20, y: currentY, width: labelWidth, height: 20)
        groupLabel.alignment = .right
        groupLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(groupLabel)

        groupField = NSTextField(frame: NSRect(x: fieldX, y: currentY - 2, width: fieldWidth, height: 24))
        groupField?.stringValue = project?.group ?? ""
        groupField?.placeholderString = "Optional group name"
        groupField?.font = NSFont.systemFont(ofSize: 13)
        groupField?.bezelStyle = .roundedBezel
        if let field = groupField {
            contentView.addSubview(field)
        }

        currentY -= rowHeight

        // Health check URL field
        let healthLabel = NSTextField(labelWithString: "Health Check")
        healthLabel.frame = NSRect(x: 20, y: currentY, width: labelWidth, height: 20)
        healthLabel.alignment = .right
        healthLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(healthLabel)

        healthCheckField = NSTextField(frame: NSRect(x: fieldX, y: currentY - 2, width: fieldWidth, height: 24))
        healthCheckField?.stringValue = project?.healthCheckUrl ?? ""
        healthCheckField?.placeholderString = "/health or http://..."
        healthCheckField?.font = NSFont.systemFont(ofSize: 13)
        healthCheckField?.bezelStyle = .roundedBezel
        if let field = healthCheckField {
            contentView.addSubview(field)
        }

        currentY -= rowHeight

        // Auto-restart checkbox
        autoRestartCheckbox = NSButton(frame: NSRect(x: fieldX, y: currentY - 2, width: fieldWidth, height: 20))
        autoRestartCheckbox?.setButtonType(.switch)
        autoRestartCheckbox?.title = "Auto-restart if server crashes"
        autoRestartCheckbox?.font = NSFont.systemFont(ofSize: 13)
        autoRestartCheckbox?.state = (project?.autoRestart ?? false) ? .on : .off
        if let checkbox = autoRestartCheckbox {
            contentView.addSubview(checkbox)
        }

        // Buttons
        let cancelButton = NSButton(frame: NSRect(x: 280, y: 16, width: 90, height: 32))
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        contentView.addSubview(cancelButton)

        let saveButton = NSButton(frame: NSRect(x: 376, y: 16, width: 90, height: 32))
        saveButton.title = "Save"
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)
        if #available(macOS 11.0, *) {
            saveButton.hasDestructiveAction = false
            saveButton.bezelColor = NSColor.controlAccentColor
        }
        contentView.addSubview(saveButton)

        window.contentView = contentView
    }

    @MainActor @objc func browseDirectory() {
        guard let window = self.window else { return }

        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false

        openPanel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = openPanel.url {
                self?.directoryField?.stringValue = url.path
            }
        }
    }

    @MainActor @objc func save() {
        guard let name = nameField?.stringValue, !name.isEmpty,
              let portString = portField?.stringValue, let port = Int(portString),
              let directory = directoryField?.stringValue, !directory.isEmpty,
              let startCommand = startCommandField?.stringValue, !startCommand.isEmpty else {

            let alert = NSAlert()
            alert.messageText = "Invalid Input"
            alert.informativeText = "Please fill in all fields with valid values."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Validate port range
        guard port >= 1 && port <= 65535 else {
            let alert = NSAlert()
            alert.messageText = "Invalid Port"
            alert.informativeText = "Port must be between 1 and 65535."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Expand tilde and validate directory exists
        let expandedDirectory = NSString(string: directory).expandingTildeInPath
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: expandedDirectory, isDirectory: &isDir) || !isDir.boolValue {
            let alert = NSAlert()
            alert.messageText = "Directory Not Found"
            alert.informativeText = "The directory \"\(directory)\" does not exist. Create it first or choose a different path."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Get optional field values
        let group = groupField?.stringValue.isEmpty == false ? groupField?.stringValue : nil
        let healthCheckUrl = healthCheckField?.stringValue.isEmpty == false ? healthCheckField?.stringValue : nil
        let autoRestart = autoRestartCheckbox?.state == .on

        let project = Project(
            name: name,
            port: port,
            directory: expandedDirectory,
            startCommand: startCommand,
            group: group,
            healthCheckUrl: healthCheckUrl,
            envVars: existingEnvVars,
            autoRestart: autoRestart
        )

        onSave?(project)
        dismiss()
    }

    @MainActor @objc func cancel() {
        dismiss()
    }

    /// Hides the window and triggers cleanup. Does not deallocate immediately.
    @MainActor private func dismiss() {
        guard !didDismiss else { return }
        didDismiss = true
        window?.delegate = nil
        window?.orderOut(nil)  // Hide immediately without animation
        onDismiss?()
    }

    @MainActor func windowWillClose(_ notification: Notification) {
        // Handle case where user clicks the window's close button (X)
        dismiss()
    }

    @MainActor func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Main Application

/// The main application delegate that manages the menu bar interface and server monitoring.
class HarbrApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let launchAgentLog = Logger(subsystem: "com.harbr.app", category: "LaunchAgent")

    var statusItem: NSStatusItem?
    var config: Config?
    var timer: Timer?
    var currentEditorWindow: ProjectEditorWindow?
    var previousPortStates: [Int: Bool] = [:]
    var notificationsAuthorized = false
    /// Tracks ports that were intentionally stopped by user (to avoid auto-restart)
    var userStoppedPorts: Set<Int> = []
    /// Per-port consecutive failed-restart count. Reset to 0 when the port comes
    /// up successfully. Used to cap the retry loop at MAX_RESTART_ATTEMPTS so a
    /// process that won't bind (e.g. EADDRINUSE because the prior PID hasn't
    /// released the port) doesn't generate an infinite cascade of Terminal windows.
    var restartAttempts: [Int: Int] = [:]
    /// Hard cap on consecutive auto-restart attempts before Harbr gives up and
    /// surfaces a notification asking the user to investigate.
    static let MAX_RESTART_ATTEMPTS = 3
    /// Wall-clock time of the most recent Harbr-initiated spawn, per port.
    /// Used to gate auto-restart to the supervised window: ports that have
    /// been up past the window are treated as stable, so a subsequent
    /// port-down is presumed intentional (e.g. `docker compose down` from
    /// another terminal) rather than a crash to recover from.
    var lastSpawnAt: [Int: Date] = [:]
    /// Duration after spawn during which auto-restart fires on port-down.
    /// Long enough to cover slow boots (Docker daemon warmup, supabase
    /// init), short enough that a server running for an hour and then
    /// being shut down externally won't get respawned.
    static let SUPERVISED_WINDOW: TimeInterval = 30
    /// The persistent menu object - reused to avoid crashes from releasing during animations
    var statusMenu: NSMenu?
    /// Tracks whether the menu is currently open
    var isMenuOpen = false
    /// Tracks whether a menu rebuild is pending (deferred while menu is open)
    var pendingMenuRebuild = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sailboat.fill", accessibilityDescription: "Harbr")
            button.image?.isTemplate = true
        }

        loadConfig()

        // Request notification permissions
        requestNotificationPermissions()

        // Create persistent menu with delegate to track open/close state
        statusMenu = NSMenu()
        statusMenu?.delegate = self
        statusItem?.menu = statusMenu

        // Build initial menu immediately (without resource info)
        rebuildMenu()

        // Then start async updates
        updateMenu()

        // Update menu every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateMenu()
        }
    }

    func requestNotificationPermissions() {
        // UserNotifications requires a proper app bundle; skip if running as bare executable
        guard Bundle.main.bundleIdentifier != nil else {
            notificationsAuthorized = false
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.notificationsAuthorized = granted
        }
    }

    func sendNotification(title: String, body: String) {
        guard notificationsAuthorized, config?.notifications == true,
              Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep the app running even when all windows are closed
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        timer?.invalidate()
        timer = nil
        return .terminateNow
    }

    func loadConfig() {
        let configDir = NSString(string: "~/.harbr").expandingTildeInPath
        let configPath = "\(configDir)/config.json"
        let fileManager = FileManager.default

        // Create config directory if it doesn't exist
        if !fileManager.fileExists(atPath: configDir) {
            do {
                try fileManager.createDirectory(atPath: configDir, withIntermediateDirectories: true)
            } catch {
                print("Failed to create config directory: \(error)")
            }
        }

        // Create default config file if it doesn't exist
        if !fileManager.fileExists(atPath: configPath) {
            let defaultConfig = Config(projects: [])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            if let data = try? encoder.encode(defaultConfig) {
                try? data.write(to: URL(fileURLWithPath: configPath))
            }
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else {
            print("Failed to load config from \(configPath)")
            config = Config(projects: [])
            return
        }

        let decoder = JSONDecoder()
        config = (try? decoder.decode(Config.self, from: data)) ?? Config(projects: [])
    }

    @MainActor func saveConfig() {
        guard let config = config else { return }

        let configPath = NSString(string: "~/.harbr/config.json").expandingTildeInPath
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(config)
            try data.write(to: URL(fileURLWithPath: configPath))
            updateMenu()
        } catch {
            showAlert(title: "Error", message: "Failed to save config: \(error.localizedDescription)")
        }
    }

    // MARK: Terminal Helpers

    /// Escapes a string for safe use in shell commands within single quotes.
    /// Handles single quotes by ending the quoted string, adding an escaped quote, and starting a new quoted string.
    private func shellEscape(_ string: String) -> String {
        return string.replacingOccurrences(of: "'", with: "'\\''")
    }

    /// Opens a terminal window in the specified directory, optionally running a command.
    @MainActor func openTerminal(directory: String, command: String? = nil, activate: Bool = true) {
        let terminal = config?.terminal ?? .terminal
        let safeDirectory = shellEscape(directory)
        let safeCommand = command.map { shellEscape($0) }

        let script: String
        switch terminal {
        case .terminal:
            if let cmd = safeCommand {
                script = """
                tell application "Terminal"
                    do script "cd '\(safeDirectory)' && \(cmd)"
                    \(activate ? "activate" : "")
                end tell
                """
            } else {
                script = """
                tell application "Terminal"
                    do script "cd '\(safeDirectory)'"
                    \(activate ? "activate" : "")
                end tell
                """
            }

        case .iterm:
            if let cmd = safeCommand {
                script = """
                tell application "iTerm"
                    create window with default profile
                    tell current session of current window
                        write text "cd '\(safeDirectory)' && \(cmd)"
                    end tell
                    \(activate ? "activate" : "")
                end tell
                """
            } else {
                script = """
                tell application "iTerm"
                    create window with default profile
                    tell current session of current window
                        write text "cd '\(safeDirectory)'"
                    end tell
                    \(activate ? "activate" : "")
                end tell
                """
            }

        case .warp:
            // Warp uses a different approach - open via URL scheme or direct launch
            if let cmd = safeCommand {
                script = """
                tell application "Warp"
                    \(activate ? "activate" : "")
                end tell
                delay 0.5
                tell application "System Events"
                    keystroke "cd '\(safeDirectory)' && \(cmd)"
                    key code 36
                end tell
                """
            } else {
                script = """
                tell application "Warp"
                    \(activate ? "activate" : "")
                end tell
                delay 0.5
                tell application "System Events"
                    keystroke "cd '\(safeDirectory)'"
                    key code 36
                end tell
                """
            }
        }

        let terminalDisplayName = terminal.displayName

        // Run AppleScript off main: NSAppleScript.executeAndReturnError
        // blocks the calling thread waiting for the AppleEvent reply, and
        // Terminal.app can take seconds to respond (especially after a
        // kill -9 burst). Without this, every Start / Restart click froze
        // the menu bar UI until the target terminal responded.
        appleScriptQueue.async { [weak self] in
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                scriptObject.executeAndReturnError(&error)
                if let error = error {
                    let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    print("AppleScript error: \(error)")
                    Task { @MainActor [weak self] in
                        self?.showAlert(
                            title: "Failed to Open Terminal",
                            message: "Could not open \(terminalDisplayName): \(errorMessage)"
                        )
                    }
                }
            }
        }
    }

    /// Activates the configured terminal application.
    func activateTerminal() {
        let terminal = config?.terminal ?? .terminal
        let script = """
        tell application "\(terminal.displayName)"
            activate
        end tell
        """
        // Off main for the same reason as openTerminal — activation can
        // synchronously wait for the target app to come forward.
        appleScriptQueue.async {
            if let scriptObject = NSAppleScript(source: script) {
                var error: NSDictionary?
                scriptObject.executeAndReturnError(&error)
            }
        }
    }

    // MARK: Port Status

    /// Cached status information for a monitored port.
    struct PortStatus {
        let isActive: Bool
        let cpuUsage: Double?
        let memoryUsage: Double?
        let healthStatus: Bool? // nil = no health check, true = healthy, false = unhealthy
    }

    /// Cache for port status to avoid blocking the menu on each open.
    var portStatusCache: [Int: PortStatus] = [:]
    /// Monotonic counter incremented on every updateResourceCache call.
    /// Each background poll captures the value at start and only commits
    /// its result if it still matches at commit time — older in-flight polls
    /// (e.g. a 5s timer poll that started before a user-initiated stop) are
    /// discarded so they can't overwrite fresher state.
    var pollGeneration: UInt64 = 0
    /// Serial queue for NSAppleScript execution. NSAppleScript isn't
    /// thread-safe, and running it inline on main blocks the UI when
    /// Terminal/iTerm/Warp is slow to respond (AppleEvents can take many
    /// seconds, especially right after killing a server). Funneling through
    /// a dedicated serial queue keeps main responsive while still serializing
    /// AppleScript invocations against the target app.
    private let appleScriptQueue = DispatchQueue(label: "com.harbr.app.applescript", qos: .userInitiated)

    /// Checks if a process is listening on the specified port.
    /// Uses a native BSD socket — no subprocess, no fork, can't crash
    /// under memory pressure (which is why the old lsof-based version
    /// blew up: NSTask raised an ObjC exception that bypassed `try`).
    func isPortActive(_ port: Int) -> Bool {
        SafeProcess.isPortActive(port)
    }

    /// Checks if a project is healthy by pinging its health check URL.
    /// Returns true if healthy, false if unhealthy, nil if no health check configured.
    func checkProjectHealth(_ project: Project) -> Bool? {
        guard let healthUrl = project.healthCheckUrl, !healthUrl.isEmpty else {
            return nil // No health check configured
        }

        // Build full URL if relative path provided
        let fullUrl: String
        if healthUrl.hasPrefix("http://") || healthUrl.hasPrefix("https://") {
            fullUrl = healthUrl
        } else {
            let path = healthUrl.hasPrefix("/") ? healthUrl : "/\(healthUrl)"
            fullUrl = "http://localhost:\(project.port)\(path)"
        }

        guard let url = URL(string: fullUrl) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0
        request.httpMethod = "GET"

        let semaphore = DispatchSemaphore(value: 0)
        var isHealthy = false

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if error == nil, let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode >= 200 && httpResponse.statusCode < 400 {
                isHealthy = true
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 4.0)

        return isHealthy
    }

    func getResourceUsage(for port: Int) -> (cpu: Double, mem: Double)? {
        // Get PIDs for the port. SafeProcess returns nil on launch failure
        // or ObjC exception (e.g. fork() failing under memory pressure).
        // Flags: -n (no DNS), -P (no port-name lookup), -b (avoid blocking
        // kernel calls), -w (suppress -b warnings). Without these, lsof can
        // hang for tens of seconds when launched from inside a GUI app
        // because every getaddrinfo/service lookup goes through a cold
        // resolver — the polling loop here calls this on every active port
        // every 5s, so any per-call latency multiplies fast. Shorter timeout
        // since a healthy lsof returns in <100ms.
        guard let pidResult = SafeProcess.runCapturingOutput(
            launchPath: "/usr/sbin/lsof",
            arguments: ["-nP", "-b", "-w", "-t", "-i", ":\(port)"],
            timeout: 3
        ) else { return nil }

        let pidOutput = pidResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pidOutput.isEmpty else { return nil }

        let pids = pidOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !pids.isEmpty else { return nil }

        // Get resource usage for all PIDs in one ps call
        guard let psResult = SafeProcess.runCapturingOutput(
            launchPath: "/bin/ps",
            arguments: ["-p", pids.joined(separator: ","), "-o", "%cpu,%mem"]
        ) else { return nil }

        var totalCpu: Double = 0
        var totalMem: Double = 0

        let lines = psResult.stdout.components(separatedBy: "\n")
        for line in lines.dropFirst() { // Skip header
            let values = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: CharacterSet.whitespaces)
                .filter { !$0.isEmpty }
            if values.count >= 2 {
                totalCpu += Double(values[0]) ?? 0
                totalMem += Double(values[1]) ?? 0
            }
        }

        return (totalCpu, totalMem)
    }

    func updateResourceCache() {
        guard let config = config else { return }

        // Capture states on main thread to avoid data race
        let capturedPreviousStates = self.previousPortStates
        let capturedUserStoppedPorts = self.userStoppedPorts
        let projectsCopy = config.projects

        // Bump generation so any older in-flight poll is discarded at commit.
        pollGeneration &+= 1
        let myGeneration = pollGeneration

        DispatchQueue.global(qos: .background).async { [weak self] in
            var newCache: [Int: PortStatus] = [:]
            var stateChanges: [(project: Project, started: Bool)] = []

            // Phase 1 — port + resource sampling (serial, fast).
            for project in projectsCopy {
                let isActive = self?.isPortActive(project.port) ?? false
                var cpu: Double? = nil
                var mem: Double? = nil

                if isActive, let usage = self?.getResourceUsage(for: project.port) {
                    cpu = usage.cpu
                    mem = usage.mem
                }

                newCache[project.port] = PortStatus(isActive: isActive, cpuUsage: cpu, memoryUsage: mem, healthStatus: nil)

                // Check for state change using captured snapshot
                if let previousState = capturedPreviousStates[project.port],
                   previousState != isActive {
                    stateChanges.append((project: project, started: isActive))
                }
            }

            // Phase 2 — health checks in parallel. Previously these ran serially
            // inside Phase 1, blocking the cache update for up to ~4s per
            // health-checked project; now wall-clock is capped at 5s for all of
            // them combined. A health check that times out still presents as
            // "unhealthy" (matches prior behavior via the pre-seed below).
            let healthGroup = DispatchGroup()
            let healthLock = NSLock()
            var healthResults: [Int: Bool] = [:]

            let projectsNeedingHealth = projectsCopy.filter { project in
                (newCache[project.port]?.isActive ?? false) &&
                (project.healthCheckUrl?.isEmpty == false)
            }
            for project in projectsNeedingHealth {
                healthResults[project.port] = false  // pessimistic until proven healthy
            }
            for project in projectsNeedingHealth {
                healthGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = self?.checkProjectHealth(project) ?? false
                    healthLock.lock()
                    healthResults[project.port] = result
                    healthLock.unlock()
                    healthGroup.leave()
                }
            }
            _ = healthGroup.wait(timeout: .now() + 5.0)

            // Merge health results back into the cache.
            for (port, healthy) in healthResults {
                guard let status = newCache[port] else { continue }
                newCache[port] = PortStatus(
                    isActive: status.isActive,
                    cpuUsage: status.cpuUsage,
                    memoryUsage: status.memoryUsage,
                    healthStatus: healthy
                )
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // Stale-result guard: a newer poll has been scheduled since
                // this one started, so its result is more recent — drop ours.
                // This matters when a user-initiated stop schedules a fresh
                // poll while a 5s timer poll (which may have read the port
                // as still-active and then blocked for ~5s on health checks)
                // is still pending. Without this, the older poll commits
                // last and the toolbar count freezes at the pre-stop value
                // until the next timer tick.
                guard myGeneration == self.pollGeneration else { return }

                // Update previous states
                for project in projectsCopy {
                    self.previousPortStates[project.port] = newCache[project.port]?.isActive ?? false
                }

                // Collect projects that need auto-restart
                var projectsToRestart: [Project] = []

                // Send notifications and handle auto-restart for state changes
                for change in stateChanges {
                    if change.started {
                        self.sendNotification(
                            title: "\(change.project.name) Started",
                            body: "Server is now running on port \(change.project.port)"
                        )
                        // Clear user-stopped flag and reset attempt counter when the server
                        // successfully comes up. Reset is critical — without it, a project
                        // that crashes after a few healthy hours would still have stale
                        // attempt count, possibly above the cap, and never restart.
                        self.userStoppedPorts.remove(change.project.port)
                        self.restartAttempts[change.project.port] = 0
                    } else {
                        self.sendNotification(
                            title: "\(change.project.name) Stopped",
                            body: "Server on port \(change.project.port) is no longer running"
                        )

                        // Auto-restart fires only inside the supervised window
                        // after a Harbr-initiated spawn. Outside the window the
                        // project is considered stable, and a port-down event is
                        // treated as intentional (e.g. `docker compose down`)
                        // rather than a crash. Inside the window, the existing
                        // retry cap still applies to prevent EADDRINUSE cascades.
                        let withinSupervisedWindow: Bool = {
                            guard let spawn = self.lastSpawnAt[change.project.port] else {
                                return false
                            }
                            return Date().timeIntervalSince(spawn) <= HarbrApp.SUPERVISED_WINDOW
                        }()

                        if change.project.shouldAutoRestart &&
                           !capturedUserStoppedPorts.contains(change.project.port) &&
                           withinSupervisedWindow {
                            let attempts = self.restartAttempts[change.project.port, default: 0]
                            if attempts >= HarbrApp.MAX_RESTART_ATTEMPTS {
                                self.sendNotification(
                                    title: "\(change.project.name) — auto-restart suspended",
                                    body: "Failed \(attempts) times in a row. Click the menu bar icon to investigate."
                                )
                                // Don't enqueue another retry. User must manually start.
                            } else {
                                self.restartAttempts[change.project.port] = attempts + 1
                                self.sendNotification(
                                    title: "Auto-restarting \(change.project.name)",
                                    body: "Server stopped, restarting (attempt \(attempts + 1)/\(HarbrApp.MAX_RESTART_ATTEMPTS))…"
                                )
                                projectsToRestart.append(change.project)
                            }
                        }
                    }
                }

                self.portStatusCache = newCache
                self.rebuildMenu()

                // Schedule auto-restarts after a delay
                if !projectsToRestart.isEmpty {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    for project in projectsToRestart {
                        self.startProjectDirectly(project)
                    }
                }
            }
        }
    }

    func updateMenu() {
        // Trigger async update of resource cache
        updateResourceCache()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        // If a rebuild was requested while menu was open, do it now
        if pendingMenuRebuild {
            pendingMenuRebuild = false
            DispatchQueue.main.async { [weak self] in
                self?.rebuildMenu()
            }
        }
    }

    @MainActor func rebuildMenu() {
        // Defer rebuild if menu is currently open to avoid animation crashes
        if isMenuOpen {
            pendingMenuRebuild = true
            return
        }

        guard let menu = statusMenu else { return }

        // Clear existing items and rebuild (reusing the same menu object)
        menu.removeAllItems()

        // Update menu bar icon with running count
        let runningCount = portStatusCache.values.filter { $0.isActive }.count
        if let button = statusItem?.button {
            if runningCount > 0 {
                button.title = " \(runningCount)"
            } else {
                button.title = ""
            }
        }

        guard let config = config else {
            menu.addItem(NSMenuItem(title: "No projects configured", action: nil, keyEquivalent: ""))
            let addItem = NSMenuItem(title: "Add Project...", action: #selector(addNewProject), keyEquivalent: "n")
            addItem.target = self
            menu.addItem(addItem)
            menu.addItem(NSMenuItem.separator())
            let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)
            return
        }

        let headerItem = NSMenuItem(title: "Harbr", action: nil, keyEquivalent: "")
        headerItem.attributedTitle = NSAttributedString(
            string: "Harbr",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        )
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())

        // Group projects by their group field
        let ungroupedProjects = config.projects.filter { $0.group == nil || $0.group?.isEmpty == true }
        let groupedProjects = config.projects.filter { $0.group != nil && $0.group?.isEmpty == false }
        let groups = Dictionary(grouping: groupedProjects) { $0.group ?? "" }
        let sortedGroupNames = groups.keys.sorted()

        // Add ungrouped projects first
        for project in ungroupedProjects {
            addProjectMenuItem(project, to: menu)
        }

        // Add grouped projects with headers
        for groupName in sortedGroupNames {
            if !ungroupedProjects.isEmpty || groupName != sortedGroupNames.first {
                menu.addItem(NSMenuItem.separator())
            }

            let groupHeader = NSMenuItem(title: groupName, action: nil, keyEquivalent: "")
            groupHeader.attributedTitle = NSAttributedString(
                string: groupName,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            groupHeader.isEnabled = false
            menu.addItem(groupHeader)

            for project in groups[groupName] ?? [] {
                addProjectMenuItem(project, to: menu)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Bulk actions (only show if there are projects)
        if !config.projects.isEmpty {
            let stoppedCount = config.projects.filter { portStatusCache[$0.port]?.isActive != true }.count
            let runningCount = config.projects.count - stoppedCount

            if stoppedCount > 0 {
                let startAllItem = NSMenuItem(title: "Start All", action: #selector(startAllProjects), keyEquivalent: "")
                startAllItem.target = self
                menu.addItem(startAllItem)
            }

            if runningCount > 0 {
                let stopAllItem = NSMenuItem(title: "Stop All", action: #selector(stopAllProjects), keyEquivalent: "")
                stopAllItem.target = self
                menu.addItem(stopAllItem)
            }

            menu.addItem(NSMenuItem.separator())
        }

        let addProjectItem = NSMenuItem(title: "Add Project...", action: #selector(addNewProject), keyEquivalent: "n")
        addProjectItem.target = self
        menu.addItem(addProjectItem)

        let reloadItem = NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        // Preferences submenu
        let prefsItem = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: ",")
        let prefsSubmenu = NSMenu()

        let terminalItem = NSMenuItem(title: "Terminal App", action: nil, keyEquivalent: "")
        let terminalSubmenu = NSMenu()

        let currentTerminal = config.terminal
        for terminal in TerminalApp.allCases {
            let item = NSMenuItem(title: terminal.displayName, action: #selector(setTerminalApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = terminal
            item.state = (terminal == currentTerminal) ? .on : .off
            if !terminal.isInstalled && terminal != .terminal {
                item.isEnabled = false
                item.title = "\(terminal.displayName) (not installed)"
            }
            terminalSubmenu.addItem(item)
        }

        terminalItem.submenu = terminalSubmenu
        prefsSubmenu.addItem(terminalItem)

        prefsSubmenu.addItem(NSMenuItem.separator())

        let notificationsItem = NSMenuItem(title: "Notifications", action: #selector(toggleNotifications), keyEquivalent: "")
        notificationsItem.target = self
        notificationsItem.state = config.notifications ? .on : .off
        prefsSubmenu.addItem(notificationsItem)

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = config.launchAtLogin ? .on : .off
        prefsSubmenu.addItem(launchAtLoginItem)

        prefsItem.submenu = prefsSubmenu
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        // Menu is already assigned to statusItem, no need to reassign
    }

    @MainActor private func addProjectMenuItem(_ project: Project, to menu: NSMenu) {
        let status = portStatusCache[project.port] ?? PortStatus(isActive: false, cpuUsage: nil, memoryUsage: nil, healthStatus: nil)
        let title = "\(project.name)  :\(project.port)"

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")

        // Use SF Symbols for status
        // Green = running & healthy, Yellow = running but unhealthy, Gray = stopped
        let statusColor: NSColor
        let statusSymbol: String
        let statusDescription: String

        if status.isActive {
            if status.healthStatus == false {
                // Running but health check failed
                statusColor = .systemYellow
                statusSymbol = "exclamationmark.circle.fill"
                statusDescription = "Unhealthy"
            } else {
                // Running and healthy (or no health check)
                statusColor = .systemGreen
                statusSymbol = "circle.fill"
                statusDescription = "Running"
            }
        } else {
            statusColor = .secondaryLabelColor
            statusSymbol = "circle"
            statusDescription = "Stopped"
        }

        if let statusImage = NSImage(systemSymbolName: statusSymbol, accessibilityDescription: statusDescription) {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            let configuredImage = statusImage.withSymbolConfiguration(symbolConfig)
            let tintedImage = NSImage(size: configuredImage?.size ?? statusImage.size, flipped: false) { rect in
                statusColor.set()
                (configuredImage ?? statusImage).draw(in: rect)
                return true
            }
            // Mark non-template so AppKit doesn't re-tint our hand-colored status dots
            // on menu highlight (would turn red/yellow/green dots into the selection color).
            tintedImage.isTemplate = false
            item.image = tintedImage
        }
        let submenu = NSMenu()

        if status.isActive {
            // Show resource usage and health at top of submenu
            if let cpu = status.cpuUsage, let mem = status.memoryUsage {
                let statsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                let cpuStr = String(format: "%.1f%%", cpu)
                let memStr = String(format: "%.1f%%", mem)
                var statsText = "CPU \(cpuStr)   MEM \(memStr)"

                // Add health status if configured
                if let healthy = status.healthStatus {
                    statsText += healthy ? "   ✓ Healthy" : "   ⚠ Unhealthy"
                }

                statsItem.attributedTitle = NSAttributedString(
                    string: statsText,
                    attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                )
                statsItem.isEnabled = false
                submenu.addItem(statsItem)
                submenu.addItem(NSMenuItem.separator())
            }

            let stopItem = NSMenuItem(title: "Stop", action: #selector(stopProject(_:)), keyEquivalent: "")
            stopItem.representedObject = project
            stopItem.target = self
            submenu.addItem(stopItem)

            let restartItem = NSMenuItem(title: "Restart", action: #selector(restartProject(_:)), keyEquivalent: "")
            restartItem.representedObject = project
            restartItem.target = self
            submenu.addItem(restartItem)
        } else {
            let startItem = NSMenuItem(title: "Start", action: #selector(startProject(_:)), keyEquivalent: "")
            startItem.representedObject = project
            startItem.target = self
            submenu.addItem(startItem)
        }

        let openDirItem = NSMenuItem(title: "Open in Finder", action: #selector(openDirectory(_:)), keyEquivalent: "")
        openDirItem.representedObject = project
        openDirItem.target = self
        submenu.addItem(openDirItem)

        let openTerminalItem = NSMenuItem(title: "Open in Terminal", action: #selector(openInTerminal(_:)), keyEquivalent: "")
        openTerminalItem.representedObject = project
        openTerminalItem.target = self
        submenu.addItem(openTerminalItem)

        let openBrowserItem = NSMenuItem(title: "Open in Browser", action: #selector(openInBrowser(_:)), keyEquivalent: "")
        openBrowserItem.representedObject = project
        openBrowserItem.target = self
        submenu.addItem(openBrowserItem)

        let copyUrlItem = NSMenuItem(title: "Copy URL", action: #selector(copyProjectUrl(_:)), keyEquivalent: "")
        copyUrlItem.representedObject = project
        copyUrlItem.target = self
        submenu.addItem(copyUrlItem)

        submenu.addItem(NSMenuItem.separator())

        let editItem = NSMenuItem(title: "Edit...", action: #selector(editProject(_:)), keyEquivalent: "")
        editItem.representedObject = project
        editItem.target = self
        submenu.addItem(editItem)

        let deleteItem = NSMenuItem(title: "Delete...", action: #selector(deleteProject(_:)), keyEquivalent: "")
        deleteItem.representedObject = project
        deleteItem.target = self
        submenu.addItem(deleteItem)

        item.submenu = submenu
        menu.addItem(item)
    }

    // MARK: Project Actions

    @MainActor @objc func startProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? Project else { return }

        // Check for port conflict
        if isPortActive(project.port) {
            let alert = NSAlert()
            alert.messageText = "Port Already in Use"
            alert.informativeText = "Port \(project.port) is already in use by another process. Start anyway?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Start Anyway")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() != .alertFirstButtonReturn {
                return
            }
        }

        startProjectDirectly(project)
    }

    @MainActor func startProjectDirectly(_ project: Project) {
        // Clear user-stopped flag since we're starting it
        userStoppedPorts.remove(project.port)

        // If the port is already bound, kill the existing listener before
        // spawning a new one. This prevents EADDRINUSE cascades where multiple
        // restart attempts each open a new Terminal window that immediately
        // dies because the prior process hasn't released the port yet. Note:
        // userInitiated:false so this kill doesn't get treated as the user
        // stopping the project (which would suppress the very restart we want).
        if isPortActive(project.port) {
            stopProjectByPort(project.port, userInitiated: false) { [weak self] portFreed in
                guard let self = self else { return }
                if portFreed {
                    self.openProjectTerminal(project)
                } else {
                    // Don't spawn a Terminal we know will EADDRINUSE. The
                    // user needs to investigate the stuck listener before
                    // we'll retry.
                    self.sendNotification(
                        title: "Couldn't start \(project.name)",
                        body: "Port \(project.port) is still in use — previous process didn't release it."
                    )
                }
            }
        } else {
            openProjectTerminal(project)
        }
    }

    /// Build the env-prefixed command and hand off to openTerminal. Split out
    /// of startProjectDirectly so the port-conflict path can defer the spawn
    /// without duplicating the command-building logic. Recording lastSpawnAt
    /// here is the single chokepoint that opens the supervised window.
    @MainActor private func openProjectTerminal(_ project: Project, activate: Bool = true) {
        var command = project.startCommand
        if let envVars = project.envVars, !envVars.isEmpty {
            let envPrefix = envVars.map { "\($0.key)='\($0.value)'" }.joined(separator: " ")
            command = "\(envPrefix) \(command)"
        }

        lastSpawnAt[project.port] = Date()
        openTerminal(directory: project.directory, command: command, activate: activate)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.updateMenu()
        }
    }

    @MainActor @objc func stopProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? Project else { return }
        stopProjectByPort(project.port)
    }

    @MainActor func stopProjectByPort(
        _ port: Int,
        userInitiated: Bool = true,
        completion: ((Bool) -> Void)? = nil
    ) {
        if userInitiated {
            userStoppedPorts.insert(port)
        }

        // Optimistic UI update first — toolbar count and menu reflect the
        // stop immediately, without waiting on the kill subprocesses or
        // the next poll. previousPortStates is pinned to false so the
        // confirming poll doesn't fire a redundant "Stopped" notification.
        portStatusCache[port] = PortStatus(
            isActive: false,
            cpuUsage: nil,
            memoryUsage: nil,
            healthStatus: nil
        )
        previousPortStates[port] = false
        rebuildMenu()

        // Run lsof/pkill/kill off main: runWaitingForExit has no timeout,
        // so a stuck subprocess would freeze the UI forever. Even when the
        // subprocesses are fast (~tens of ms each), keeping them off main
        // means clicks like Stop / Restart never block the menu bar.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // lsof flags: -n / -P avoid DNS + service-name lookups,
            // -b / -w avoid blocking kernel calls. Without these, lsof
            // routinely timed out at 10s when launched from inside Harbr,
            // which made Restart silently no-op: the kill never got any
            // PIDs, but the completion fired anyway and Restart "succeeded"
            // while the original server kept running.
            let lsof = SafeProcess.runCapturingOutput(
                launchPath: "/usr/sbin/lsof",
                arguments: ["-nP", "-b", "-w", "-t", "-i", ":\(port)", "-sTCP:LISTEN"],
                timeout: 3
            )

            if let result = lsof {
                let pids = result.stdout
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty }

                for pid in pids {
                    // First kill child processes of this PID
                    SafeProcess.runWaitingForExit(
                        launchPath: "/usr/bin/pkill",
                        arguments: ["-9", "-P", pid]
                    )
                    // Then kill the process itself
                    SafeProcess.runWaitingForExit(
                        launchPath: "/bin/kill",
                        arguments: ["-9", pid]
                    )
                }
            }

            // Verify the port is actually free before reporting success.
            // The native socket check can't hang, so this is the safe
            // source of truth even when lsof fails or the kill subprocesses
            // don't take. Poll up to 3s @100ms so a slow OS reap (the old
            // 0.5s grace) is still covered.
            var portFree = false
            let deadline = Date().addingTimeInterval(3.0)
            while Date() < deadline {
                if !SafeProcess.isPortActive(port) {
                    portFree = true
                    break
                }
                Thread.sleep(forTimeInterval: 0.1)
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !portFree {
                    // Kill didn't take — undo the optimistic UI so the
                    // toolbar count reflects reality on the next poll, and
                    // tell the user so they don't think Restart worked.
                    self.portStatusCache[port] = PortStatus(
                        isActive: true,
                        cpuUsage: nil,
                        memoryUsage: nil,
                        healthStatus: nil
                    )
                    self.previousPortStates[port] = true
                    // Only surface a notification for user-initiated stops.
                    // The internal port-conflict path (startProjectDirectly
                    // calling stop with userInitiated:false) raises its own
                    // notification in restartProjectDirectly.
                    if userInitiated {
                        let name = self.config?.projects.first(where: { $0.port == port })?.name
                            ?? "port \(port)"
                        self.sendNotification(
                            title: "Couldn't stop \(name)",
                            body: "Port \(port) is still in use. The kill didn't take — check the terminal window."
                        )
                    }
                }
                self.updateMenu()
                completion?(portFree)
            }
        }
    }

    @MainActor @objc func restartProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? Project else { return }
        restartProjectDirectly(project)
    }

    @MainActor func restartProjectDirectly(_ project: Project) {
        // Chain start off stop's completion. Completion now reports whether
        // the port is actually free (verified via native socket check, not
        // just "we issued a kill"), so we don't recursively spawn a Terminal
        // that will EADDRINUSE while the original process keeps running.
        // The previous version fired completion unconditionally — when
        // lsof timed out, the kill silently no-op'd and Restart appeared
        // to succeed while the server kept running uninterrupted.
        stopProjectByPort(project.port) { [weak self] portFreed in
            guard let self = self else { return }
            if portFreed {
                self.startProjectDirectly(project)
            } else {
                self.sendNotification(
                    title: "Couldn't restart \(project.name)",
                    body: "Port \(project.port) is still in use — kill didn't take."
                )
            }
        }
    }

    @MainActor @objc func startAllProjects() {
        guard let config = config else { return }

        for project in config.projects {
            let status = portStatusCache[project.port]
            if status?.isActive != true {
                // Route through openProjectTerminal so each project gets its
                // supervised window opened (and env-var handling stays in one
                // place). activate:false because we activate once below.
                openProjectTerminal(project, activate: false)
            }
        }

        // Activate terminal once after all scripts are queued
        activateTerminal()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.updateMenu()
        }
    }

    @MainActor @objc func stopAllProjects() {
        guard let config = config else { return }

        for project in config.projects {
            let status = portStatusCache[project.port]
            if status?.isActive == true {
                stopProjectByPort(project.port)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateMenu()
        }
    }

    @MainActor @objc func openDirectory(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? Project else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: project.directory))
    }

    @MainActor @objc func openInTerminal(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? Project else { return }
        openTerminal(directory: project.directory)
    }

    @MainActor @objc func openInBrowser(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? Project,
              let url = URL(string: "http://localhost:\(project.port)") else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor @objc func copyProjectUrl(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? Project else { return }
        let url = "http://localhost:\(project.port)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    @MainActor @objc func setTerminalApp(_ sender: NSMenuItem) {
        guard let terminal = sender.representedObject as? TerminalApp else { return }
        config?.terminal = terminal
        saveConfig()
    }

    @MainActor @objc func toggleNotifications() {
        config?.notifications = !(config?.notifications ?? true)
        saveConfig()
    }

    @MainActor @objc func toggleLaunchAtLogin() {
        let newValue = !(config?.launchAtLogin ?? false)
        config?.launchAtLogin = newValue

        if newValue {
            installLaunchAgent()
        } else {
            uninstallLaunchAgent()
        }

        saveConfig()
    }

    private func launchAgentPath() -> String {
        return NSString(string: "~/Library/LaunchAgents/com.harbr.app.plist").expandingTildeInPath
    }

    private func installLaunchAgent() {
        let appPath = Bundle.main.bundlePath.isEmpty
            ? ProcessInfo.processInfo.arguments[0]
            : "\(Bundle.main.bundlePath)/Contents/MacOS/Harbr"

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.harbr.app</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(appPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """

        let launchAgentsDir = NSString(string: "~/Library/LaunchAgents").expandingTildeInPath
        let fileManager = FileManager.default

        // Create LaunchAgents directory if needed
        if !fileManager.fileExists(atPath: launchAgentsDir) {
            do {
                try fileManager.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
            } catch {
                Self.launchAgentLog.error("Failed to create LaunchAgents directory: \(error.localizedDescription, privacy: .public)")
                return
            }
        }

        // Write the plist
        do {
            try plistContent.write(toFile: launchAgentPath(), atomically: true, encoding: .utf8)
        } catch {
            Self.launchAgentLog.error("Failed to write LaunchAgent plist at \(self.launchAgentPath(), privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        // Load the agent
        let loaded = SafeProcess.runWaitingForExit(
            launchPath: "/bin/launchctl",
            arguments: ["load", launchAgentPath()]
        )
        if !loaded {
            Self.launchAgentLog.error("launchctl load failed for \(self.launchAgentPath(), privacy: .public) — auto-launch at login will not work until investigated")
        }
    }

    private func uninstallLaunchAgent() {
        let path = launchAgentPath()

        // Unload the agent
        let unloaded = SafeProcess.runWaitingForExit(
            launchPath: "/bin/launchctl",
            arguments: ["unload", path]
        )
        if !unloaded {
            Self.launchAgentLog.error("launchctl unload failed for \(path, privacy: .public)")
        }

        // Remove the plist
        try? FileManager.default.removeItem(atPath: path)
    }

    @MainActor @objc func reloadConfig() {
        loadConfig()
        updateMenu()
    }

    @MainActor @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    @MainActor func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor @objc func addNewProject() {
        currentEditorWindow = ProjectEditorWindow { [weak self] project in
            self?.config?.projects.append(project)
            self?.saveConfig()
        }
        currentEditorWindow?.onDismiss = { [weak self] in
            // Defer release so pending CoreAnimation transactions can flush before
            // the NSWindow deallocates (otherwise CA tries to release a freed
            // _NSWindowTransformAnimation on the next runloop tick → SIGBUS).
            DispatchQueue.main.async {
                self?.currentEditorWindow = nil
            }
        }
        currentEditorWindow?.show()
    }

    @MainActor @objc func editProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? Project else {
            return
        }

        let originalPort = project.port

        currentEditorWindow = ProjectEditorWindow(project: project) { [weak self] updatedProject in
            guard let self = self,
                  let index = self.config?.projects.firstIndex(where: { $0.port == originalPort }) else {
                return
            }
            self.config?.projects[index] = updatedProject
            self.saveConfig()
        }
        currentEditorWindow?.onDismiss = { [weak self] in
            DispatchQueue.main.async {
                self?.currentEditorWindow = nil
            }
        }
        currentEditorWindow?.show()
    }

    @MainActor @objc func deleteProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? Project else { return }

        let alert = NSAlert()
        alert.messageText = "Delete Project"
        alert.informativeText = "Are you sure you want to delete \"\(project.name)\"?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            // Match by port only — it's the unique key. Matching by name+port
            // silently fails when the user has renamed the project after the
            // menu was built (the menu item holds the old Project value).
            config?.projects.removeAll { $0.port == project.port }
            saveConfig()
        }
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = HarbrApp()
app.delegate = delegate
app.setActivationPolicy(.accessory) // This makes it a menu bar only app
app.run()
