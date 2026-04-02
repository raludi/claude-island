<div align="center">
  <img src="ClaudeIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h3 align="center">Claude Island (Fork)</h3>
  <p align="center">
    A privacy-focused fork of <a href="https://github.com/farouqaldori/claude-island">Claude Island</a> — a macOS Dynamic Island companion for Claude Code.
    <br />
    No telemetry. No Python dependency. Extra features.
  </p>
</div>

## What's Different in This Fork

This fork removes telemetry, replaces the Python bridge with a compiled Swift binary, and adds new features:

### Removed
- **Mixpanel analytics** — all telemetry stripped, zero data collection
- **Sparkle auto-updater** — removed external update framework
- **Python dependency** — no longer needs Python installed

### Added
- **Swift bridge binary** — compiled CLI at `Contents/Helpers/claude-island-bridge` replaces the Python hook script. Faster, no runtime dependency
- **Bypass mode** — per-session auto-approve toggle (red shield icon). When enabled, all tool permissions are automatically allowed
- **Terminal jump** — single-click any session to bring its terminal (iTerm2, Terminal.app, Ghostty, etc.) to the front. Works with tmux
- **Context window indicator** — shows remaining context % for each session via the statusLine API. Color-coded: white (>50%), amber (20-50%), red (<20%)
- **StatusLine integration** — registers a statusLine script that feeds context window data to the app in real-time

### Improved
- **Hook installer** — uses a shell launcher + compiled bridge (same pattern as Vibe Island). Auto-migrates from old Python hooks
- **Terminal focus** — works without yabai by using AppleScript activation. Correctly finds iTerm2 for tmux sessions

## Features

- **Notch UI** — Animated overlay that expands from the MacBook notch
- **Live Session Monitoring** — Track multiple Claude Code sessions in real-time
- **Permission Approvals** — Approve or deny tool executions directly from the notch
- **Bypass Mode** — Auto-approve all tools for trusted sessions (per-session toggle)
- **Terminal Jump** — Click a session to jump to its terminal window
- **Context Window %** — See how much context remains in each session
- **Chat History** — View full conversation history with markdown rendering
- **Auto-Setup** — Hooks and statusLine install automatically on first launch

## Requirements

- macOS 15.0+
- Claude Code CLI

## Install

Build from source:

```bash
xcodebuild -scheme ClaudeIsland -configuration Release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build
```

Then copy the built app to your Applications folder:

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/Build/Products/Release/Claude\ Island.app ~/Applications/
```

## How It Works

On first launch, Claude Island installs:
1. A **shell launcher** at `~/.claude-island/bin/claude-island-bridge` that delegates to the compiled Swift bridge inside the app bundle
2. **Hooks** in `~/.claude/settings.json` for all Claude Code events (SessionStart, PermissionRequest, PreToolUse, etc.)
3. A **statusLine script** at `~/.claude-island/bin/statusline.sh` that reports context window usage

The app listens on a Unix socket at `/tmp/claude-island.sock`. Hook events flow through the bridge to the app in real-time.

When Claude needs permission to run a tool, the notch expands with approve/deny buttons — no need to switch to the terminal. Or enable bypass mode to auto-approve everything.

## Privacy

This fork collects **zero data**. No analytics, no telemetry, no network calls. Everything stays on your machine.

## License

Apache 2.0 — same as the original project.

## Credits

Based on [claude-island](https://github.com/farouqaldori/claude-island) by [@farouqaldori](https://github.com/farouqaldori).
