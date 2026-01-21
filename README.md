# Harbr

A lightweight macOS menu bar app that monitors your localhost development servers and lets you start/stop them with a click.

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- **Live status monitoring** of localhost ports with visual indicators
- **Start servers** directly from the menu bar (opens Terminal with your command)
- **Stop running servers** with one click
- **Start/Stop All** - bulk actions for all projects
- **Resource monitoring** - see CPU and memory usage for each server
- **Quick access** - open project directories in Finder, Terminal, or Browser
- **Project management** - add, edit, and delete projects via UI
- **Multiple terminal support** - Terminal.app, iTerm2, or Warp
- **Notifications** - get notified when servers start or stop
- **Running count** - see how many servers are active in the menu bar
- **Auto-refresh** every 5 seconds

## Installation

### Build as Application (Recommended)

```bash
git clone https://github.com/yourusername/Harbr.git
cd Harbr
./scripts/build-app.sh
```

Then copy to Applications:
```bash
cp -r build/Harbr.app /Applications/
```

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
      "startCommand": "npm run dev"
    },
    {
      "name": "API Server",
      "port": 8080,
      "directory": "/Users/yourusername/Projects/api-server",
      "startCommand": "go run main.go"
    }
  ],
  "terminalApp": "Terminal",
  "notificationsEnabled": true
}
```

### Project Fields

| Field | Description | Example |
|-------|-------------|---------|
| `name` | Display name for the project | `"My App"` |
| `port` | Localhost port to monitor (1-65535) | `3000` |
| `directory` | Full path to project directory | `"/Users/me/Projects/app"` |
| `startCommand` | Command to start the dev server | `"npm run dev"` |

### Settings

| Setting | Description | Values |
|---------|-------------|--------|
| `terminalApp` | Terminal to use for commands | `"Terminal"`, `"iTerm"`, `"Warp"` |
| `notificationsEnabled` | Show notifications on state changes | `true` / `false` |

## Usage

1. **Click the menu bar icon** (sailboat) to see all configured projects
2. **Green dot** = server is running (shows CPU/memory usage)
3. **Empty circle** = server is stopped
4. **Number badge** = count of running servers
5. **Click a project** to see available actions:
   - Start/Stop the server
   - Open in Finder
   - Open in Terminal
   - Open in Browser (localhost:port)
   - Edit or Delete the project
6. **Bulk actions**: Start All / Stop All
7. **Preferences**: Choose terminal app, toggle notifications
8. **Keyboard shortcuts**:
   - `⌘N` - Add new project
   - `⌘R` - Reload configuration
   - `⌘Q` - Quit

## Launch at Login

1. Build the app: `./scripts/build-app.sh`
2. Copy to Applications: `cp -r build/Harbr.app /Applications/`
3. Open System Settings → General → Login Items
4. Click '+' and select Harbr from Applications

## Requirements

- macOS 12.0 (Monterey) or later
- Swift 6.1+ (for building from source)

## How It Works

Harbr uses system tools to monitor and manage your development servers:

- **Port detection**: Uses `lsof` to check which ports have active listeners
- **Resource monitoring**: Uses `ps` to get CPU and memory usage
- **Server management**: Uses AppleScript to open Terminal/iTerm/Warp and run commands
- **Process control**: Uses `kill` to stop servers
- **Notifications**: Uses UserNotifications framework for system notifications

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
