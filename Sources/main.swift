//
//  main.swift
//  Harbr
//
//  Copyright (c) 2025 Alexander Hayworth
//  Licensed under the MIT License. See LICENSE file for details.
//

import Cocoa
import Foundation
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
}

/// Application configuration containing all tracked projects.
struct Config: Codable {
    var projects: [Project]
    var terminalApp: TerminalApp?
    var notificationsEnabled: Bool?

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
}

// MARK: - Project Editor Window

/// A modal window for adding or editing project configurations.
class ProjectEditorWindow: NSObject, NSWindowDelegate {
    var window: NSWindow?
    var nameField: NSTextField?
    var portField: NSTextField?
    var directoryField: NSTextField?
    var startCommandField: NSTextField?
    var onSave: ((String, Int, String, String) -> Void)?
    var onCancel: (() -> Void)?
    private var didSave = false

    @MainActor init(project: Project? = nil, onSave: @escaping (String, Int, String, String) -> Void) {
        super.init()
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = project == nil ? "Add Project" : "Edit Project"
        window.center()
        window.delegate = self
        window.isMovableByWindowBackground = true
        self.window = window

        let contentView = NSView(frame: window.contentView!.bounds)

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
        contentView.addSubview(nameField!)

        currentY -= rowHeight

        // Port field
        let portLabel = NSTextField(labelWithString: "Port")
        portLabel.frame = NSRect(x: 20, y: currentY, width: labelWidth, height: 20)
        portLabel.alignment = .right
        portLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(portLabel)

        portField = NSTextField(frame: NSRect(x: fieldX, y: currentY - 2, width: 80, height: 24))
        portField?.stringValue = project != nil ? "\(project!.port)" : ""
        portField?.placeholderString = "3000"
        portField?.font = NSFont.systemFont(ofSize: 13)
        portField?.bezelStyle = .roundedBezel
        contentView.addSubview(portField!)

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
        contentView.addSubview(directoryField!)

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
        contentView.addSubview(startCommandField!)

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

        didSave = true
        onSave?(name, port, expandedDirectory, startCommand)
        window?.close()
    }

    @MainActor @objc func cancel() {
        onCancel?()
        window?.close()
    }

    @MainActor func windowWillClose(_ notification: Notification) {
        if !didSave {
            onCancel?()
        }
    }

    @MainActor func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Main Application

/// The main application delegate that manages the menu bar interface and server monitoring.
class HarbrApp: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var config: Config?
    var timer: Timer?
    var currentEditorWindow: ProjectEditorWindow?
    var previousPortStates: [Int: Bool] = [:]
    var notificationsAuthorized = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sailboat.fill", accessibilityDescription: "Harbr")
            button.image?.isTemplate = true
        }

        loadConfig()

        // Request notification permissions
        requestNotificationPermissions()

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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.notificationsAuthorized = granted
        }
    }

    func sendNotification(title: String, body: String) {
        guard notificationsAuthorized, config?.notifications == true else { return }

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

    /// Opens a terminal window in the specified directory, optionally running a command.
    func openTerminal(directory: String, command: String? = nil, activate: Bool = true) {
        let terminal = config?.terminal ?? .terminal

        let script: String
        switch terminal {
        case .terminal:
            if let cmd = command {
                script = """
                tell application "Terminal"
                    do script "cd '\(directory)' && \(cmd)"
                    \(activate ? "activate" : "")
                end tell
                """
            } else {
                script = """
                tell application "Terminal"
                    do script "cd '\(directory)'"
                    \(activate ? "activate" : "")
                end tell
                """
            }

        case .iterm:
            if let cmd = command {
                script = """
                tell application "iTerm"
                    create window with default profile
                    tell current session of current window
                        write text "cd '\(directory)' && \(cmd)"
                    end tell
                    \(activate ? "activate" : "")
                end tell
                """
            } else {
                script = """
                tell application "iTerm"
                    create window with default profile
                    tell current session of current window
                        write text "cd '\(directory)'"
                    end tell
                    \(activate ? "activate" : "")
                end tell
                """
            }

        case .warp:
            // Warp uses a different approach - open via URL scheme or direct launch
            if let cmd = command {
                script = """
                tell application "Warp"
                    \(activate ? "activate" : "")
                end tell
                delay 0.5
                tell application "System Events"
                    keystroke "cd '\(directory)' && \(cmd)"
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
                    keystroke "cd '\(directory)'"
                    key code 36
                end tell
                """
            }
        }

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
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
        if let scriptObject = NSAppleScript(source: script) {
            var error: NSDictionary?
            scriptObject.executeAndReturnError(&error)
        }
    }

    // MARK: Port Status

    /// Cached status information for a monitored port.
    struct PortStatus {
        let isActive: Bool
        let cpuUsage: Double?
        let memoryUsage: Double?
    }

    /// Cache for port status to avoid blocking the menu on each open.
    var portStatusCache: [Int: PortStatus] = [:]

    /// Checks if a process is listening on the specified port.
    func isPortActive(_ port: Int) -> Bool {
        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-i", ":\(port)", "-sTCP:LISTEN"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return !output.isEmpty && output.contains("LISTEN")
    }

    func getResourceUsage(for port: Int) -> (cpu: Double, mem: Double)? {
        do {
            // Get PIDs for the port
            let pidTask = Process()
            pidTask.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            pidTask.arguments = ["-t", "-i", ":\(port)"]

            let pidPipe = Pipe()
            pidTask.standardOutput = pidPipe
            pidTask.standardError = FileHandle.nullDevice

            try pidTask.run()
            pidTask.waitUntilExit()

            let pidData = pidPipe.fileHandleForReading.readDataToEndOfFile()
            let pidOutput = String(data: pidData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !pidOutput.isEmpty else { return nil }

            let pids = pidOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard !pids.isEmpty else { return nil }

            // Get resource usage for all PIDs in one ps call
            let psTask = Process()
            psTask.executableURL = URL(fileURLWithPath: "/bin/ps")
            psTask.arguments = ["-p", pids.joined(separator: ","), "-o", "%cpu,%mem"]

            let psPipe = Pipe()
            psTask.standardOutput = psPipe
            psTask.standardError = FileHandle.nullDevice

            try psTask.run()
            psTask.waitUntilExit()

            let psData = psPipe.fileHandleForReading.readDataToEndOfFile()
            let psOutput = String(data: psData, encoding: .utf8) ?? ""

            var totalCpu: Double = 0
            var totalMem: Double = 0

            let lines = psOutput.components(separatedBy: "\n")
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
        } catch {
            return nil
        }
    }

    func updateResourceCache() {
        guard let config = config else { return }

        DispatchQueue.global(qos: .background).async { [weak self] in
            var newCache: [Int: PortStatus] = [:]
            var stateChanges: [(project: Project, started: Bool)] = []

            for project in config.projects {
                let isActive = self?.isPortActive(project.port) ?? false
                var cpu: Double? = nil
                var mem: Double? = nil

                if isActive, let usage = self?.getResourceUsage(for: project.port) {
                    cpu = usage.cpu
                    mem = usage.mem
                }

                newCache[project.port] = PortStatus(isActive: isActive, cpuUsage: cpu, memoryUsage: mem)

                // Check for state change
                if let previousState = self?.previousPortStates[project.port] {
                    if previousState != isActive {
                        stateChanges.append((project: project, started: isActive))
                    }
                }
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // Update previous states
                for project in config.projects {
                    self.previousPortStates[project.port] = newCache[project.port]?.isActive ?? false
                }

                // Send notifications for state changes
                for change in stateChanges {
                    if change.started {
                        self.sendNotification(
                            title: "\(change.project.name) Started",
                            body: "Server is now running on port \(change.project.port)"
                        )
                    } else {
                        self.sendNotification(
                            title: "\(change.project.name) Stopped",
                            body: "Server on port \(change.project.port) is no longer running"
                        )
                    }
                }

                self.portStatusCache = newCache
                self.rebuildMenu()
            }
        }
    }

    func updateMenu() {
        // Trigger async update of resource cache
        updateResourceCache()
    }

    @MainActor func rebuildMenu() {
        let menu = NSMenu()

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
            menu.addItem(NSMenuItem(title: "Add Project...", action: #selector(addNewProject), keyEquivalent: "n"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
            statusItem?.menu = menu
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

        for project in config.projects {
            let status = portStatusCache[project.port] ?? PortStatus(isActive: false, cpuUsage: nil, memoryUsage: nil)
            let title = "\(project.name)  :\(project.port)"

            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")

            // Use SF Symbols for status
            if let statusImage = NSImage(systemSymbolName: status.isActive ? "circle.fill" : "circle", accessibilityDescription: status.isActive ? "Running" : "Stopped") {
                let symbolConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
                let tintedImage = statusImage.withSymbolConfiguration(symbolConfig)
                item.image = tintedImage
                if status.isActive {
                    item.image?.isTemplate = false
                    // Create a green-tinted version
                    let greenImage = NSImage(size: statusImage.size, flipped: false) { rect in
                        NSColor.systemGreen.set()
                        statusImage.draw(in: rect)
                        return true
                    }
                    item.image = greenImage
                }
            }
            let submenu = NSMenu()

            if status.isActive {
                // Show resource usage at top of submenu
                if let cpu = status.cpuUsage, let mem = status.memoryUsage {
                    let statsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                    let cpuStr = String(format: "%.1f%%", cpu)
                    let memStr = String(format: "%.1f%%", mem)
                    statsItem.attributedTitle = NSAttributedString(
                        string: "CPU \(cpuStr)   MEM \(memStr)",
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

        prefsItem.submenu = prefsSubmenu
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: Project Actions

    @MainActor @objc func startProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? Project else { return }

        openTerminal(directory: project.directory, command: project.startCommand)

        // Wait a moment then refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.updateMenu()
        }
    }

    @MainActor @objc func stopProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? Project else { return }

        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-t", "-i", ":\(project.port)"]

        let pipe = Pipe()
        task.standardOutput = pipe

        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !output.isEmpty {
            let pids = output.components(separatedBy: "\n")
            for pid in pids {
                let killTask = Process()
                killTask.launchPath = "/bin/kill"
                killTask.arguments = [pid]
                killTask.launch()
                killTask.waitUntilExit()
            }

            // Wait a moment then refresh
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateMenu()
            }
        }
    }

    @MainActor @objc func startAllProjects() {
        guard let config = config else { return }

        for project in config.projects {
            let status = portStatusCache[project.port]
            if status?.isActive != true {
                openTerminal(directory: project.directory, command: project.startCommand, activate: false)
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
                let task = Process()
                task.launchPath = "/usr/sbin/lsof"
                task.arguments = ["-t", "-i", ":\(project.port)"]

                let pipe = Pipe()
                task.standardOutput = pipe

                task.launch()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if !output.isEmpty {
                    let pids = output.components(separatedBy: "\n")
                    for pid in pids {
                        let killTask = Process()
                        killTask.launchPath = "/bin/kill"
                        killTask.arguments = [pid]
                        killTask.launch()
                        killTask.waitUntilExit()
                    }
                }
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

    @MainActor @objc func setTerminalApp(_ sender: NSMenuItem) {
        guard let terminal = sender.representedObject as? TerminalApp else { return }
        config?.terminal = terminal
        saveConfig()
    }

    @MainActor @objc func toggleNotifications() {
        config?.notifications = !(config?.notifications ?? true)
        saveConfig()
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
        currentEditorWindow = ProjectEditorWindow { [weak self] name, port, directory, startCommand in
            let newProject = Project(name: name, port: port, directory: directory, startCommand: startCommand)
            self?.config?.projects.append(newProject)
            self?.saveConfig()
            self?.currentEditorWindow = nil
        }
        currentEditorWindow?.onCancel = { [weak self] in
            self?.currentEditorWindow = nil
        }
        currentEditorWindow?.show()
    }

    @MainActor @objc func editProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? Project,
              let index = config?.projects.firstIndex(where: { $0.name == project.name && $0.port == project.port }) else {
            return
        }

        currentEditorWindow = ProjectEditorWindow(project: project) { [weak self] name, port, directory, startCommand in
            let updatedProject = Project(name: name, port: port, directory: directory, startCommand: startCommand)
            self?.config?.projects[index] = updatedProject
            self?.saveConfig()
            self?.currentEditorWindow = nil
        }
        currentEditorWindow?.onCancel = { [weak self] in
            self?.currentEditorWindow = nil
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
            config?.projects.removeAll { $0.name == project.name && $0.port == project.port }
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
