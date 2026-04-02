//
//  HookInstaller.swift
//  ClaudeIsland
//
//  Auto-installs Claude Code hooks on app launch.
//  Uses a compiled Swift bridge binary instead of Python.
//

import Foundation

struct HookInstaller {

    /// Identifier string used in hook commands to detect our hooks
    private static let hookIdentifier = "claude-island-bridge"

    /// Install launcher script and update settings.json on app launch
    static func installIfNeeded() {
        installLauncher()
        installStatusLine()
        let settings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        updateSettings(at: settings)
    }

    /// Install the shell launcher at ~/.claude-island/bin/claude-island-bridge
    private static func installLauncher() {
        let fm = FileManager.default
        let binDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-island/bin")

        try? fm.createDirectory(at: binDir, withIntermediateDirectories: true)

        let launcherPath = binDir.appendingPathComponent("claude-island-bridge")
        let script = """
        #!/bin/zsh
        # claude-island-bridge launcher (auto-generated)
        H=/Contents/Helpers/claude-island-bridge
        B="/Applications/Claude Island.app${H}"
        [ -x "$B" ] && exec "$B" "$@"
        for P in "/Applications/Claude Island.app" "$HOME/Applications/Claude Island.app"; do
          B="${P}${H}"; [ -x "$B" ] && exec "$B" "$@"
        done
        C=~/.claude-island/bin/.bridge-cache
        [ -f "$C" ] && read -r P < "$C" && B="${P}${H}" && [ -x "$B" ] && exec "$B" "$@"
        P="$(/usr/bin/mdfind 'kMDItemCFBundleIdentifier == "com.celestial.ClaudeIsland"' 2>/dev/null | /usr/bin/head -1)"
        B="${P}${H}"
        [ -x "$B" ] && { echo "$P" > "$C"; exec "$B" "$@"; }
        exit 0
        """

        try? script.write(to: launcherPath, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherPath.path)
    }

    /// Install the status line script at ~/.claude-island/bin/statusline.sh
    private static func installStatusLine() {
        let fm = FileManager.default
        let binDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-island/bin")
        let statusLinePath = binDir.appendingPathComponent("statusline.sh")

        let script = """
        #!/bin/bash
        SOCKET="/tmp/claude-island.sock"
        input=$(cat)
        REMAINING=$(echo "$input" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(int(d.get('context_window',{}).get('remaining_percentage',0)))" 2>/dev/null)
        SESSION_ID=$(echo "$input" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null)
        [ -z "$REMAINING" ] && REMAINING=0
        [ -z "$SESSION_ID" ] && exit 0
        MSG="{\\\"session_id\\\":\\\"${SESSION_ID}\\\",\\\"event\\\":\\\"StatusLine\\\",\\\"status\\\":\\\"status_update\\\",\\\"cwd\\\":\\\"\\\",\\\"remaining_percentage\\\":${REMAINING}}"
        echo "$MSG" | /usr/bin/nc -U -w1 "$SOCKET" 2>/dev/null
        echo "${REMAINING}% ctx"
        """

        try? script.write(to: statusLinePath, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: statusLinePath.path)
    }

    private static var statusLineCommand: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude-island/bin/statusline.sh"
    }

    private static var bridgeCommand: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude-island/bin/claude-island-bridge"
    }

    private static func updateSettings(at settingsURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let command = bridgeCommand
        let hookEntry: [[String: Any]] = [["type": "command", "command": command]]
        let hookEntryWithTimeout: [[String: Any]] = [["type": "command", "command": command, "timeout": 86400]]
        let withMatcher: [[String: Any]] = [["matcher": "*", "hooks": hookEntry]]
        let withMatcherAndTimeout: [[String: Any]] = [["matcher": "*", "hooks": hookEntryWithTimeout]]
        let withoutMatcher: [[String: Any]] = [["hooks": hookEntry]]
        let preCompactConfig: [[String: Any]] = [
            ["matcher": "auto", "hooks": hookEntry],
            ["matcher": "manual", "hooks": hookEntry]
        ]

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let hookEvents: [(String, [[String: Any]])] = [
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PostToolUse", withMatcher),
            ("PermissionRequest", withMatcherAndTimeout),
            ("Notification", withMatcher),
            ("Stop", withoutMatcher),
            ("SubagentStop", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("SessionEnd", withoutMatcher),
            ("PreCompact", preCompactConfig),
        ]

        for (event, config) in hookEvents {
            if var existingEvent = hooks[event] as? [[String: Any]] {
                // Remove old Python-based hooks
                existingEvent.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { h in
                            let cmd = h["command"] as? String ?? ""
                            return cmd.contains("claude-island-state.py")
                        }
                    }
                    return false
                }

                let hasOurHook = existingEvent.contains { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { h in
                            let cmd = h["command"] as? String ?? ""
                            return cmd.contains(hookIdentifier)
                        }
                    }
                    return false
                }
                if !hasOurHook {
                    existingEvent.append(contentsOf: config)
                }
                hooks[event] = existingEvent
            } else {
                hooks[event] = config
            }
        }

        json["hooks"] = hooks

        // Register statusLine
        json["statusLine"] = [
            "command": statusLineCommand,
            "type": "command"
        ] as [String: Any]

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    /// Check if hooks are currently installed
    static func isInstalled() -> Bool {
        let settings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")

        guard let data = try? Data(contentsOf: settings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        for hook in entryHooks {
                            if let cmd = hook["command"] as? String,
                               cmd.contains(hookIdentifier) {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    /// Uninstall hooks from settings.json and remove launcher
    static func uninstall() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let launcher = home.appendingPathComponent(".claude-island/bin/claude-island-bridge")
        let oldPython = home.appendingPathComponent(".claude/hooks/claude-island-state.py")
        let settings = home.appendingPathComponent(".claude/settings.json")

        try? fm.removeItem(at: launcher)
        try? fm.removeItem(at: oldPython)

        guard let data = try? Data(contentsOf: settings),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { hook in
                            let cmd = hook["command"] as? String ?? ""
                            return cmd.contains(hookIdentifier) || cmd.contains("claude-island-state.py")
                        }
                    }
                    return false
                }

                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settings, options: .atomic)
        }
    }
}
