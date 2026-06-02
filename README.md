# Harbr

A lightweight macOS menu bar app that monitors your localhost development servers and lets you start/stop them with a click.

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- **Live status monitoring** of localhost ports with visual indicators
- **Start/Stop/Restart servers** directly from the menu bar
- **Start/Stop All** - bulk actions for all projects
- **Auto-restart on crash** - automatically restart servers that go down
- **Health check endpoints** - verify servers are responding, not just listening
- **Resource monitoring** - see CPU and memory usage for each server
- **Project groups** - organize projects into groups with section headers
- **Quick access** - open project directories in Finder, Terminal, or Browser
- **Copy URL** - quickly copy localhost URL to clipboard
- **Port conflict warnings** - alert before starting if port is in use
- **Environment variables** - set env vars per project
- **Project management** - add, edit, and delete projects via UI
- **Multiple terminal support** - Terminal.app, iTerm2, or Warp
- **Launch at Login** - built-in toggle to start automatically
- **Notifications** - get notified when servers start or stop
- **Running count** - see how many servers are active in the menu bar
- **Auto-refresh** every 5 seconds

## Installation

### Quick Install (Recommended)

```bash
git clone https://github.com/athayworth/Harbr.git
cd Harbr
./scripts/install.sh
```

This builds, ad-hoc codesigns, and installs Harbr to `/Applications/Harbr.app`.
Requires Swift 6.1+ (Xcode 16 or the standalone toolchain).

### Build from Source (CLI)

```bash
swift build -c release
./.build/release/Harbr
```

The app will appear in your menu bar with a sailboat icon.

### First Launch

On first launch you'll hit two one-time macOS prompts. Both are expected:

1. **Automation permission** ("Harbr would like to control Terminal") — fires
   the first time you click Start/Stop/Restart. Approve it so Harbr can spawn
   dev-server windows. You can revoke this later in
   *System Settings → Privacy & Security → Automation*.
2. **Notifications permission** — fires shortly after launch. Approve to get
   start/stop/auto-restart notifications, or skip if you'd rather not.

If you downloaded a prebuilt `Harbr.app` rather than building from source,
Gatekeeper may say *"Harbr can't be opened because Apple cannot check it for
malicious software."* Right-click the app and pick **Open** to bypass once;
subsequent launches work normally. (The install script clears the quarantine
attribute for you, so this only applies to manually-downloaded binaries.)

### Building a signed distribution

The default build is ad-hoc signed (`codesign --sign -`), which works on the
machine that built it but Gatekeeper will still warn other users on download.
To produce a build you can hand to someone else, set `CODESIGN_IDENTITY` to a
Developer ID Application identity from your keychain:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./scripts/build-app.sh
```

Full notarization (`xcrun notarytool`) is left to you — Harbr's build scripts
stop at signing.

## Configuration

Harbr stores project configurations in `~/.harbr/config.json`. You can either:

1. **Use the UI**: Click "Add Project..." from the menu bar
2. **Edit the config file** directly:

```json
{
  "projects": [
    {
      "name": "My Next.js App",
      "port": 3000,
      "directory": "/Users/yourusername/Projects/my-nextjs-app",
      "startCommand": "npm run dev",
      "group": "Frontend",
      "healthCheckUrl": "/api/health",
      "autoRestart": true
    },
    {
      "name": "API Server",
      "port": 8080,
      "directory": "/Users/yourusername/Projects/api-server",
      "startCommand": "go run main.go",
      "group": "Backend",
      "envVars": {
        "GO_ENV": "development",
        "DEBUG": "true"
      }
    }
  ],
  "terminalApp": "Terminal",
  "notificationsEnabled": true,
  "launchAtLoginEnabled": false
}
```

### Project Fields

| Field | Description | Required | Example |
|-------|-------------|----------|---------|
| `name` | Display name for the project | Yes | `"My App"` |
| `port` | Localhost port to monitor (1-65535) | Yes | `3000` |
| `directory` | Full path to project directory | Yes | `"/Users/me/Projects/app"` |
| `startCommand` | Command to start the dev server | Yes | `"npm run dev"` |
| `group` | Group name for organizing projects | No | `"Frontend"` |
| `healthCheckUrl` | URL path or full URL to check server health | No | `"/health"` |
| `envVars` | Environment variables to set when starting | No | `{"NODE_ENV": "dev"}` |
| `autoRestart` | Auto-restart if server crashes | No | `true` |

### Settings

| Setting | Description | Values |
|---------|-------------|--------|
| `terminalApp` | Terminal to use for commands | `"Terminal"`, `"iTerm"`, `"Warp"` |
| `notificationsEnabled` | Show notifications on state changes | `true` / `false` |
| `launchAtLoginEnabled` | Start Harbr when you log in | `true` / `false` |

## Usage

1. **Click the menu bar icon** (sailboat) to see all configured projects
2. **Status indicators**:
   - **Green dot** = server is running and healthy
   - **Yellow warning** = server is running but health check failed
   - **Empty circle** = server is stopped
   - **Number badge** = count of running servers
3. **Click a project** to see available actions:
   - Start/Stop/Restart the server
   - Open in Finder
   - Open in Terminal
   - Open in Browser (localhost:port)
   - Copy URL to clipboard
   - Edit or Delete the project
4. **Bulk actions**: Start All / Stop All
5. **Preferences**:
   - Choose terminal app
   - Toggle notifications
   - Toggle Launch at Login
6. **Keyboard shortcuts**:
   - `⌘N` - Add new project
   - `⌘R` - Reload configuration
   - `⌘Q` - Quit

## Requirements

- macOS 12.0 (Monterey) or later
- Swift 6.1+ (for building from source)

## How It Works

Harbr uses system tools to monitor and manage your development servers:

- **Port detection**: Native BSD socket `connect()` to `127.0.0.1:port` — no subprocess, safe under memory pressure. (`lsof` is still used to look up the owning PIDs when stopping or measuring a server.)
- **Health checks**: URLSession pings health endpoints in parallel; results are capped at a 5s wall-clock window per cache refresh.
- **Resource monitoring**: Uses `ps` to get CPU and memory usage.
- **Server management**: Uses AppleScript to open Terminal/iTerm/Warp and run commands.
- **Process control**: Uses `kill` and `pkill` to stop servers and child processes.
- **Launch at Login**: Creates a LaunchAgent in `~/Library/LaunchAgents/`.
- **Notifications**: Uses UserNotifications framework for system notifications.
- **Subprocess safety**: All `Process` invocations are routed through an Objective-C `@try`/`@catch` bridge (`HarbrSafe`), so an `NSException` raised by `NSConcreteTask` under heavy memory pressure becomes a logged error instead of an `abort()`.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
