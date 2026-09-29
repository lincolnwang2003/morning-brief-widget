import AppKit
import Foundation
import ServiceManagement
import WidgetKit

struct Config: Codable {
    var canvasURL = ""
    var lookaheadDays = 3
    var language = "English"
    var runHour = 7
    var setupDone = false
}

/// App state: config, the current brief, and the daily schedule.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var config: Config
    @Published var brief: Brief
    @Published var isRunning = false
    @Published var claudePath: String?
    @Published var connections = Agent.Connections()

    private var timer: Timer?

    init() {
        try? FileManager.default.createDirectory(at: Store.dir, withIntermediateDirectories: true)
        config = (try? JSONDecoder().decode(Config.self, from: Data(contentsOf: Store.configURL))) ?? Config()
        brief = Store.loadBrief() ?? Brief()
        if brief.status == "running" { brief.status = nil }  // app quit mid-run last time
        claudePath = Agent.findClaude()
    }

    var needsSetup: Bool { !config.setupDone }

    func saveConfig() {
        if let data = try? JSONEncoder().encode(config) { try? data.write(to: Store.configURL, options: .atomic) }
    }

    // MARK: - Schedule

    /// Runs once a day after `runHour`, whenever the Mac is awake (and on launch / wake).
    func startSchedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in self.runIfDue() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            // Give Wi-Fi a moment to reconnect after waking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.runIfDue() }
        }
        runIfDue()
    }

    private func runIfDue() {
        guard config.setupDone, !isRunning else { return }
        let cal = Calendar.current
        let now = Date()
        guard cal.component(.hour, from: now) >= config.runHour else { return }
        if let last = lastSuccess, cal.isDate(last, inSameDayAs: now) { return }
        Task { await refresh() }
    }

    private var lastSuccess: Date? {
        guard brief.status == "ok", let s = brief.generated_at else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.date(from: s)
    }

    // MARK: - Refresh

    func refresh() async {
        guard !isRunning else { return }
        guard let claude = claudePath ?? Agent.findClaude() else {
            fail(Agent.AgentError.notInstalled); return
        }
        isRunning = true
        brief.status = "running"
        write(brief)
        log("start")

        let config = self.config
        do {
            let items = try await Canvas.upcoming(feed: config.canvasURL, days: config.lookaheadDays + 1)
            log("canvas: \(items.count) items")
            let prompt = try buildPrompt(canvas: items, config: config)
            var result = try await Task.detached { try Agent.run(claude: claude, prompt: prompt) }.value

            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd'T'HH:mm"
            result.status = "ok"
            result.error = nil
            result.generated_at = f.string(from: Date())
            brief = result
            write(result)
            log("done: \(result.today.count) today, \(result.upcoming.count) upcoming")
        } catch {
            fail(error)
        }
        isRunning = false
    }

    private func fail(_ error: Error) {
        log("FAILED: \(error.localizedDescription)")
        brief.status = "error"  // keep the last good list on screen
        brief.error = error.localizedDescription
        write(brief)
        isRunning = false
    }

    private func write(_ brief: Brief) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? enc.encode(brief) { try? data.write(to: Store.briefURL, options: .atomic) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func buildPrompt(canvas: [Canvas.Item], config: Config) throws -> String {
        guard let url = Bundle.main.url(forResource: "prompt", withExtension: "md") else {
            throw Agent.AgentError.failed("prompt.md is missing from the app bundle")
        }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: config.lookaheadDays, to: now)!
        func fmt(_ pattern: String, _ d: Date) -> String {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = pattern
            return f.string(from: d)
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let canvasJSON = String(decoding: try enc.encode(canvas), as: UTF8.self)

        // prompt.md uses Python str.format syntax: {name} placeholders, {{ }} for literal braces.
        var text = try String(contentsOf: url, encoding: .utf8)
        let values = [
            "today": fmt("EEEE, yyyy-MM-dd", now), "now": fmt("HH:mm", now),
            "tz": TimeZone.current.abbreviation() ?? TimeZone.current.identifier,
            "lookahead": String(config.lookaheadDays), "end_date": fmt("yyyy-MM-dd", end),
            "language": config.language,
        ]
        for (k, v) in values { text = text.replacingOccurrences(of: "{\(k)}", with: v) }
        text = text.replacingOccurrences(of: "{{", with: "{").replacingOccurrences(of: "}}", with: "}")
        return text.replacingOccurrences(of: "{canvas_json}", with: canvasJSON)
    }

    private func log(_ msg: String) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "[\(f.string(from: Date()))] \(msg)\n"
        if let h = try? FileHandle(forWritingTo: Store.logURL) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? line.write(to: Store.logURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            objectWillChange.send()
        }
    }
}
