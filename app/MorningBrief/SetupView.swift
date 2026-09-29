import SwiftUI

/// First-run setup: Claude Code -> Canvas link -> Gmail & Calendar -> done.
struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var canvasURL = ""
    @State private var canvasStatus: String?
    @State private var canvasOK = false
    @State private var checking = false

    private var claudeOK: Bool { model.claudePath != nil }
    private var connectorsOK: Bool { model.connections.gmail && model.connections.calendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up Morning Brief").font(.title2.bold())
                Text("Three quick steps. Everything stays on your Mac, and the AI can only read, never send or change anything.")
                    .foregroundStyle(.secondary)
            }

            step(1, "Install Claude Code", done: claudeOK) {
                if claudeOK {
                    Text("Found at \(model.claudePath!)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Morning Brief uses Claude as its AI. You need a Claude Pro or Max subscription. Paste this into Terminal, then sign in:")
                        .font(.callout)
                    CopyField(text: "curl -fsSL https://claude.ai/install.sh | bash")
                    Button("Check again") { model.claudePath = Agent.findClaude() }
                }
            }

            step(2, "Paste your Canvas calendar link", done: canvasOK) {
                Text("In Canvas, open **Calendar** → **Calendar Feed** (bottom right) and copy the link.")
                    .font(.callout)
                HStack {
                    TextField("https://canvas.….edu/feeds/calendars/user_….ics", text: $canvasURL)
                        .textFieldStyle(.roundedBorder)
                    Button("Test") { Task { await testCanvas() } }.disabled(canvasURL.isEmpty)
                }
                if let canvasStatus {
                    Text(canvasStatus).font(.caption).foregroundStyle(canvasOK ? .green : .orange)
                }
            }

            step(3, "Connect Gmail and Google Calendar", done: connectorsOK) {
                Text("This opens Claude in Terminal. Type **/mcp**, then sign in to **claude.ai Gmail** and **claude.ai Google Calendar**.")
                    .font(.callout)
                HStack {
                    Button("Open Terminal") { if let c = model.claudePath { Agent.openConnectTerminal(claude: c) } }
                        .disabled(!claudeOK)
                    Button("Check again") { Task { await checkConnections() } }.disabled(!claudeOK || checking)
                    if checking { ProgressView().controlSize(.small) }
                }
                HStack(spacing: 14) {
                    status("Gmail", model.connections.gmail)
                    status("Google Calendar", model.connections.calendar)
                }.font(.caption)
            }

            Divider()
            HStack {
                Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                Spacer()
                Picker("Update at", selection: $model.config.runHour) {
                    ForEach(5..<12) { Text("\($0):00 AM").tag($0) }
                }.frame(width: 170)
            }
            HStack {
                Spacer()
                Button(model.config.setupDone ? "Save" : "Finish setup") { finish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!(claudeOK && canvasOK && connectorsOK))
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            canvasURL = model.config.canvasURL
            canvasOK = !canvasURL.isEmpty && model.config.setupDone
            Task { await checkConnections() }
        }
    }

    @ViewBuilder
    private func step(_ n: Int, _ title: String, done: Bool, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor).frame(width: 24, height: 24)
                if done { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                else { Text("\(n)").font(.caption.bold()).foregroundStyle(.white) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content()
            }
        }
    }

    private func status(_ name: String, _ ok: Bool) -> some View {
        Label(name, systemImage: ok ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(ok ? .green : .secondary)
    }

    private func testCanvas() async {
        canvasStatus = "Checking…"
        do {
            let items = try await Canvas.upcoming(feed: canvasURL, days: 14)
            canvasOK = true
            canvasStatus = "✓ Connected. \(items.count) item\(items.count == 1 ? "" : "s") in the next two weeks."
        } catch {
            canvasOK = false
            canvasStatus = error.localizedDescription
        }
    }

    private func checkConnections() async {
        guard let claude = model.claudePath else { return }
        checking = true
        model.connections = await Task.detached { Agent.checkConnections(claude: claude) }.value
        checking = false
    }

    private func finish() {
        let firstTime = !model.config.setupDone
        model.config.canvasURL = canvasURL.trimmingCharacters(in: .whitespacesAndNewlines)
        model.config.setupDone = true
        model.saveConfig()
        if firstTime {
            model.launchAtLogin = true
            Task { await model.refresh() }
        }
        model.startSchedule()
        dismiss()
    }
}

struct CopyField: View {
    let text: String
    @State private var copied = false
    var body: some View {
        HStack {
            Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .padding(6).background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
            }
        }
    }
}
