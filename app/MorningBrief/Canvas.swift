import Foundation

/// Downloads the Canvas calendar feed (.ics) and returns upcoming items.
/// Swift port of canvas.py.
enum Canvas {
    struct Item: Codable {
        var title: String
        var course: String?
        var due: String
        var is_assignment: Bool
        var url: String?
        var details: String
    }

    enum CanvasError: LocalizedError {
        case badURL, notCalendar
        var errorDescription: String? {
            switch self {
            case .badURL: return "That doesn't look like a Canvas calendar feed link (it should end in .ics)."
            case .notCalendar: return "The link opened, but it isn't a calendar feed."
            }
        }
    }

    static func upcoming(feed: String, days: Int) async throws -> [Item] {
        guard let url = URL(string: feed.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.hasPrefix("http") == true else { throw CanvasError.badURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let text = String(decoding: data, as: UTF8.self)
        guard text.contains("BEGIN:VCALENDAR") else { throw CanvasError.notCalendar }

        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: days, to: start)!
        let dayFmt = formatter("yyyy-MM-dd")
        let timeFmt = formatter("yyyy-MM-dd HH:mm")

        return parse(text)
            .filter { $0.start >= start && $0.start < end }
            .sorted { $0.start < $1.start }
            .map { ev in
                let (title, course) = splitCourse(ev.summary)
                let url = ev.url ?? ""
                return Item(title: title, course: course,
                            due: ev.allDay ? dayFmt.string(from: ev.start) : timeFmt.string(from: ev.start),
                            is_assignment: url.contains("assignment") || ev.description.lowercased().contains("assignment"),
                            url: ev.url,
                            details: String(ev.description.prefix(300)))
            }
    }

    // MARK: - ICS parsing

    private struct Event {
        var start: Date
        var allDay: Bool
        var summary = "(untitled)"
        var description = ""
        var url: String?
    }

    private static func parse(_ text: String) -> [Event] {
        // Long lines are folded: a line starting with a space continues the previous one.
        let unfolded = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
        var events: [Event] = []
        var fields: [String: (params: String, value: String)]?

        for line in unfolded.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if line == "BEGIN:VEVENT" {
                fields = [:]
            } else if line == "END:VEVENT" {
                if let f = fields, let dt = f["DTSTART"], let (start, allDay) = parseDate(dt.params, dt.value) {
                    var ev = Event(start: start, allDay: allDay)
                    if let s = f["SUMMARY"] { ev.summary = unescape(s.value) }
                    if let d = f["DESCRIPTION"] { ev.description = unescape(d.value) }
                    ev.url = f["URL"]?.value
                    events.append(ev)
                }
                fields = nil
            } else if fields != nil, let colon = line.firstIndex(of: ":") {
                let keyPart = line[..<colon]
                let value = String(line[line.index(after: colon)...])
                let parts = keyPart.split(separator: ";", maxSplits: 1)
                fields?[String(parts[0])] = (parts.count > 1 ? String(parts[1]) : "", value)
            }
        }
        return events
    }

    private static func parseDate(_ params: String, _ value: String) -> (Date, Bool)? {
        if params.contains("VALUE=DATE") || value.count == 8 {
            return formatter("yyyyMMdd").date(from: String(value.prefix(8))).map { ($0, true) }
        }
        if value.hasSuffix("Z") {
            let f = formatter("yyyyMMdd'T'HHmmss'Z'")
            f.timeZone = TimeZone(identifier: "UTC")
            return f.date(from: value).map { ($0, false) }
        }
        return formatter("yyyyMMdd'T'HHmmss").date(from: String(value.prefix(15))).map { ($0, false) }
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n")
         .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
         .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func splitCourse(_ summary: String) -> (String, String?) {
        // Canvas titles look like "Homework 3 [PM 4001]"
        guard summary.hasSuffix("]"), let open = summary.lastIndex(of: "[") else { return (summary, nil) }
        let title = summary[..<open].trimmingCharacters(in: .whitespaces)
        let course = summary[summary.index(after: open)..<summary.index(before: summary.endIndex)]
        return (title, String(course))
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}
