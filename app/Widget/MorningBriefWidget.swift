import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let brief: Brief?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, brief: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, brief: context.isPreview ? (Store.loadBrief() ?? .sample) : Store.loadBrief()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The app reloads the widget after every update; this is only a safety net.
        let entry = Entry(date: .now, brief: Store.loadBrief())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode
    let entry: Entry

    var body: some View {
        Group {
            if let brief = entry.brief {
                switch family {
                case .systemSmall: small(brief)
                case .systemMedium: list(brief, todayLimit: 4, showUpcoming: false)
                default: list(brief, todayLimit: 6, showUpcoming: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Morning Brief").font(.headline)
                    Text("Open the Morning Brief app to finish setup.").font(.caption).dim()
                }
            }
        }
        // In the dimmed "vibrant" mode everything is tinted one color, so a filled background
        // would swallow the text. Draw no background there and let the system glass show.
        .containerBackground(for: .widget) {
            if mode == .fullColor { Rectangle().fill(.fill.tertiary) } else { Color.clear }
        }
    }

    private func small(_ brief: Brief) -> some View {
        let high = brief.today.filter { $0.priority == "high" }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.caption.weight(.semibold)).dim()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(brief.today.count)").font(.system(size: 34, weight: .bold, design: .rounded))
                Text("today").font(.caption).dim()
            }
            if high > 0 {
                Label("\(high) urgent", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(.red).widgetAccentable()
            }
            Spacer(minLength: 0)
            if let first = brief.today.first ?? brief.upcoming.first {
                Row(item: first, compact: true)
            }
        }
    }

    private func list(_ brief: Brief, todayLimit: Int, showUpcoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.headline)
                Spacer()
                if brief.status == "error" { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            if showUpcoming, !brief.summary.isEmpty {
                Text(brief.summary).font(.caption).dim().lineLimit(2)
            }
            Title("Today")
            if brief.today.isEmpty {
                Text("Nothing due today").font(.caption).dim()
            }
            ForEach(brief.today.prefix(todayLimit), id: \.self) { Row(item: $0) }

            if showUpcoming {
                ForEach(brief.upcomingByDay.prefix(3), id: \.date) { day in
                    Title(Brief.dayLabel(day.date))
                    ForEach(day.items.prefix(3), id: \.self) { Row(item: $0) }
                }
            } else if !brief.upcoming.isEmpty {
                Text("+ \(brief.upcoming.count) in the next few days")
                    .font(.caption2).dim().padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }
}

/// When another app is in front, macOS draws desktop widgets in "vibrant" mode: no background,
/// no color, and secondary text fades to near-invisible. Keep text readable there.
private struct Dim: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode
    func body(content: Content) -> some View {
        content.foregroundStyle(mode == .fullColor ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary.opacity(0.8)))
    }
}

private extension View {
    func dim() -> some View { modifier(Dim()) }
}

/// Priority shown by shape as well as color, so it survives when the color is stripped.
private struct PriorityMark: View {
    let priority: String
    var body: some View {
        switch priority {
        case "high":
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).widgetAccentable()
        case "medium":
            Image(systemName: "circle.fill").foregroundStyle(.yellow).imageScale(.small)
        default:
            Image(systemName: "circle").foregroundStyle(.gray).imageScale(.small)
        }
    }
}

private struct Title: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).dim().padding(.top, 5)
    }
}

private struct Row: View {
    let item: BriefItem
    var compact = false

    var body: some View {
        let content = HStack(alignment: .firstTextBaseline, spacing: 6) {
            PriorityMark(priority: item.priority)
            Text(item.title).font(compact ? .caption : .caption.weight(.medium)).lineLimit(compact ? 2 : 1)
            Spacer(minLength: 0)
            if !compact, let time = item.time {
                Text(time).font(.caption2).dim()
            }
        }
        if let url = item.url { Link(destination: url) { content } } else { content }
    }
}

@main
struct MorningBriefWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MorningBrief", provider: Provider()) { WidgetView(entry: $0) }
            .configurationDisplayName("Morning Brief")
            .description("Your ranked to-do list from Canvas, email and calendar.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

extension Brief {
    static let sample = Brief(
        summary: "A team deliverable is due tomorrow night; two meetings today.",
        today: [
            BriefItem(title: "Team Assignment 4", time: "23:59", priority: "high", sources: ["canvas"]),
            BriefItem(title: "PM Group Meeting", time: "12:00", priority: "medium", sources: ["calendar"]),
        ],
        upcoming: [BriefItem(title: "Quiz 1 retake", time: "16:00", priority: "high", sources: ["gmail"], date: "2026-10-01")],
        status: "ok")
}
