#!/usr/bin/env swift
//
//  main.swift
//  ClaudeIslandBridge
//
//  Swift replacement for claude-island-state.py
//  Sends session state to ClaudeIsland.app via Unix socket.
//  For PermissionRequest: waits for user decision from the app.
//

import Foundation

let socketPath = "/tmp/claude-island.sock"
let timeoutSeconds: Int = 300 // 5 minutes for permission decisions

// MARK: - TTY Detection

func getTTY() -> String? {
    let ppid = getppid()

    // Try ps command for parent process
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-p", "\(ppid)", "-o", "tty="]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let tty = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tty.isEmpty, tty != "??", tty != "-" {
            return tty.hasPrefix("/dev/") ? tty : "/dev/" + tty
        }
    } catch {}

    // Fallback: try ttyname on stdin
    if let name = ttyname(STDIN_FILENO) {
        return String(cString: name)
    }
    if let name = ttyname(STDOUT_FILENO) {
        return String(cString: name)
    }

    return nil
}

// MARK: - Socket Communication

func sendEvent(_ state: [String: Any]) -> [String: Any]? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = socketPath.utf8CString
    guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
            pathBytes.withUnsafeBufferPointer { src in
                _ = memcpy(dest, src.baseAddress!, src.count)
            }
        }
    }

    // Set socket timeout
    var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    // Disable SIGPIPE
    var noSigPipe: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connectResult == 0 else { return nil }

    // Send JSON
    guard let jsonData = try? JSONSerialization.data(withJSONObject: state),
          let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }

    let bytes = Array(jsonString.utf8)
    let sent = Darwin.send(fd, bytes, bytes.count, 0)
    guard sent > 0 else { return nil }

    // For permission requests, wait for response
    let isPermission = (state["status"] as? String) == "waiting_for_approval"
    if isPermission {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let received = recv(fd, &buffer, buffer.count, 0)
        if received > 0 {
            let responseData = Data(buffer[0..<received])
            if let response = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                return response
            }
        }
    }

    return nil
}

// MARK: - Main

func main() {
    // Read stdin
    let inputData = FileHandle.standardInput.readDataToEndOfFile()
    guard let data = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] else {
        exit(1)
    }

    let sessionId = data["session_id"] as? String ?? "unknown"
    let event = data["hook_event_name"] as? String ?? ""
    let cwd = data["cwd"] as? String ?? ""
    let toolInput = data["tool_input"] as? [String: Any] ?? [:]

    // Get process info
    let claudePid = Int(getppid())
    let tty = getTTY()

    // Build state object
    var state: [String: Any] = [
        "session_id": sessionId,
        "cwd": cwd,
        "event": event,
        "pid": claudePid,
    ]
    if let tty = tty {
        state["tty"] = tty
    }

    // Map events to status
    switch event {
    case "UserPromptSubmit":
        state["status"] = "processing"

    case "PreToolUse":
        state["status"] = "running_tool"
        state["tool"] = data["tool_name"] as Any
        state["tool_input"] = toolInput as Any
        if let toolUseId = data["tool_use_id"] {
            state["tool_use_id"] = toolUseId
        }

    case "PostToolUse":
        state["status"] = "processing"
        state["tool"] = data["tool_name"] as Any
        state["tool_input"] = toolInput as Any
        if let toolUseId = data["tool_use_id"] {
            state["tool_use_id"] = toolUseId
        }

    case "PermissionRequest":
        state["status"] = "waiting_for_approval"
        state["tool"] = data["tool_name"] as Any
        state["tool_input"] = toolInput as Any

        // Send to app and wait for decision
        let response = sendEvent(state)

        if let response = response {
            let decision = response["decision"] as? String ?? "ask"
            let reason = response["reason"] as? String ?? ""

            if decision == "allow" {
                let output: [String: Any] = [
                    "hookSpecificOutput": [
                        "hookEventName": "PermissionRequest",
                        "decision": ["behavior": "allow"]
                    ]
                ]
                if let outputData = try? JSONSerialization.data(withJSONObject: output),
                   let outputString = String(data: outputData, encoding: .utf8) {
                    print(outputString)
                }
                exit(0)
            } else if decision == "deny" {
                let output: [String: Any] = [
                    "hookSpecificOutput": [
                        "hookEventName": "PermissionRequest",
                        "decision": [
                            "behavior": "deny",
                            "message": reason.isEmpty ? "Denied by user via Claude Island" : reason
                        ] as [String: Any]
                    ]
                ]
                if let outputData = try? JSONSerialization.data(withJSONObject: output),
                   let outputString = String(data: outputData, encoding: .utf8) {
                    print(outputString)
                }
                exit(0)
            }
        }

        // No response or "ask" - let Claude Code show its normal UI
        exit(0)

    case "Notification":
        let notificationType = data["notification_type"] as? String
        // Skip permission_prompt - PermissionRequest hook handles this
        if notificationType == "permission_prompt" {
            exit(0)
        } else if notificationType == "idle_prompt" {
            state["status"] = "waiting_for_input"
        } else {
            state["status"] = "notification"
        }
        state["notification_type"] = notificationType as Any
        state["message"] = data["message"] as Any

    case "Stop":
        state["status"] = "waiting_for_input"

    case "SubagentStop":
        state["status"] = "waiting_for_input"

    case "SessionStart":
        state["status"] = "waiting_for_input"

    case "SessionEnd":
        state["status"] = "ended"

    case "PreCompact":
        state["status"] = "compacting"

    default:
        state["status"] = "unknown"
    }

    // Send to socket (fire and forget for non-permission events)
    _ = sendEvent(state)
}

main()
