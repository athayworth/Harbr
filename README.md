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

This builds and installs Harbr to `/Applications/Harbr.app`.

### Build from Source (CLI)

```bash
swift build -c release
./.build/release/Harbr
```

The app will appear in your menu bar with a sailboat icon.

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

- **Port detection**: Uses `lsof` to check which ports have active listeners
- **Health checks**: Uses URLSession to ping health endpoints
- **Resource monitoring**: Uses `ps` to get CPU and memory usage
- **Server management**: Uses AppleScript to open Terminal/iTerm/Warp and run commands
- **Process control**: Uses `kill` and `pkill` to stop servers and child processes
- **Launch at Login**: Creates a LaunchAgent in `~/Library/LaunchAgents/`
- **Notifications**: Uses UserNotifications framework for system notifications

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
