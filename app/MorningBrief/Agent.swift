import AppKit
import Foundation

/// Talks to Claude Code: finds it, checks the Gmail/Calendar connectors, and runs the agent.
enum Agent {
    /// The agent may only read. Sending, drafting, deleting and editing tools are left out.
    static let readOnlyTools = [
        "mcp__claude_ai_Gmail__search_threads", "mcp__claude_ai_Gmail__get_thread",
        "mcp__claude_ai_Gmail__get_message", "mcp__claude_ai_Gmail__list_labels",
        "mcp__claude_ai_Google_Calendar__list_calendars", "mcp__claude_ai_Google_Calendar__list_events",
        "mcp__claude_ai_Google_Calendar__get_event", "mcp__claude_ai_Google_Calendar__search_events",
    ]

    enum AgentError: LocalizedError {
        case notInstalled, failed(String), noJSON(String), timedOut
        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Claude Code isn't installed."
            case .failed(let msg): return msg
            case .noJSON(let text): return "The agent didn't return a list: \(text.prefix(200))"
            case .timedOut: return "The agent took longer than 10 minutes."
            }
        }
    }

    // MARK: - Finding Claude Code

    static func findClaude() -> String? {
        let home = Store.realHome.path
        let candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                          "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude"]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return hit
        }
        // Fall back to the user's login shell PATH.
        let out = try? shell("/bin/zsh", ["-lc", "command -v claude"], timeout: 15)
        let path = out?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    struct Connections { var gmail = false; var calendar = false }

    /// Reads `claude mcp list` to see whether the claude.ai connectors are authorized.
    static func checkConnections(claude: String) -> Connections {
        guard let out = try? shell(claude, ["mcp", "list"], timeout: 60) else { return Connections() }
        func connected(_ name: String) -> Bool {
            out.stdout.split(separator: "\n").contains { $0.contains(name + ":") && $0.contains("Connected") }
        }
        return Connections(gmail: connected("claude.ai Gmail"), calendar: connected("claude.ai Google Calendar"))
    }

    /// Opens Terminal running Claude Code so the user can type /mcp and sign in.
    static func openConnectTerminal(claude: String) {
        let script = """
        #!/bin/zsh
        clear
        echo "Morning Brief: connect Gmail and Google Calendar"
        echo
        echo "  1. Type /mcp and press Enter"
        echo "  2. Choose 'claude.ai Gmail' -> Authenticate, sign in with your school Google account"
        echo "  3. Do the same for 'claude.ai Google Calendar'"
        echo "  4. Close this window and click 'Check again' in Morning Brief"
        echo
        cd "\(Store.dir.path)"
        exec "\(claude)"
        """
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("connect-morning-brief.command")
        try? script.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        NSWorkspace.shared.open(file)
    }

    // MARK: - Running the agent

    static func run(claude: String, prompt: String) throws -> Brief {
        let args = ["-p", prompt, "--output-format", "json", "--max-turns", "20",
                    "--allowedTools"] + readOnlyTools +
                   ["--disallowedTools", "Bash", "Edit", "Write", "NotebookEdit", "WebFetch", "WebSearch"]
        let out = try shell(claude, args, timeout: 600, cwd: Store.dir)

        guard out.status == 0 else {
            let msg = out.stderr.isEmpty ? out.stdout : out.stderr
            throw AgentError.failed("Claude exited with \(out.status): \(msg.prefix(300))")
        }
        guard let envelope = try? JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any],
              let result = envelope["result"] as? String else {
            throw AgentError.noJSON(out.stdout)
        }
        if envelope["is_error"] as? Bool == true { throw AgentError.failed("Agent error: \(result.prefix(300))") }

        // The agent is told to return bare JSON, but tolerate code fences or stray prose.
        guard let open = result.firstIndex(of: "{"), let close = result.lastIndex(of: "}"),
              let brief = try? JSONDecoder().decode(Brief.self, from: Data(result[open...close].utf8)) else {
            throw AgentError.noJSON(result)
        }
        return brief
    }

    // MARK: - Process helper

    struct Output { var status: Int32; var stdout: String; var stderr: String }

    static func shell(_ exe: String, _ args: [String], timeout: TimeInterval, cwd: URL? = nil) throws -> Output {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        // Apps launched from Finder get a bare PATH; give Claude Code the usual places.
        var env = ProcessInfo.processInfo.environment
        let home = Store.realHome.path
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        env["HOME"] = home
        p.environment = env

        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice

        // Read pipes concurrently so a large output can't block the process.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        try p.run()
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        if p.isRunning { p.terminate(); throw AgentError.timedOut }
        group.wait()
        return Output(status: p.terminationStatus,
                      stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errData, as: UTF8.self))
    }
}
