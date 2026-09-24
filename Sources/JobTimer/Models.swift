import Foundation
import SwiftUI

struct Job: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Spacecamp job number (optional).
    var code: String
    var name: String
    var colorIndex: Int
    var archived = false
    var pinned = false
    var lastUsed: Date?

    var displayName: String {
        [code, name].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Compact label for the menu bar.
    var shortLabel: String {
        if !code.isEmpty { return code }
        return name.count > 18 ? String(name.prefix(17)) + "…" : name
    }

    var color: Color { JobPalette.colors[colorIndex % JobPalette.colors.count] }
}

enum JobPalette {
    static let colors: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .red, .yellow, .indigo, .mint, .brown, .cyan]
}

struct TimeEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var jobID: UUID
    var start: Date
    var end: Date?
    var note: String = ""

    var isRunning: Bool { end == nil }

    func duration(now: Date = Date()) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

struct AppData: Codable {
    var jobs: [Job] = []
    var entries: [TimeEntry] = []
}

enum MainTab: Hashable {
    case timesheet, jobs, settings
}

struct JobSummary: Identifiable {
    let job: Job
    let seconds: TimeInterval
    let notes: [String]
    var id: UUID { job.id }
}

enum TimelineItem: Identifiable {
    case entry(TimeEntry)
    case gap(start: Date, end: Date)

    var id: String {
        switch self {
        case .entry(let e): return e.id.uuidString
        case .gap(let s, _): return "gap-\(s.timeIntervalSince1970)"
        }
    }
}
