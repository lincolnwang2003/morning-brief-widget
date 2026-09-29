import Foundation
import SwiftUI

/// One task on the list. Matches the JSON the agent returns (see prompt.md).
struct BriefItem: Codable, Hashable {
    var title: String
    var time: String?
    var priority: String
    var sources: [String]?
    var reason: String?
    var link: String?
    var date: String?

    var url: URL? {
        guard let link, link.hasPrefix("http") else { return nil }
        return URL(string: link)
    }

    var color: Color {
        switch priority {
        case "high": return .red
        case "medium": return .yellow
        default: return .gray
        }
    }

    var meta: String {
        let labels = ["canvas": "Canvas", "calendar": "Calendar", "gmail": "Email"]
        let src = (sources ?? []).map { labels[$0] ?? $0 }.joined(separator: " · ")
        return [time, src.isEmpty ? nil : src, reason].compactMap { $0 }.joined(separator: "  ·  ")
    }
}

struct Brief: Codable {
    var summary: String = ""
    var today: [BriefItem] = []
    var upcoming: [BriefItem] = []
    var status: String?
    var error: String?
    var generated_at: String?

    /// Upcoming items grouped by date, in date order.
    var upcomingByDay: [(date: String, items: [BriefItem])] {
        Dictionary(grouping: upcoming, by: { $0.date ?? "" })
            .sorted { $0.key < $1.key }
            .map { (date: $0.key, items: $0.value) }
    }

    static func dayLabel(_ iso: String) -> String {
        let parse = DateFormatter()
        parse.dateFormat = "yyyy-MM-dd"
        guard let d = parse.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "EEE, MMM d"
        return out.string(from: d)
    }
}

/// Where the app keeps its files. The widget runs sandboxed, so it reads from the real
/// home folder through a read-only entitlement exception for this directory.
enum Store {
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var dir: URL { realHome.appendingPathComponent("Library/Application Support/MorningBrief") }
    static var briefURL: URL { dir.appendingPathComponent("today.json") }
    static var configURL: URL { dir.appendingPathComponent("config.json") }
    static var logURL: URL { dir.appendingPathComponent("run.log") }

    static func loadBrief() -> Brief? {
        guard let data = try? Data(contentsOf: briefURL) else { return nil }
        return try? JSONDecoder().decode(Brief.self, from: data)
    }
}
