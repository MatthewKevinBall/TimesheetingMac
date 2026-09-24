import Foundation
import Observation

@MainActor @Observable
final class Store {
    static let shared = Store()

    private(set) var jobs: [Job] = []
    private(set) var entries: [TimeEntry] = []
    /// Ticks every second so timers in the UI stay live.
    var now = Date()
    var mainTab: MainTab = .timesheet

    let dataDirectory: URL
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var saveWork: DispatchWorkItem?

    private var fileURL: URL { dataDirectory.appendingPathComponent("data.json") }
    private let calendar = Calendar.current

    private init() {
        dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JobTimer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        load()
        backupIfNeeded()

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    // MARK: - Queries

    var running: TimeEntry? { entries.last(where: \.isRunning) }
    var runningJob: Job? { running.flatMap { job(for: $0.jobID) } }

    func job(for id: UUID) -> Job? { jobs.first { $0.id == id } }

    /// Non-archived jobs: pinned first, then most recently used.
    var activeJobs: [Job] {
        jobs.filter { !$0.archived }.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            let la = a.lastUsed ?? .distantPast, lb = b.lastUsed ?? .distantPast
            if la != lb { return la > lb }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    func filteredJobs(_ query: String) -> [Job] {
        let tokens = query.lowercased().split(separator: " ")
        guard !tokens.isEmpty else { return activeJobs }
        return activeJobs.filter { job in
            let hay = job.displayName.lowercased()
            return tokens.allSatisfy { hay.contains($0) }
        }
    }

    func hasExactMatch(_ text: String) -> Bool {
        let t = text.trimmed.lowercased()
        return jobs.contains { job in
            !job.archived && [job.name, job.code, job.displayName, "\(job.code) \(job.name)"]
                .map { $0.lowercased() }.contains(t)
        }
    }

    /// Jobs to offer in a picker: active ones plus `jobID` if it's archived.
    func pickerJobs(including jobID: UUID) -> [Job] {
        var list = activeJobs
        if !list.contains(where: { $0.id == jobID }), let j = job(for: jobID) { list.append(j) }
        return list
    }

    func entries(on day: Date) -> [TimeEntry] {
        entries.filter { calendar.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
    }

    func seconds(for jobID: UUID, on day: Date) -> TimeInterval {
        entries(on: day).filter { $0.jobID == jobID }.reduce(0) { $0 + $1.duration(now: now) }
    }

    func seconds(for jobID: UUID, since date: Date) -> TimeInterval {
        entries.filter { $0.jobID == jobID && $0.start >= date }.reduce(0) { $0 + $1.duration(now: now) }
    }

    func totalSeconds(on day: Date) -> TimeInterval {
        entries(on: day).reduce(0) { $0 + $1.duration(now: now) }
    }

    func billableSeconds(on day: Date) -> TimeInterval {
        summary(on: day).reduce(0) { $0 + Billing.round($1.seconds) }
    }

    /// Per-job totals for a day, in the order jobs were first worked on.
    func summary(on day: Date) -> [JobSummary] {
        var order: [UUID] = []
        var secs: [UUID: TimeInterval] = [:]
        var notes: [UUID: [String]] = [:]
        for e in entries(on: day) {
            if secs[e.jobID] == nil { order.append(e.jobID) }
            secs[e.jobID, default: 0] += e.duration(now: now)
            let n = e.note.trimmed
            if !n.isEmpty && !(notes[e.jobID]?.contains(n) ?? false) { notes[e.jobID, default: []].append(n) }
        }
        return order.compactMap { id in
            job(for: id).map { JobSummary(job: $0, seconds: secs[id] ?? 0, notes: notes[id] ?? []) }
        }
    }

    /// Entries for a day with untracked gaps (≥ 5 min) between them.
    func timeline(on day: Date) -> [TimelineItem] {
        var items: [TimelineItem] = []
        var prevEnd: Date?
        for e in entries(on: day) {
            if let p = prevEnd, e.start.timeIntervalSince(p) >= 300 {
                items.append(.gap(start: p, end: e.start))
            }
            items.append(.entry(e))
            let end = e.end ?? now
            prevEnd = max(prevEnd ?? end, end)
        }
        return items
    }

    func summaryText(on day: Date) -> String {
        let rows = summary(on: day)
        var lines = [Fmt.longDate.string(from: day), ""]
        for s in rows {
            var line = "\(s.job.displayName): \(Fmt.hours(Billing.round(s.seconds)))h"
            if !s.notes.isEmpty { line += " — " + s.notes.joined(separator: "; ") }
            lines.append(line)
        }
        lines.append("")
        lines.append("Total: \(Fmt.hours(billableSeconds(on: day)))h")
        return lines.joined(separator: "\n")
    }

    // MARK: - Timer actions

    func start(_ job: Job, at date: Date = Date()) {
        if running?.jobID == job.id { return }
        stop(at: date)
        entries.append(TimeEntry(jobID: job.id, start: date))
        if let i = jobs.firstIndex(where: { $0.id == job.id }) { jobs[i].lastUsed = date }
        save()
    }

    func stop(at date: Date = Date()) {
        guard let i = entries.lastIndex(where: \.isRunning) else { return }
        let end = max(date, entries[i].start)
        // Drop accidental blips from quick switching.
        if end.timeIntervalSince(entries[i].start) < 30 && entries[i].note.trimmed.isEmpty {
            entries.remove(at: i)
        } else {
            entries[i].end = end
        }
        save()
    }

    func setRunningNote(_ note: String) {
        guard let i = entries.lastIndex(where: \.isRunning) else { return }
        entries[i].note = note
        save()
    }

    /// "I actually started this 15 minutes ago" — moves the running entry's start
    /// earlier, trimming whatever entry it now overlaps.
    func backdateRunning(minutes: Int) {
        guard let i = entries.lastIndex(where: \.isRunning) else { return }
        let runningID = entries[i].id
        let oldStart = entries[i].start
        var newStart = oldStart.addingTimeInterval(TimeInterval(-minutes * 60))
        let others = entries.indices
            .filter { entries[$0].id != runningID && entries[$0].start < oldStart }
            .sorted { entries[$0].start > entries[$1].start }
        for j in others {
            guard let end = entries[j].end, end > newStart else { continue }
            newStart = max(newStart, entries[j].start)
            entries[j].end = newStart
        }
        entries[i].start = newStart
        entries.removeAll { e in e.end.map { $0 <= e.start } ?? false }
        save()
    }

    // MARK: - Editing

    func addEntry(jobID: UUID, start: Date, end: Date, note: String = "") {
        entries.append(TimeEntry(jobID: jobID, start: start, end: max(start, end), note: note))
        save()
    }

    func updateEntry(_ id: UUID, _ change: (inout TimeEntry) -> Void) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[i])
        if let end = entries[i].end, end < entries[i].start { entries[i].end = entries[i].start }
        save()
    }

    func deleteEntry(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    @discardableResult
    func addJob(code: String, name: String) -> Job {
        let job = Job(code: code.trimmed, name: name.trimmed, colorIndex: jobs.count % JobPalette.colors.count)
        jobs.append(job)
        save()
        return job
    }

    /// "4521 Acme website" → code "4521", name "Acme website".
    @discardableResult
    func addJob(fromText text: String) -> Job {
        let t = text.trimmed
        let parts = t.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0].contains(where: \.isNumber) {
            let name = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " -–·:"))
            return addJob(code: parts[0], name: name)
        }
        return addJob(code: "", name: t)
    }

    func updateJob(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
        save()
    }

    func hasEntries(_ jobID: UUID) -> Bool {
        entries.contains { $0.jobID == jobID }
    }

    func deleteJob(_ id: UUID) {
        guard !hasEntries(id) else { return }
        jobs.removeAll { $0.id == id }
        save()
    }

    // MARK: - Lifecycle

    func heartbeat() {
        UserDefaults.standard.set(Date(), forKey: "lastSeen")
    }

    /// On quit, close the running entry but remember it so a quick relaunch
    /// (restart, update) carries on seamlessly.
    func prepareForQuit() {
        let d = UserDefaults.standard
        if let e = running {
            d.set(e.jobID.uuidString, forKey: "resumeJobID")
            d.set(Date(), forKey: "resumeFrom")
            stop()
        }
        saveNow()
    }

    func recoverAfterLaunch() {
        let d = UserDefaults.standard
        defer {
            d.removeObject(forKey: "resumeJobID")
            d.removeObject(forKey: "resumeFrom")
        }
        if let i = entries.lastIndex(where: \.isRunning) {
            // App didn't quit cleanly. If it's been gone a while, end the entry when we last saw it.
            let lastSeen = (d.object(forKey: "lastSeen") as? Date) ?? entries[i].start
            if Date().timeIntervalSince(lastSeen) > 600 {
                entries[i].end = max(lastSeen, entries[i].start)
                save()
            }
        } else if let idString = d.string(forKey: "resumeJobID"),
                  let id = UUID(uuidString: idString),
                  let from = d.object(forKey: "resumeFrom") as? Date,
                  Date().timeIntervalSince(from) < 600,
                  let job = job(for: id) {
            start(job, at: from)
        }
    }

    // MARK: - Persistence

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoded = try Self.decoder.decode(AppData.self, from: data)
            jobs = decoded.jobs
            entries = decoded.entries
        } catch {
            NSLog("JobTimer: failed to read data.json: \(error)")
            // Keep the unreadable file rather than overwriting it.
            let bad = dataDirectory.appendingPathComponent("data-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: bad)
        }
    }

    func save() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        do {
            let data = try Self.encoder.encode(AppData(jobs: jobs, entries: entries))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("JobTimer: save failed: \(error)")
        }
    }

    /// One backup per day, kept for 30 days.
    private func backupIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        let dir = dataDirectory.appendingPathComponent("Backups", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let target = dir.appendingPathComponent("data-\(f.string(from: Date())).json")
        if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: fileURL, to: target) }
        let files = (try? fm.contentsOfDirectory(atPath: dir.path))?.filter { $0.hasPrefix("data-") }.sorted() ?? []
        for old in files.dropLast(30) { try? fm.removeItem(at: dir.appendingPathComponent(old)) }
    }
}
