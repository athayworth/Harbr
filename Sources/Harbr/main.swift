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
    /// Whether to wrap the start command with `script -q` to capture stdout
    /// to a log file Harbr can tail. Defaults to true — the Activity tab
    /// is useless without it. Opt-out exists for edge cases (Docker Compose
    /// allocating its own TTY, custom wrappers that don't survive an outer
    /// PTY) where wrapping breaks the user's setup.
    let captureLogs: Bool?

    var shouldAutoRestart: Bool { autoRestart ?? false }
    var shouldCaptureLogs: Bool { captureLogs ?? true }

    /// Creates a project with default optional values.
    init(name: String, port: Int, directory: String, startCommand: String,
         group: String? = nil, healthCheckUrl: String? = nil,
         envVars: [String: String]? = nil, autoRestart: Bool? = nil,
         captureLogs: Bool? = nil) {
        self.name = name
        self.port = port
        self.directory = directory
        self.startCommand = startCommand
        self.group = group
        self.healthCheckUrl = healthCheckUrl
        self.envVars = envVars
        self.autoRestart = autoRestart
        self.captureLogs = captureLogs
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
    var captureLogsCheckbox: NSButton?
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
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 408),
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
        var currentY: CGFloat = 238

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

        currentY -= 24

        // Capture-logs checkbox. Default is on for new projects so the
        // Activity tab is useful out of the box; existing projects without
        // the field default to on too (shouldCaptureLogs has nil → true).
        captureLogsCheckbox = NSButton(frame: NSRect(x: fieldX, y: currentY - 2, width: fieldWidth, height: 20))
        captureLogsCheckbox?.setButtonType(.switch)
        captureLogsCheckbox?.title = "Capture output for the Activity tab"
        captureLogsCheckbox?.font = NSFont.systemFont(ofSize: 13)
        captureLogsCheckbox?.state = (project?.shouldCaptureLogs ?? true) ? .on : .off
        if let checkbox = captureLogsCheckbox {
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
                self?.applyPackageJsonDefaults(forDirectory: url.path)
            }
        }
    }

    /// Reads package.json (if present) and pre-fills any empty fields with
    /// sensible defaults — name from the package, command from scripts.dev /
    /// start / serve, port from the script flags or the framework's default.
    /// Only fills empty fields so we never clobber a value the user typed.
    /// Vibe-coder targeting: most users picking a Next.js / Vite folder
    /// shouldn't have to know what port their framework binds to.
    @MainActor private func applyPackageJsonDefaults(forDirectory dir: String) {
        let pkgPath = (dir as NSString).appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: pkgPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if (nameField?.stringValue.isEmpty ?? false),
           let pkgName = json["name"] as? String, !pkgName.isEmpty {
            // "my-cool-app" → "My Cool App". Scoped packages ("@org/pkg") get
            // the scope stripped because the app's display name shouldn't
            // leak the npm namespace.
            let stripped = pkgName.split(separator: "/").last.map(String.init) ?? pkgName
            let titled = stripped
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
            nameField?.stringValue = titled
        }

        let scripts = (json["scripts"] as? [String: String]) ?? [:]
        var chosenScriptName: String?
        var chosenScriptBody: String?
        for candidate in ["dev", "start", "serve"] {
            if let body = scripts[candidate] {
                chosenScriptName = candidate
                chosenScriptBody = body
                break
            }
        }

        if (startCommandField?.stringValue.isEmpty ?? false), let scriptName = chosenScriptName {
            startCommandField?.stringValue = "npm run \(scriptName)"
        }

        if portField?.stringValue.isEmpty ?? false {
            if let body = chosenScriptBody, let detected = detectPort(from: body) {
                portField?.stringValue = "\(detected)"
            } else {
                let deps = (json["dependencies"] as? [String: Any]) ?? [:]
                let devDeps = (json["devDependencies"] as? [String: Any]) ?? [:]
                let allDeps = Set(deps.keys).union(devDeps.keys)
                let defaultPort: Int? = {
                    if allDeps.contains("next") { return 3000 }
                    if allDeps.contains("vite") { return 5173 }
                    if allDeps.contains("astro") { return 4321 }
                    if allDeps.contains("remix") || allDeps.contains("@remix-run/dev") { return 3000 }
                    if allDeps.contains("react-scripts") { return 3000 }
                    if allDeps.contains("@sveltejs/kit") { return 5173 }
                    if allDeps.contains("nuxt") { return 3000 }
                    return nil
                }()
                if let port = defaultPort {
                    portField?.stringValue = "\(port)"
                }
            }
        }
    }

    /// Pulls a port number out of a dev-script string. Handles `-p 3001`,
    /// `--port=3001`, and `PORT=3001 next dev`. Stops at the first match
    /// because in practice scripts don't specify a port twice.
    private func detectPort(from script: String) -> Int? {
        let patterns = [
            #"--port[=\s]+(\d+)"#,
            #"\s-p[=\s]+(\d+)"#,
            #"\bPORT=(\d+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(script.startIndex..., in: script)
            guard let match = regex.firstMatch(in: script, range: nsRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: script),
                  let port = Int(script[range]) else { continue }
            return port
        }
        return nil
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
        let captureLogs = captureLogsCheckbox?.state == .on

        let project = Project(
            name: name,
            port: port,
            directory: expandedDirectory,
            startCommand: startCommand,
            group: group,
            healthCheckUrl: healthCheckUrl,
            envVars: existingEnvVars,
            autoRestart: autoRestart,
            captureLogs: captureLogs
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

// MARK: - Project Scanner

/// A project discovered by scanning a folder for `package.json` files. The
/// fields mirror what the editor would prompt for, so adding a detected
/// project is just "convert to Project + save."
struct DetectedProject {
    let name: String
    let port: Int?
    let directory: String
    let command: String
    let framework: String?
}

/// Walks a directory tree looking for `package.json` files and turns each
/// one into a `DetectedProject`. The scanner is the implementation behind
/// the onboarding flow that lets a vibe coder say "Here's where my projects
/// live, find them" instead of typing port/directory/command for each.
enum ProjectScanner {
    /// Directories we never recurse into. Some (node_modules, .git, dist)
    /// would never contain a real project; others (Pods, target, .venv)
    /// can technically contain package.json files from tooling vendor
    /// dirs and would produce false positives.
    static let skipDirs: Set<String> = [
        "node_modules", ".git", ".next", "dist", "build",
        ".vercel", ".turbo", ".cache", "vendor", ".svelte-kit",
        ".nuxt", ".output", "tmp", "Pods", ".gradle",
        "venv", ".venv", "__pycache__", "target"
    ]

    /// Recursively scans `rootPath` up to `maxDepth` levels deep. Stops
    /// descending into a directory the moment we find a package.json there
    /// — the inner package.jsons of a monorepo are almost always workspace
    /// packages, not separately-runnable projects.
    static func scan(rootPath: String, maxDepth: Int = 4) -> [DetectedProject] {
        var results: [DetectedProject] = []
        let fm = FileManager.default
        var stack: [(String, Int)] = [(rootPath, 0)]

        while let (path, depth) = stack.popLast() {
            let pkgPath = (path as NSString).appendingPathComponent("package.json")
            if fm.fileExists(atPath: pkgPath) {
                if let detected = parsePackageJson(at: pkgPath, directory: path) {
                    results.append(detected)
                }
                continue
            }
            if depth >= maxDepth { continue }
            guard let children = try? fm.contentsOfDirectory(atPath: path) else { continue }
            for child in children {
                if skipDirs.contains(child) || child.hasPrefix(".") { continue }
                let childPath = (path as NSString).appendingPathComponent(child)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: childPath, isDirectory: &isDir), isDir.boolValue {
                    stack.append((childPath, depth + 1))
                }
            }
        }
        return results.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private static func parsePackageJson(at path: String, directory: String) -> DetectedProject? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let scripts = (json["scripts"] as? [String: String]) ?? [:]
        var scriptName: String?
        var scriptBody: String?
        for candidate in ["dev", "start", "serve"] {
            if let body = scripts[candidate] {
                scriptName = candidate
                scriptBody = body
                break
            }
        }
        // If a package has no runnable dev script, it's almost certainly a
        // library or a workspace child — not something a user would want
        // to "start" from a menu bar.
        guard let chosenName = scriptName else { return nil }

        let rawName = (json["name"] as? String) ?? URL(fileURLWithPath: directory).lastPathComponent
        let stripped = rawName.split(separator: "/").last.map(String.init) ?? rawName
        let pretty = stripped
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")

        var port: Int? = nil
        var framework: String? = nil
        if let body = scriptBody { port = extractPort(from: body) }

        let deps = (json["dependencies"] as? [String: Any]) ?? [:]
        let devDeps = (json["devDependencies"] as? [String: Any]) ?? [:]
        let allDeps = Set(deps.keys).union(devDeps.keys)

        if allDeps.contains("next") { framework = "Next.js"; if port == nil { port = 3000 } }
        else if allDeps.contains("vite") { framework = "Vite"; if port == nil { port = 5173 } }
        else if allDeps.contains("astro") { framework = "Astro"; if port == nil { port = 4321 } }
        else if allDeps.contains("@sveltejs/kit") { framework = "SvelteKit"; if port == nil { port = 5173 } }
        else if allDeps.contains("nuxt") { framework = "Nuxt"; if port == nil { port = 3000 } }
        else if allDeps.contains("react-scripts") { framework = "CRA"; if port == nil { port = 3000 } }
        else if allDeps.contains("remix") || allDeps.contains("@remix-run/dev") { framework = "Remix"; if port == nil { port = 3000 } }
        else if allDeps.contains("express") { framework = "Express" }
        else if allDeps.contains("fastify") { framework = "Fastify" }

        return DetectedProject(
            name: pretty,
            port: port,
            directory: directory,
            command: "npm run \(chosenName)",
            framework: framework
        )
    }

    static func extractPort(from script: String) -> Int? {
        let patterns = [#"--port[=\s]+(\d+)"#, #"\s-p[=\s]+(\d+)"#, #"\bPORT=(\d+)"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(script.startIndex..., in: script)
            guard let match = regex.firstMatch(in: script, range: nsRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: script),
                  let port = Int(script[range]) else { continue }
            return port
        }
        return nil
    }
}

/// Modal-style window that walks the user through scanning a folder and
/// picking which detected projects to add. Designed to be the friendly
/// first-run path so a new user doesn't need to know what a port is to
/// get value from Harbr.
class ProjectScannerWindow: NSObject, NSWindowDelegate {
    var window: NSWindow?
    private var pathField: NSTextField?
    private var scanButton: NSButton?
    private var statusLabel: NSTextField?
    private var resultsStack: NSStackView?
    private var addButton: NSButton?

    private var detected: [DetectedProject] = []
    private var checkboxes: [NSButton] = []
    private let existingDirs: Set<String>
    private let existingPorts: Set<Int>

    var onAdd: (([Project]) -> Void)?
    var onDismiss: (() -> Void)?
    private var didDismiss = false

    @MainActor init(existingProjects: [Project], onAdd: @escaping ([Project]) -> Void) {
        self.existingDirs = Set(existingProjects.map { NSString(string: $0.directory).expandingTildeInPath })
        self.existingPorts = Set(existingProjects.map { $0.port })
        self.onAdd = onAdd
        super.init()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Find Projects"
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 360)
        self.window = window

        guard let content = window.contentView else { return }

        let intro = NSTextField(labelWithString: "Pick a folder where your projects live. Harbr will scan it for runnable apps and let you add them with one click.")
        intro.frame = NSRect(x: 20, y: 450, width: 540, height: 36)
        intro.lineBreakMode = .byWordWrapping
        intro.maximumNumberOfLines = 2
        intro.font = NSFont.systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        content.addSubview(intro)

        let pathField = NSTextField(frame: NSRect(x: 20, y: 410, width: 410, height: 24))
        pathField.placeholderString = "~/Projects"
        pathField.stringValue = NSString(string: "~/Projects").expandingTildeInPath
        pathField.bezelStyle = .roundedBezel
        pathField.font = NSFont.systemFont(ofSize: 13)
        content.addSubview(pathField)
        self.pathField = pathField

        let browseButton = NSButton(frame: NSRect(x: 438, y: 408, width: 60, height: 26))
        browseButton.title = "Browse"
        browseButton.bezelStyle = .rounded
        browseButton.target = self
        browseButton.action = #selector(browse)
        content.addSubview(browseButton)

        let scanButton = NSButton(frame: NSRect(x: 502, y: 408, width: 58, height: 26))
        scanButton.title = "Scan"
        scanButton.bezelStyle = .rounded
        scanButton.keyEquivalent = "\r"
        scanButton.target = self
        scanButton.action = #selector(runScan)
        if #available(macOS 11.0, *) { scanButton.bezelColor = .controlAccentColor }
        content.addSubview(scanButton)
        self.scanButton = scanButton

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 20, y: 378, width: 540, height: 20)
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        content.addSubview(statusLabel)
        self.statusLabel = statusLabel

        let scroll = NSScrollView(frame: NSRect(x: 20, y: 70, width: 540, height: 300))
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.drawsBackground = false
        // Make the document view the stack directly and pin its width to the
        // scroll view's clip view. The previous wrapper-view layout had no
        // width constraint on the wrapper, so the stack auto-compressed
        // horizontally and every row collapsed to its minimum width — the
        // checkbox + a sliver of label text overlapping at the bottom-left.
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        content.addSubview(scroll)
        self.resultsStack = stack

        let cancelButton = NSButton(frame: NSRect(x: 380, y: 20, width: 80, height: 32))
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        content.addSubview(cancelButton)

        let addButton = NSButton(frame: NSRect(x: 468, y: 20, width: 92, height: 32))
        addButton.title = "Add"
        addButton.bezelStyle = .rounded
        addButton.target = self
        addButton.action = #selector(addSelected)
        addButton.isEnabled = false
        if #available(macOS 11.0, *) { addButton.bezelColor = .controlAccentColor }
        content.addSubview(addButton)
        self.addButton = addButton
    }

    @MainActor @objc private func browse() {
        guard let window = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] resp in
            if resp == .OK, let url = panel.url {
                self?.pathField?.stringValue = url.path
                self?.runScan()
            }
        }
    }

    @MainActor @objc private func runScan() {
        guard let path = pathField?.stringValue, !path.isEmpty else { return }
        let expanded = NSString(string: path).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
            statusLabel?.stringValue = "Folder not found."
            return
        }
        statusLabel?.stringValue = "Scanning…"
        scanButton?.isEnabled = false
        addButton?.isEnabled = false
        let existingDirs = self.existingDirs
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let raw = ProjectScanner.scan(rootPath: expanded)
            // Drop directories already configured so the user isn't offered
            // a project they've already added.
            let filtered = raw.filter { !existingDirs.contains($0.directory) }
            DispatchQueue.main.async { [weak self] in
                self?.presentResults(filtered, alreadyAdded: raw.count - filtered.count)
            }
        }
    }

    @MainActor private func presentResults(_ projects: [DetectedProject], alreadyAdded: Int) {
        detected = projects
        checkboxes.forEach { $0.removeFromSuperview() }
        checkboxes.removeAll()
        resultsStack?.arrangedSubviews.forEach { $0.removeFromSuperview() }
        scanButton?.isEnabled = true

        if projects.isEmpty {
            let msg: String
            if alreadyAdded > 0 {
                msg = "No new projects found (\(alreadyAdded) already added)."
            } else {
                msg = "No runnable projects found in that folder."
            }
            statusLabel?.stringValue = msg
            addButton?.isEnabled = false
            return
        }

        let suffix = alreadyAdded > 0 ? " (\(alreadyAdded) already added)" : ""
        statusLabel?.stringValue = "Found \(projects.count) project\(projects.count == 1 ? "" : "s")\(suffix). Pick which to add."
        addButton?.isEnabled = true
        addButton?.title = "Add \(projects.count)"

        for (idx, project) in projects.enumerated() {
            let row = makeRow(for: project, index: idx)
            resultsStack?.addArrangedSubview(row)
        }
    }

    @MainActor private func makeRow(for project: DetectedProject, index: Int) -> NSView {
        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleSelection(_:)))
        checkbox.tag = index
        checkbox.state = .on
        checkboxes.append(checkbox)

        let title = NSMutableAttributedString(
            string: project.name,
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                         .foregroundColor: NSColor.labelColor]
        )
        if let port = project.port {
            title.append(NSAttributedString(
                string: "  :\(port)",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                             .foregroundColor: NSColor.secondaryLabelColor]
            ))
        }
        if let fw = project.framework {
            title.append(NSAttributedString(
                string: "   \(fw)",
                attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .regular),
                             .foregroundColor: NSColor.tertiaryLabelColor]
            ))
        }
        let nameLabel = NSTextField(labelWithAttributedString: title)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Show ~ for the user's home; otherwise show the full path (relevant
        // for projects on external drives like /Volumes/...). Truncate
        // middle so the project's leaf folder stays readable.
        let displayPath = project.directory.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        let pathLabel = NSTextField(labelWithString: displayPath)
        pathLabel.font = NSFont.systemFont(ofSize: 10)
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pathLabel.cell?.truncatesLastVisibleLine = true

        // Each row is now itself a stack: name+path on the right, checkbox
        // on the left. Stack views derive a real intrinsic size from their
        // arranged subviews, which is what the previous hand-rolled
        // constraint layout was missing — and which is why the rows all
        // collapsed in your screenshot.
        let textStack = NSStackView(views: [nameLabel, pathLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let row = NSStackView(views: [checkbox, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    @MainActor @objc private func toggleSelection(_ sender: NSButton) {
        let count = checkboxes.filter { $0.state == .on }.count
        addButton?.isEnabled = count > 0
        addButton?.title = count > 0 ? "Add \(count)" : "Add"
    }

    @MainActor @objc private func addSelected() {
        // For port collisions, prefer the detected value; bump duplicates by
        // +1 until free so two Next.js projects don't both claim 3000 and
        // immediately fail to start. The user can adjust later in the editor.
        var taken = existingPorts
        var toAdd: [Project] = []
        for (idx, checkbox) in checkboxes.enumerated() {
            guard checkbox.state == .on, idx < detected.count else { continue }
            let d = detected[idx]
            var port = d.port ?? 3000
            while taken.contains(port) { port += 1 }
            taken.insert(port)
            toAdd.append(Project(
                name: d.name,
                port: port,
                directory: d.directory,
                startCommand: d.command,
                group: nil,
                healthCheckUrl: nil,
                envVars: nil,
                autoRestart: nil
            ))
        }
        onAdd?(toAdd)
        dismiss()
    }

    @MainActor @objc private func cancel() { dismiss() }

    @MainActor private func dismiss() {
        guard !didDismiss else { return }
        didDismiss = true
        window?.orderOut(nil)
        onDismiss?()
    }

    func windowWillClose(_ notification: Notification) { dismiss() }

    @MainActor func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Main Window

/// Tabs in the desktop window's sidebar. Kept as a string enum so the
/// title doubles as the sidebar row label and the value is stable for
/// future settings persistence.
enum MainWindowTab: String, CaseIterable {
    case projects = "Projects"
    case activity = "Activity"
    case settings = "Settings"

    var sfSymbol: String {
        switch self {
        case .projects: return "list.bullet.rectangle"
        case .activity: return "text.alignleft"
        case .settings: return "gearshape"
        }
    }
}

/// Tiny inline CPU sparkline. Renders the recent samples as a filled path
/// from baseline to value, tinted by the latest sample so a hot project
/// reads as orange/red even without looking at the number column. Drawn
/// directly in NSView because Swift Charts would require NSHostingView and
/// the visual is simple enough that the bridge isn't worth it.
private class SparklineView: NSView {
    var samples: [Double] = [] { didSet { needsDisplay = true } }
    /// Y-axis ceiling. Pinned at 100 so two projects' sparklines are
    /// directly comparable — auto-scaling would make a low-CPU project's
    /// minor blip look as dramatic as a high-CPU project's spike.
    var ceiling: Double = 100

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard samples.count > 1 else {
            // Single sample or empty: just draw the baseline so the cell
            // doesn't look broken before the second poll lands.
            NSColor.separatorColor.set()
            NSBezierPath(rect: NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)).fill()
            return
        }

        let stepX = bounds.width / CGFloat(samples.count - 1)
        let latest = samples.last ?? 0
        let tint: NSColor = latest >= 50 ? .systemRed
                          : latest >= 20 ? .systemOrange
                          : .secondaryLabelColor

        // Fill: from baseline up to value at each sample. Translucent so
        // overlapping sparklines (if we ever stack them) don't blot out
        // the row underneath.
        let fillPath = NSBezierPath()
        fillPath.move(to: NSPoint(x: 0, y: bounds.height))
        for (i, sample) in samples.enumerated() {
            let x = CGFloat(i) * stepX
            let yNorm = min(max(sample / ceiling, 0), 1)
            let y = bounds.height - (CGFloat(yNorm) * bounds.height)
            fillPath.line(to: NSPoint(x: x, y: y))
        }
        fillPath.line(to: NSPoint(x: bounds.width, y: bounds.height))
        fillPath.close()
        tint.withAlphaComponent(0.22).set()
        fillPath.fill()

        // Stroke: same path without the bottom closure, full opacity.
        let strokePath = NSBezierPath()
        for (i, sample) in samples.enumerated() {
            let x = CGFloat(i) * stepX
            let yNorm = min(max(sample / ceiling, 0), 1)
            let y = bounds.height - (CGFloat(yNorm) * bounds.height)
            if i == 0 { strokePath.move(to: NSPoint(x: x, y: y)) }
            else { strokePath.line(to: NSPoint(x: x, y: y)) }
        }
        strokePath.lineWidth = 1.5
        strokePath.lineJoinStyle = .round
        tint.set()
        strokePath.stroke()
    }
}

/// A clickable sidebar row. Hand-drawn because NSTableView in source-list
/// style wouldn't render any rows in our setup (the table view's
/// auto-sizing inside an NSScrollView came up empty even with explicit
/// reloadData), and the look-and-feel we want — icon + label, accent
/// highlight on selection, full row click target — is faster to draw
/// directly than to fight cell-view lifecycle.
private class SidebarTabView: NSView {
    let tab: MainWindowTab
    var isSelected: Bool = false { didSet { needsDisplay = true; updateColors() } }
    var onClick: (() -> Void)?
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init(tab: MainWindowTab) {
        self.tab = tab
        super.init(frame: .zero)
        iconView.image = NSImage(systemSymbolName: tab.sfSymbol, accessibilityDescription: tab.rawValue)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        label.stringValue = tab.rawValue
        label.font = NSFont.systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateColors() {
        iconView.contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
        label.font = NSFont.systemFont(ofSize: 13, weight: isSelected ? .medium : .regular)
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.18).set()
            let inset = bounds.insetBy(dx: 8, dy: 2)
            NSBezierPath(roundedRect: inset, xRadius: 6, yRadius: 6).fill()
        }
    }
}

/// The desktop window — a sidebar + content area surface where users can
/// see all their projects in a sortable table, peek at recent server
/// output, and adjust app-wide settings. The menu bar dropdown stays the
/// primary surface; this window is the "deep view" for things that don't
/// fit a 300px-wide menu.
///
/// Built as one window with three swappable content views rather than
/// NSTabViewController because the parent project doesn't use view
/// controllers and the visual design we want (sidebar selection driving
/// the right pane) is simpler with manual view swapping.
class HarbrMainWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    weak var app: HarbrApp?
    var window: NSWindow?

    private var sidebarTabViews: [SidebarTabView] = []
    private var contentContainer: NSView?
    private var currentTab: MainWindowTab = .projects

    // Projects tab
    private var projectsTable: NSTableView?

    // Activity tab
    private var activityProjectList: NSTableView?
    private var activityTextView: NSTextView?
    private var activityRefreshTimer: Timer?
    private var activitySelectedPort: Int?

    // Settings tab
    private var terminalPopup: NSPopUpButton?
    private var notificationsCheckbox: NSButton?
    private var launchAtLoginCheckbox: NSButton?
    private var captureLogsDefaultLabel: NSTextField?

    var onDismiss: (() -> Void)?
    private var didDismiss = false

    @MainActor init(app: HarbrApp) {
        self.app = app
        super.init()
        buildWindow()
    }

    @MainActor private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Harbr"
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 420)
        if #available(macOS 11.0, *) {
            window.titlebarAppearsTransparent = false
            window.toolbarStyle = .unified
        }
        self.window = window

        guard let content = window.contentView else { return }

        // Sidebar. Use NSVisualEffectView with the system .sidebar material
        // so it picks up the correct vibrancy + auto-adapts to light/dark
        // mode. The previous NSView + layer.backgroundColor approach
        // captured NSColor.controlBackgroundColor as a CGColor at init time,
        // which doesn't track appearance changes — switching the Mac to
        // dark mode left the sidebar stuck white.
        let sidebarWidth: CGFloat = 180
        let sidebarContainer = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: sidebarWidth, height: 560))
        sidebarContainer.material = .sidebar
        sidebarContainer.blendingMode = .behindWindow
        sidebarContainer.state = .active
        sidebarContainer.autoresizingMask = [.height]
        content.addSubview(sidebarContainer)

        let tabStack = NSStackView()
        tabStack.orientation = .vertical
        tabStack.alignment = .leading
        tabStack.spacing = 4
        tabStack.edgeInsets = NSEdgeInsets(top: 16, left: 0, bottom: 16, right: 0)
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.addSubview(tabStack)
        NSLayoutConstraint.activate([
            tabStack.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            tabStack.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            tabStack.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor)
        ])

        for tab in MainWindowTab.allCases {
            let view = SidebarTabView(tab: tab)
            view.onClick = { [weak self] in self?.switchTo(tab) }
            sidebarTabViews.append(view)
            tabStack.addArrangedSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: tabStack.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: tabStack.trailingAnchor)
            ])
        }

        // Divider
        let divider = NSBox(frame: NSRect(x: sidebarWidth, y: 0, width: 1, height: 560))
        divider.boxType = .separator
        divider.autoresizingMask = [.height]
        content.addSubview(divider)

        // Content container
        let container = NSView(frame: NSRect(x: sidebarWidth + 1, y: 0, width: 880 - sidebarWidth - 1, height: 560))
        container.autoresizingMask = [.height, .width]
        content.addSubview(container)
        self.contentContainer = container

        switchTo(.projects)
    }

    // MARK: Tables (Projects + Activity project picker)

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === activityProjectList { return app?.config?.projects.count ?? 0 }
        if tableView === projectsTable { return app?.config?.projects.count ?? 0 }
        return 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === activityProjectList {
            guard let project = app?.config?.projects[safe: row] else { return nil }
            let cell = NSTableCellView()
            let dot = NSImageView(frame: NSRect(x: 6, y: 7, width: 12, height: 12))
            let active = app?.portStatusCache[project.port]?.isActive ?? false
            dot.image = NSImage(systemSymbolName: active ? "circle.fill" : "circle",
                                accessibilityDescription: active ? "Running" : "Stopped")
            dot.contentTintColor = active ? .systemGreen : .tertiaryLabelColor
            cell.addSubview(dot)
            let label = NSTextField(labelWithString: "\(project.name)  :\(project.port)")
            label.frame = NSRect(x: 26, y: 4, width: 220, height: 20)
            label.font = NSFont.systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingTail
            cell.addSubview(label)
            return cell
        }
        if tableView === projectsTable, let id = tableColumn?.identifier.rawValue {
            return projectsCellView(forColumn: id, row: row)
        }
        return nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView === activityProjectList { return 26 }
        return 28
    }

    @MainActor private func switchTo(_ tab: MainWindowTab) {
        currentTab = tab
        for view in sidebarTabViews {
            view.isSelected = (view.tab == tab)
        }
        // Tear down per-tab state so the Activity timer doesn't keep firing
        // while we're looking at Settings.
        activityRefreshTimer?.invalidate()
        activityRefreshTimer = nil
        contentContainer?.subviews.forEach { $0.removeFromSuperview() }
        guard let container = contentContainer else { return }
        switch tab {
        case .projects: buildProjectsTab(in: container)
        case .activity: buildActivityTab(in: container)
        case .settings: buildSettingsTab(in: container)
        }
    }

    // MARK: Projects tab

    @MainActor private func buildProjectsTab(in container: NSView) {
        let bounds = container.bounds

        let title = NSTextField(labelWithString: "Your Projects")
        title.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        title.frame = NSRect(x: 20, y: bounds.height - 44, width: 400, height: 28)
        title.autoresizingMask = [.minYMargin]
        container.addSubview(title)

        // Right-side toolbar (top): Start All, Stop All, Scan, Add
        let toolbarY = bounds.height - 44
        let startAll = NSButton(title: "Start All", target: app, action: #selector(HarbrApp.startAllProjects))
        startAll.bezelStyle = .rounded
        startAll.frame = NSRect(x: bounds.width - 440, y: toolbarY, width: 80, height: 28)
        startAll.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(startAll)

        let stopAll = NSButton(title: "Stop All", target: app, action: #selector(HarbrApp.stopAllProjects))
        stopAll.bezelStyle = .rounded
        stopAll.frame = NSRect(x: bounds.width - 354, y: toolbarY, width: 78, height: 28)
        stopAll.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(stopAll)

        let scanButton = NSButton(title: "Scan Folder", target: app, action: #selector(HarbrApp.scanForProjects))
        scanButton.bezelStyle = .rounded
        scanButton.frame = NSRect(x: bounds.width - 270, y: toolbarY, width: 100, height: 28)
        scanButton.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(scanButton)

        let addButton = NSButton(title: "Add Project", target: app, action: #selector(HarbrApp.addNewProject))
        addButton.bezelStyle = .rounded
        addButton.frame = NSRect(x: bounds.width - 164, y: toolbarY, width: 96, height: 28)
        addButton.autoresizingMask = [.minXMargin, .minYMargin]
        if #available(macOS 11.0, *) { addButton.bezelColor = .controlAccentColor }
        container.addSubview(addButton)

        let reloadButton = NSButton(title: "↻", target: app, action: #selector(HarbrApp.reloadConfig))
        reloadButton.bezelStyle = .rounded
        reloadButton.frame = NSRect(x: bounds.width - 60, y: toolbarY, width: 40, height: 28)
        reloadButton.autoresizingMask = [.minXMargin, .minYMargin]
        reloadButton.toolTip = "Reload config from disk"
        container.addSubview(reloadButton)

        // Table
        let tableScroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: bounds.width - 40, height: bounds.height - 84))
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .lineBorder
        tableScroll.autoresizingMask = [.width, .height]

        let table = NSTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.rowSizeStyle = .default
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.style = .inset
        table.doubleAction = #selector(projectsTableDoubleClicked)
        table.target = self

        // Widths total 684px which fits in the 880px window's ~699px
        // content area while leaving room for the per-row primary action
        // button + ⋯ overflow menu. Sparkline goes right after CPU so a
        // hot project's number + trend read together.
        let columns: [(String, String, CGFloat)] = [
            ("status", "", 24),
            ("name", "Name", 140),
            ("port", "Port", 50),
            ("cpu", "CPU", 50),
            ("trend", "Trend", 90),
            ("mem", "Memory", 70),
            ("framework", "Type", 70),
            ("actions", "", 190)
        ]
        for (id, title, width) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            col.minWidth = width * 0.6
            table.addTableColumn(col)
        }
        table.dataSource = self
        table.delegate = self
        tableScroll.documentView = table
        container.addSubview(tableScroll)
        self.projectsTable = table
        table.reloadData()
    }

    @MainActor private func projectsCellView(forColumn id: String, row: Int) -> NSView? {
        guard let project = app?.config?.projects[safe: row] else { return nil }
        let status = app?.portStatusCache[project.port]
        let cell = NSTableCellView()
        switch id {
        case "status":
            let dot = NSImageView(frame: NSRect(x: 4, y: 6, width: 14, height: 14))
            let active = status?.isActive ?? false
            let unhealthy = active && status?.healthStatus == false
            dot.image = NSImage(systemSymbolName: active ? "circle.fill" : "circle",
                                accessibilityDescription: active ? "Running" : "Stopped")
            dot.contentTintColor = unhealthy ? .systemYellow
                                  : active ? .systemGreen
                                  : .tertiaryLabelColor
            cell.addSubview(dot)
        case "name":
            let label = NSTextField(labelWithString: project.name)
            label.frame = NSRect(x: 0, y: 4, width: 200, height: 20)
            label.lineBreakMode = .byTruncatingTail
            cell.addSubview(label)
        case "port":
            let label = NSTextField(labelWithString: "\(project.port)")
            label.frame = NSRect(x: 0, y: 4, width: 60, height: 20)
            label.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            cell.addSubview(label)
        case "cpu":
            let val = (status?.isActive == true) ? (status?.cpuUsage).map { String(format: "%.0f%%", $0) } ?? "—" : "—"
            let label = NSTextField(labelWithString: val)
            label.frame = NSRect(x: 0, y: 4, width: 50, height: 20)
            label.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            label.textColor = .secondaryLabelColor
            cell.addSubview(label)
        case "trend":
            // Sparkline picks up live samples from the poll. Empty / single-
            // sample is handled inside the view itself (draws a baseline).
            let sparkline = SparklineView(frame: NSRect(x: 0, y: 4, width: 80, height: 20))
            sparkline.samples = app?.cpuHistory[project.port] ?? []
            cell.addSubview(sparkline)
        case "mem":
            let val = (status?.isActive == true) ? (status?.memoryUsage).map { HarbrApp.formatMemory($0) } ?? "—" : "—"
            let label = NSTextField(labelWithString: val)
            label.frame = NSRect(x: 0, y: 4, width: 90, height: 20)
            label.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            label.textColor = .secondaryLabelColor
            cell.addSubview(label)
        case "framework":
            // Best-effort: re-parse package.json once per row build. Cheap
            // because it's only the rows currently scrolled into view.
            let pkgPath = (project.directory as NSString).appendingPathComponent("package.json")
            var framework = "—"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: pkgPath)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let deps = (json["dependencies"] as? [String: Any]) ?? [:]
                let devDeps = (json["devDependencies"] as? [String: Any]) ?? [:]
                let allDeps = Set(deps.keys).union(devDeps.keys)
                if allDeps.contains("next") { framework = "Next.js" }
                else if allDeps.contains("vite") { framework = "Vite" }
                else if allDeps.contains("astro") { framework = "Astro" }
                else if allDeps.contains("@sveltejs/kit") { framework = "SvelteKit" }
                else if allDeps.contains("nuxt") { framework = "Nuxt" }
                else if allDeps.contains("remix") || allDeps.contains("@remix-run/dev") { framework = "Remix" }
                else if allDeps.contains("react-scripts") { framework = "CRA" }
                else if allDeps.contains("express") { framework = "Express" }
                else if allDeps.contains("fastify") { framework = "Fastify" }
            }
            let label = NSTextField(labelWithString: framework)
            label.frame = NSRect(x: 0, y: 4, width: 100, height: 20)
            label.textColor = .secondaryLabelColor
            label.font = NSFont.systemFont(ofSize: 12)
            cell.addSubview(label)
        case "actions":
            let active = status?.isActive ?? false
            let primary = NSButton(title: active ? "Restart" : "Start",
                                   target: self,
                                   action: active ? #selector(restartFromTable(_:)) : #selector(startFromTable(_:)))
            primary.bezelStyle = .rounded
            primary.controlSize = .small
            primary.tag = row
            primary.frame = NSRect(x: 0, y: 4, width: 70, height: 22)
            cell.addSubview(primary)

            if active {
                let stop = NSButton(title: "Stop", target: self, action: #selector(stopFromTable(_:)))
                stop.bezelStyle = .rounded
                stop.controlSize = .small
                stop.tag = row
                stop.frame = NSRect(x: 76, y: 4, width: 56, height: 22)
                cell.addSubview(stop)
            }

            // Overflow menu (⋯). Cheaper than crowding the column with
            // five buttons and a more familiar Mac affordance for
            // secondary actions.
            let overflow = NSPopUpButton(frame: NSRect(x: active ? 138 : 76, y: 4, width: 40, height: 22), pullsDown: true)
            overflow.bezelStyle = .rounded
            overflow.controlSize = .small
            overflow.addItem(withTitle: "⋯")
            overflow.lastItem?.image = nil
            for (title, sel) in [
                ("Edit…", #selector(editFromTable(_:))),
                ("Open in Finder", #selector(openFinderFromTable(_:))),
                ("Open in Terminal", #selector(openTerminalFromTable(_:))),
                ("Open in Browser", #selector(openBrowserFromTable(_:))),
                ("Copy URL", #selector(copyUrlFromTable(_:))),
                ("", nil as Selector?),  // separator placeholder
                ("Delete…", #selector(deleteFromTable(_:)))
            ] as [(String, Selector?)] {
                if title.isEmpty {
                    overflow.menu?.addItem(.separator())
                    continue
                }
                let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
                item.target = self
                item.representedObject = row
                overflow.menu?.addItem(item)
            }
            cell.addSubview(overflow)
        default:
            break
        }
        return cell
    }

    @MainActor @objc private func projectsTableDoubleClicked() {
        guard let row = projectsTable?.selectedRow, row >= 0,
              let project = app?.config?.projects[safe: row] else { return }
        let active = app?.portStatusCache[project.port]?.isActive ?? false
        if active {
            app?.restartProjectDirectly(project)
        } else {
            app?.startProjectDirectly(project)
        }
    }

    @MainActor @objc private func startFromTable(_ sender: NSButton) {
        guard let project = app?.config?.projects[safe: sender.tag] else { return }
        app?.startProjectDirectly(project)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.projectsTable?.reloadData()
        }
    }

    @MainActor @objc private func stopFromTable(_ sender: NSButton) {
        guard let project = app?.config?.projects[safe: sender.tag] else { return }
        app?.stopProjectByPort(project.port)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.projectsTable?.reloadData()
        }
    }

    @MainActor @objc private func restartFromTable(_ sender: NSButton) {
        guard let project = app?.config?.projects[safe: sender.tag] else { return }
        app?.restartProjectDirectly(project)
    }

    private func projectForMenuItem(_ sender: NSMenuItem) -> Project? {
        guard let row = sender.representedObject as? Int else { return nil }
        return app?.config?.projects[safe: row]
    }

    @MainActor @objc private func editFromTable(_ sender: NSMenuItem) {
        guard let project = projectForMenuItem(sender) else { return }
        // Drive the existing editor flow through HarbrApp so config-save
        // and CoreAnimation-flush teardown still happen the same way they
        // do when the editor is opened from the menu.
        let proxyMenuItem = NSMenuItem()
        proxyMenuItem.representedObject = project
        app?.editProject(proxyMenuItem)
    }

    @MainActor @objc private func deleteFromTable(_ sender: NSMenuItem) {
        guard let project = projectForMenuItem(sender) else { return }
        let proxyMenuItem = NSMenuItem()
        proxyMenuItem.representedObject = project
        app?.deleteProject(proxyMenuItem)
    }

    @MainActor @objc private func openFinderFromTable(_ sender: NSMenuItem) {
        guard let project = projectForMenuItem(sender) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: project.directory))
    }

    @MainActor @objc private func openTerminalFromTable(_ sender: NSMenuItem) {
        guard let project = projectForMenuItem(sender) else { return }
        app?.openTerminal(directory: project.directory)
    }

    @MainActor @objc private func openBrowserFromTable(_ sender: NSMenuItem) {
        guard let project = projectForMenuItem(sender),
              let url = URL(string: "http://localhost:\(project.port)") else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor @objc private func copyUrlFromTable(_ sender: NSMenuItem) {
        guard let project = projectForMenuItem(sender) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("http://localhost:\(project.port)", forType: .string)
    }

    // MARK: Activity tab

    @MainActor private func buildActivityTab(in container: NSView) {
        let bounds = container.bounds

        let title = NSTextField(labelWithString: "Activity")
        title.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        title.frame = NSRect(x: 20, y: bounds.height - 44, width: 200, height: 28)
        title.autoresizingMask = [.minYMargin]
        container.addSubview(title)

        let hint = NSTextField(labelWithString: "Recent output from each project. Updated every second.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 20, y: bounds.height - 64, width: 500, height: 16)
        hint.autoresizingMask = [.minYMargin]
        container.addSubview(hint)

        // Left: project picker
        let leftWidth: CGFloat = 240
        let leftScroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: leftWidth, height: bounds.height - 100))
        leftScroll.hasVerticalScroller = true
        leftScroll.borderType = .lineBorder
        leftScroll.autoresizingMask = [.height]
        let leftTable = NSTableView()
        leftTable.headerView = nil
        leftTable.allowsEmptySelection = true
        leftTable.allowsMultipleSelection = false
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("project"))
        col.width = leftWidth
        leftTable.addTableColumn(col)
        leftTable.dataSource = self
        leftTable.delegate = self
        leftTable.target = self
        leftTable.action = #selector(activityProjectClicked)
        leftScroll.documentView = leftTable
        container.addSubview(leftScroll)
        self.activityProjectList = leftTable

        // Right: log text view
        let rightX: CGFloat = 20 + leftWidth + 12
        let rightScroll = NSScrollView(frame: NSRect(x: rightX, y: 20, width: bounds.width - rightX - 20, height: bounds.height - 100))
        rightScroll.hasVerticalScroller = true
        rightScroll.borderType = .lineBorder
        rightScroll.autoresizingMask = [.height, .width]
        let textView = NSTextView()
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isEditable = false
        textView.isRichText = false
        textView.backgroundColor = NSColor(white: 0.10, alpha: 1.0)
        textView.textColor = NSColor(white: 0.92, alpha: 1.0)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = "Pick a project to see its recent output."
        rightScroll.documentView = textView
        container.addSubview(rightScroll)
        self.activityTextView = textView

        // Auto-select first project so the panel isn't empty.
        if let first = app?.config?.projects.first {
            activitySelectedPort = first.port
            leftTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            refreshActivityText()
        }

        // Tail at 1Hz; cheap because tail() reads at most maxBytes.
        activityRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshActivityText()
            }
        }
    }

    @MainActor @objc private func activityProjectClicked() {
        guard let row = activityProjectList?.selectedRow, row >= 0,
              let project = app?.config?.projects[safe: row] else { return }
        activitySelectedPort = project.port
        refreshActivityText()
    }

    @MainActor private func refreshActivityText() {
        guard let port = activitySelectedPort, let textView = activityTextView else { return }
        let path = HarbrApp.logPath(forPort: port)
        if !FileManager.default.fileExists(atPath: path) {
            let project = app?.config?.projects.first(where: { $0.port == port })
            let name = project?.name ?? "Project"
            let captureOn = project?.shouldCaptureLogs ?? true
            textView.string = captureOn
                ? "\(name) hasn't produced any output yet. Start it from the Projects tab."
                : "Log capture is off for \(name). Turn it on in the project's editor to see output here."
            return
        }
        let body = LogReader.tail(path: path, lines: 800)
        // Preserve scroll position only if the user has scrolled up — auto
        // scroll-to-bottom is what people expect when watching live logs.
        let atBottom: Bool = {
            guard let scroll = textView.enclosingScrollView else { return true }
            let docHeight = scroll.documentView?.bounds.height ?? 0
            let visibleBottom = scroll.contentView.bounds.origin.y + scroll.contentView.bounds.height
            return abs(docHeight - visibleBottom) < 40
        }()
        textView.string = body
        if atBottom {
            textView.scrollToEndOfDocument(nil)
        }
    }

    // MARK: Settings tab

    @MainActor private func buildSettingsTab(in container: NSView) {
        let bounds = container.bounds

        let title = NSTextField(labelWithString: "Settings")
        title.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        title.frame = NSRect(x: 20, y: bounds.height - 44, width: 200, height: 28)
        title.autoresizingMask = [.minYMargin]
        container.addSubview(title)

        var y: CGFloat = bounds.height - 90

        // Terminal app
        let terminalLabel = NSTextField(labelWithString: "Open dev servers in:")
        terminalLabel.frame = NSRect(x: 20, y: y, width: 160, height: 20)
        terminalLabel.autoresizingMask = [.minYMargin]
        container.addSubview(terminalLabel)

        let terminalPopup = NSPopUpButton(frame: NSRect(x: 190, y: y - 4, width: 180, height: 26))
        for terminal in TerminalApp.allCases {
            let title = terminal.isInstalled ? terminal.displayName : "\(terminal.displayName) (not installed)"
            terminalPopup.addItem(withTitle: title)
            terminalPopup.lastItem?.isEnabled = terminal.isInstalled
            terminalPopup.lastItem?.representedObject = terminal
        }
        let current = app?.config?.terminal ?? .terminal
        if let idx = TerminalApp.allCases.firstIndex(of: current) {
            terminalPopup.selectItem(at: idx)
        }
        terminalPopup.target = self
        terminalPopup.action = #selector(terminalPopupChanged(_:))
        terminalPopup.autoresizingMask = [.minYMargin]
        container.addSubview(terminalPopup)
        self.terminalPopup = terminalPopup

        y -= 44

        // Notifications
        let notif = NSButton(checkboxWithTitle: "Show notifications when servers start, stop, or auto-restart",
                             target: self, action: #selector(notificationsToggled))
        notif.frame = NSRect(x: 20, y: y, width: 500, height: 22)
        notif.state = (app?.config?.notifications ?? true) ? .on : .off
        notif.autoresizingMask = [.minYMargin]
        container.addSubview(notif)
        self.notificationsCheckbox = notif

        y -= 32

        // Launch at login
        let launch = NSButton(checkboxWithTitle: "Launch Harbr automatically when I log in",
                              target: self, action: #selector(launchAtLoginToggled))
        launch.frame = NSRect(x: 20, y: y, width: 500, height: 22)
        launch.state = (app?.config?.launchAtLogin ?? false) ? .on : .off
        launch.autoresizingMask = [.minYMargin]
        container.addSubview(launch)
        self.launchAtLoginCheckbox = launch

        y -= 52

        // Info row about log capture
        let infoTitle = NSTextField(labelWithString: "Log capture")
        infoTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        infoTitle.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        infoTitle.autoresizingMask = [.minYMargin]
        container.addSubview(infoTitle)

        y -= 24

        let infoBody = NSTextField(wrappingLabelWithString: "Harbr wraps each dev server with /usr/bin/script so its output is saved to ~/.harbr/logs/<port>.log and shown in the Activity tab. Turn it off per project in the project's editor if you have something that needs an unwrapped command (rare).")
        infoBody.font = NSFont.systemFont(ofSize: 11)
        infoBody.textColor = .secondaryLabelColor
        infoBody.frame = NSRect(x: 20, y: y - 40, width: bounds.width - 40, height: 60)
        infoBody.autoresizingMask = [.minYMargin, .width]
        container.addSubview(infoBody)
        self.captureLogsDefaultLabel = infoBody

        y -= 80

        // About
        let about = NSTextField(labelWithString: "Harbr · github.com/athayworth/Harbr")
        about.font = NSFont.systemFont(ofSize: 10)
        about.textColor = .tertiaryLabelColor
        about.frame = NSRect(x: 20, y: 20, width: bounds.width - 40, height: 16)
        about.autoresizingMask = [.maxYMargin]
        container.addSubview(about)
    }

    @MainActor @objc private func terminalPopupChanged(_ sender: NSPopUpButton) {
        guard let selected = sender.selectedItem?.representedObject as? TerminalApp else { return }
        app?.config?.terminal = selected
        app?.saveConfig()
    }

    @MainActor @objc private func notificationsToggled() {
        let value = notificationsCheckbox?.state == .on
        app?.config?.notifications = value
        app?.saveConfig()
    }

    @MainActor @objc private func launchAtLoginToggled() {
        let value = launchAtLoginCheckbox?.state == .on
        guard let current = app?.config?.launchAtLogin, current != value else { return }
        app?.toggleLaunchAtLogin()
    }

    // MARK: Refresh hook (called from app's poll)

    @MainActor func reloadFromPoll() {
        // Avoid touching tables for tabs that aren't on screen.
        if currentTab == .projects { projectsTable?.reloadData() }
        if currentTab == .activity {
            activityProjectList?.reloadData()
            refreshActivityText()
        }
    }

    // MARK: Lifecycle

    func windowWillClose(_ notification: Notification) {
        activityRefreshTimer?.invalidate()
        activityRefreshTimer = nil
        guard !didDismiss else { return }
        didDismiss = true
        onDismiss?()
    }

    @MainActor func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Log Reader

/// Reads the tail of a log file written by `script -q`, strips terminal
/// control sequences, and returns plain text ready to render. Kept small
/// and stateless so multiple consumers (Activity tab, future widgets) can
/// share it without contention.
enum LogReader {
    /// Strip the common ANSI/VT sequences: SGR colors, cursor moves, and
    /// the OSC clipboard/title pokes that some tools emit. We're not
    /// trying to be a real terminal emulator — just produce something
    /// readable in a plain NSTextView.
    static let ansiRegex: NSRegularExpression? = {
        // CSI sequences: ESC [ params final-byte
        // OSC sequences: ESC ] ... BEL or ESC \\
        let pattern = "\u{1B}\\[[0-9;?]*[a-zA-Z]|\u{1B}\\][^\u{07}\u{1B}]*[\u{07}\u{1B}]"
        return try? NSRegularExpression(pattern: pattern)
    }()

    static func stripAnsi(_ s: String) -> String {
        guard let regex = ansiRegex else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    }

    /// Returns the last `lines` text lines of the file at `path`, with
    /// ANSI sequences stripped. Reads up to `maxBytes` from the tail —
    /// for very long-running servers the file may be many MB but we
    /// only need the last screen's worth.
    static func tail(path: String, lines: Int = 500, maxBytes: Int = 256 * 1024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return ""
        }
        defer { try? handle.close() }

        // Seek backward maxBytes from EOF, or to start of file.
        let size = (try? handle.seekToEnd()) ?? 0
        let readFrom = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        do { try handle.seek(toOffset: readFrom) } catch { return "" }
        guard let data = try? handle.readToEnd() else { return "" }
        let text = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)

        let stripped = stripAnsi(text)
        // Normalize CR-only and CRLF newlines so NSTextView doesn't show
        // empty lines for every `\r` in a progress-bar redraw.
        let normalized = stripped
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let allLines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        if allLines.count <= lines { return normalized }
        return allLines.suffix(lines).joined(separator: "\n")
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
    var currentScannerWindow: ProjectScannerWindow?
    var currentMainWindow: HarbrMainWindow?
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
        Self.ensureLogsDir()

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

    /// Escapes a string for embedding inside an AppleScript double-quoted
    /// literal. AppleScript treats `\` as an escape character and rejects
    /// unknown escape sequences with "Expected '\"' but found unknown token"
    /// — exactly what happened when the script -q wrapper introduced `'\''`
    /// (sh-quoting) into a command field that was being pasted bare into
    /// `do script "..."`. Always apply this LAST, after any sh-level
    /// escaping, since this is what AppleScript sees.
    private func appleScriptEscape(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Opens a terminal window in the specified directory, optionally running a command.
    @MainActor func openTerminal(directory: String, command: String? = nil, activate: Bool = true) {
        let terminal = config?.terminal ?? .terminal
        // Directory goes inside `cd '...'` in the template, so it needs sh
        // escaping for any `'` it might contain. Then AppleScript-escape the
        // result so the `\` from sh-quoting doesn't choke the AppleScript
        // parser. Command is already a bare sh expression (the user typed
        // it; we only wrap it for log capture) — so it only needs the
        // AppleScript escape, not another round of sh quoting.
        let safeDirectory = appleScriptEscape(shellEscape(directory))
        let safeCommand = command.map { appleScriptEscape($0) }

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
    /// Rolling per-port CPU history for sparkline rendering. Sized for ~5
    /// minutes at the 5s poll cadence (60 samples). When a port goes from
    /// running → stopped → running, we keep the buffer so the sparkline
    /// shows the transition gap, but trim it from the front to avoid
    /// unbounded growth. Memory cost is negligible (Double × 60 × ports).
    var cpuHistory: [Int: [Double]] = [:]
    static let cpuHistoryLength = 60
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

        // Get resource usage for all PIDs in one ps call. rss is the resident
        // set size in KB — same number Activity Monitor labels "Real Memory"
        // — which formats much more legibly as MB/GB than the old %mem
        // (fraction-of-total-RAM) figure. Vibe coders parse "1.2 GB" as a
        // problem; "3.4%" reads as fine even when it isn't.
        guard let psResult = SafeProcess.runCapturingOutput(
            launchPath: "/bin/ps",
            arguments: ["-p", pids.joined(separator: ","), "-o", "%cpu,rss"]
        ) else { return nil }

        var totalCpu: Double = 0
        var totalMemMB: Double = 0

        let lines = psResult.stdout.components(separatedBy: "\n")
        for line in lines.dropFirst() { // Skip header
            let values = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: CharacterSet.whitespaces)
                .filter { !$0.isEmpty }
            if values.count >= 2 {
                totalCpu += Double(values[0]) ?? 0
                // rss is in KB → MB; keep as Double so formatMemory can
                // promote to GB at display time.
                totalMemMB += (Double(values[1]) ?? 0) / 1024.0
            }
        }

        return (totalCpu, totalMemMB)
    }

    /// Format an MB-valued double as "247 MB" or "1.4 GB", picking the unit
    /// that reads cleanly without overspecifying. Used in both menu surfaces
    /// so a hot project shows the same number on the top line and in its
    /// submenu detail.
    static func formatMemory(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024.0)
        } else if mb >= 100 {
            return String(format: "%.0f MB", mb)
        } else {
            return String(format: "%.1f MB", mb)
        }
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
                // Append a CPU sample per active project, padding with 0 for
                // stopped ones so the sparkline reads as "went silent" rather
                // than just freezing. Trim from the front to keep the buffer
                // bounded — this is the only place that grows the history.
                for project in projectsCopy {
                    let sample = newCache[project.port]?.cpuUsage ?? 0
                    var history = self.cpuHistory[project.port] ?? []
                    history.append(sample)
                    if history.count > HarbrApp.cpuHistoryLength {
                        history.removeFirst(history.count - HarbrApp.cpuHistoryLength)
                    }
                    self.cpuHistory[project.port] = history
                }
                self.rebuildMenu()
                // Live-refresh the desktop window's tables so a project
                // transitioning from stopped → running shows up there
                // without the user having to click anything.
                self.currentMainWindow?.reloadFromPoll()

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

        // Empty/first-run state: lead with the scan flow since it's the
        // fastest path from "fresh install" to "Harbr is useful," and keep
        // the manual Add path right below for users who already know what
        // they want or whose projects live somewhere unscannable.
        if config == nil || (config?.projects.isEmpty ?? true) {
            let welcome = NSMenuItem(title: "Welcome to Harbr", action: nil, keyEquivalent: "")
            welcome.attributedTitle = NSAttributedString(
                string: "Welcome to Harbr",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            welcome.isEnabled = false
            menu.addItem(welcome)

            let hint = NSMenuItem(title: "Add your dev servers to monitor and control them.", action: nil, keyEquivalent: "")
            hint.attributedTitle = NSAttributedString(
                string: "Add your dev servers to monitor and control them.",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            hint.isEnabled = false
            menu.addItem(hint)
            menu.addItem(NSMenuItem.separator())

            let scanItem = NSMenuItem(title: "Scan a folder for projects…", action: #selector(scanForProjects), keyEquivalent: "")
            scanItem.target = self
            scanItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Scan")
            menu.addItem(scanItem)

            let addItem = NSMenuItem(title: "Add a project manually…", action: #selector(addNewProject), keyEquivalent: "n")
            addItem.target = self
            menu.addItem(addItem)

            menu.addItem(NSMenuItem.separator())
            let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)
            return
        }

        guard let config = config else {
            // Defensive — handled above, but the rest of this function
            // assumes a non-nil config so the explicit unwrap here is what
            // every downstream `config.` reference relies on.
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

        let openWindowItem = NSMenuItem(title: "Open Harbr…", action: #selector(openMainWindow), keyEquivalent: "0")
        openWindowItem.target = self
        menu.addItem(openWindowItem)

        let scanProjectsItem = NSMenuItem(title: "Scan for Projects…", action: #selector(scanForProjects), keyEquivalent: "")
        scanProjectsItem.target = self
        menu.addItem(scanProjectsItem)

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

        // Surface CPU/MEM on the top-level line when active — previously
        // these were only visible inside each project's submenu, so users
        // had to hover one by one to find what was hot. Show as a muted
        // suffix so idle/healthy projects stay visually quiet and a hot
        // one stands out without us needing a separate alert.
        if status.isActive, let cpu = status.cpuUsage, let mem = status.memoryUsage {
            let primary = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.menuFont(ofSize: 0),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            // Tint the CPU figure when it's elevated so the eye lands on it
            // immediately. 20% is the threshold where a dev server feels
            // sluggish; >50% usually means something's stuck in a loop.
            let cpuColor: NSColor = cpu >= 50 ? .systemRed
                                   : cpu >= 20 ? .systemOrange
                                   : .secondaryLabelColor
            let suffix = NSMutableAttributedString(
                string: "   ·   ",
                attributes: [
                    .font: NSFont.menuFont(ofSize: 0),
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
            )
            suffix.append(NSAttributedString(
                string: String(format: "%.0f%%", cpu),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular),
                    .foregroundColor: cpuColor
                ]
            ))
            suffix.append(NSAttributedString(
                string: "  " + HarbrApp.formatMemory(mem),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            ))
            let combined = NSMutableAttributedString(attributedString: primary)
            combined.append(suffix)
            item.attributedTitle = combined
        }

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
                let memStr = HarbrApp.formatMemory(mem)
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

        // Wrap with `script -q LOG sh -c '<command>'` so the dev server's
        // stdout/stderr lands in a log file Harbr can tail. `script`
        // allocates a PTY for the inner command — without it, dev servers
        // strip ANSI colors and disable progress bars when they detect
        // their stdout isn't a terminal. Truncating each restart (no -a)
        // keeps the file small and matches the mental model "new run,
        // new logs."
        if project.shouldCaptureLogs {
            Self.ensureLogsDir()
            let logPath = Self.logPath(forPort: project.port)
            // Quote-escape single quotes inside the inner command using the
            // standard '\'' trick so commands like `echo 'hi'` survive
            // being wrapped in sh -c '...'.
            let escapedInner = command.replacingOccurrences(of: "'", with: "'\\''")
            let escapedLog = logPath.replacingOccurrences(of: "'", with: "'\\''")
            command = "/usr/bin/script -q '\(escapedLog)' /bin/sh -c '\(escapedInner)'"
        }

        lastSpawnAt[project.port] = Date()
        openTerminal(directory: project.directory, command: command, activate: activate)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.updateMenu()
        }
    }

    /// Directory where per-port log files live. `~/.harbr/logs/`. Created
    /// lazily on first spawn so we don't pollute the user's filesystem on
    /// install.
    static var logsDir: String {
        NSString(string: "~/.harbr/logs").expandingTildeInPath
    }

    static func logPath(forPort port: Int) -> String {
        (logsDir as NSString).appendingPathComponent("\(port).log")
    }

    static func ensureLogsDir() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logsDir) {
            try? fm.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
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

        // Don't `launchctl load` here. The plist has RunAtLoad=true, so a
        // load would immediately start a SECOND copy of Harbr on top of the
        // one the user is currently using — two menu-bar icons, two pollers
        // racing on the same config. Writing the plist is enough; macOS
        // picks it up on next login automatically. (Previous version spawned
        // a duplicate icon every time the user toggled Launch-at-Login on.)
        Self.launchAgentLog.info("Wrote LaunchAgent to \(self.launchAgentPath(), privacy: .public); will take effect at next login")
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

    @MainActor @objc func openMainWindow() {
        if currentMainWindow == nil {
            currentMainWindow = HarbrMainWindow(app: self)
            currentMainWindow?.onDismiss = { [weak self] in
                DispatchQueue.main.async {
                    // Defer release through the next runloop tick to flush any
                    // pending CoreAnimation transactions before NSWindow
                    // deallocates — same crash pattern that bit the editor.
                    self?.currentMainWindow = nil
                }
            }
        }
        currentMainWindow?.show()
    }

    @MainActor @objc func scanForProjects() {
        let existing = config?.projects ?? []
        currentScannerWindow = ProjectScannerWindow(existingProjects: existing) { [weak self] newProjects in
            guard let self = self, !newProjects.isEmpty else { return }
            self.config?.projects.append(contentsOf: newProjects)
            self.saveConfig()
        }
        currentScannerWindow?.onDismiss = { [weak self] in
            // Same CoreAnimation-flush defer as addNewProject — releasing
            // the NSWindow before pending CA transactions land has caused
            // SIGBUS crashes in the editor flow, and the scanner uses the
            // same window pattern.
            DispatchQueue.main.async {
                self?.currentScannerWindow = nil
            }
        }
        currentScannerWindow?.show()
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
