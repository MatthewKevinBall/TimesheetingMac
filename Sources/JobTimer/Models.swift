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

/// A manual correction to a job's tracked time on one day, added on top of its entries.
struct Adjustment: Codable, Hashable {
    var jobID: UUID
    /// Start of the day it applies to.
    var day: Date
    var seconds: TimeInterval
}

struct AppData: Codable {
    var jobs: [Job] = []
    var entries: [TimeEntry] = []
    var adjustments: [Adjustment] = []

    init(jobs: [Job], entries: [TimeEntry], adjustments: [Adjustment]) {
        self.jobs = jobs
        self.entries = entries
        self.adjustments = adjustments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jobs = try c.decodeIfPresent([Job].self, forKey: .jobs) ?? []
        entries = try c.decodeIfPresent([TimeEntry].self, forKey: .entries) ?? []
        adjustments = try c.decodeIfPresent([Adjustment].self, forKey: .adjustments) ?? []
    }
}

enum MainTab: Hashable {
    case timesheet, jobs, settings
}

struct JobSummary: Identifiable {
    let job: Job
    /// Timer total plus any manual adjustment.
    let seconds: TimeInterval
    let adjustment: TimeInterval
    let notes: [String]
    var id: UUID { job.id }
}
