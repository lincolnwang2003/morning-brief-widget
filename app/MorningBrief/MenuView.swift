import SwiftUI

/// The panel that drops down from the menu bar icon.
struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)

            if model.needsSetup {
                setupPrompt
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !model.brief.summary.isEmpty {
                            Text(model.brief.summary)
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 6)
                        }
                        SectionTitle("Today")
                        if model.brief.today.isEmpty {
                            Text(model.brief.generated_at == nil ? "No list yet. Click Refresh." : "Nothing due today 🎉")
                                .font(.callout).foregroundStyle(.secondary).padding(.vertical, 4)
                        }
                        ForEach(model.brief.today, id: \.self) { ItemRow(item: $0) }

                        ForEach(model.brief.upcomingByDay, id: \.date) { day in
                            SectionTitle(Brief.dayLabel(day.date))
                            ForEach(day.items, id: \.self) { ItemRow(item: $0) }
                        }
                    }
                }
                .frame(maxHeight: 460)
            }

            footer
        }
        .padding(14)
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.headline)
            Spacer()
            if model.isRunning {
                ProgressView().controlSize(.small)
                Text("Updating…").font(.caption).foregroundStyle(.secondary)
            } else if !model.needsSetup {
                Button("Refresh") { Task { await model.refresh() } }
                    .buttonStyle(.link)
            }
        }
    }

    private var setupPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to Morning Brief").font(.title3.bold())
            Text("Connect Canvas, Gmail and Google Calendar to get one ranked to-do list every morning.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Start setup") { openSetup() }.buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.brief.status == "error", let err = model.brief.error {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                if let g = model.brief.generated_at {
                    Text("Updated \(g.replacingOccurrences(of: "T", with: " "))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Settings…") { openSetup() }.buttonStyle(.link).font(.caption)
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.link).font(.caption)
            }
        }
        .padding(.top, 8)
    }

    private func openSetup() {
        openWindow(id: "setup")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.top, 10).padding(.bottom, 4)
    }
}

struct ItemRow: View {
    let item: BriefItem
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(item.color).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body)
                if !item.meta.isEmpty {
                    Text(item.meta).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if item.url != nil && hover {
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(hover && item.url != nil ? Color.primary.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { if let url = item.url { NSWorkspace.shared.open(url) } }
    }
}
