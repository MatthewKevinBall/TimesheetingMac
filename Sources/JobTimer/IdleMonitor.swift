import AppKit

/// Watches for time away from the keyboard, forgotten timers and the end of the day.
@MainActor
final class IdleMonitor {
    private let store: Store
    private var timer: Timer?
    private var awaySince: Date?
    private var prompting = false
    /// Last moment a timer was running (or we nudged) — drives the "no timer running" nudge.
    private var lastTrackingOrNudge = Date()
    private var longRunReminded: (entry: UUID, count: Int)?

    init(store: Store) {
        self.store = store
    }

    static var systemIdleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.markAway() }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.markAway() }
        }
    }

    private func markAway() {
        if store.running != nil, awaySince == nil { awaySince = Date() }
    }

    private func check() {
        store.heartbeat()
        guard !prompting else { return }
        let idle = Self.systemIdleSeconds
        let now = Date()
        let threshold = TimeInterval(Prefs.idleMinutes * 60)

        if let running = store.running {
            lastTrackingOrNudge = now
            if Prefs.idleMinutes > 0 {
                if awaySince == nil, idle >= threshold {
                    awaySince = now.addingTimeInterval(-idle)
                } else if let since = awaySince, idle < 10 {
                    awaySince = nil
                    let back = now.addingTimeInterval(-idle)
                    if back.timeIntervalSince(since) >= threshold {
                        promptReturn(since: max(since, running.start), back: back)
                    }
                }
            }
            longRunCheck(running, now: now)
        } else {
            awaySince = nil
            nudgeCheck(idle: idle, now: now)
        }
        endOfDayCheck(now: now)
    }

    private func promptReturn(since: Date, back: Date) {
        guard let job = store.runningJob else { return }
        prompting = true
        defer { prompting = false }

        let alert = NSAlert()
        alert.messageText = "You were away for \(Fmt.duration(back.timeIntervalSince(since)))"
        alert.informativeText = """
        The timer for \(job.displayName) kept running from \(Fmt.time.string(from: since)) to \(Fmt.time.string(from: back)).

        If you removed it, you can still give that time to another job from the Timesheet.
        """
        alert.addButton(withTitle: "Remove Away Time")
        alert.addButton(withTitle: "Keep It")
        alert.addButton(withTitle: "Remove & Stop Timer")
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            store.stop(at: since)
            store.start(job, at: back)
        case .alertThirdButtonReturn:
            store.stop(at: since)
        default:
            break
        }
    }

    private func nudgeCheck(idle: TimeInterval, now: Date) {
        let minutes = Prefs.nudgeMinutes
        guard minutes > 0, idle < 120, Prefs.isWorkTime(now) else { return }
        guard now.timeIntervalSince(lastTrackingOrNudge) >= TimeInterval(minutes * 60) else { return }
        lastTrackingOrNudge = now
        AppController.shared.notify(
            id: "nudge",
            title: "No timer running",
            body: "What are you working on? Click here or press ⌥⌘T to pick a job.",
            action: "switcher"
        )
    }

    private func longRunCheck(_ entry: TimeEntry, now: Date) {
        let hours = Prefs.longRunHours
        guard hours > 0, let job = store.job(for: entry.jobID) else { return }
        let count = Int(entry.duration(now: now) / TimeInterval(hours * 3600))
        guard count >= 1 else { return }
        if let r = longRunReminded, r.entry == entry.id, r.count >= count { return }
        longRunReminded = (entry.id, count)
        AppController.shared.notify(
            id: "longrun",
            title: "Still working on \(job.displayName)?",
            body: "This timer has been running for \(Fmt.duration(entry.duration(now: now))). Click to switch jobs.",
            action: "switcher"
        )
    }

    /// Weekday (Mon–Fri) reminder to update the timesheet, 4pm by default.
    private func endOfDayCheck(now: Date) {
        let cal = Calendar.current
        guard Prefs.endOfDayReminder, !cal.isDateInWeekend(now) else { return }
        let minutesNow = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let reminderAt = Prefs.timesheetReminderMinutes
        // Fire at the reminder time, or on wake if the Mac was asleep then — but not late in the evening.
        guard minutesNow >= reminderAt, minutesNow < max(reminderAt + 180, 20 * 60) else { return }
        let d = UserDefaults.standard
        if let last = d.object(forKey: "endOfDayNotified") as? Date, cal.isDate(last, inSameDayAs: now) { return }
        d.set(now, forKey: "endOfDayNotified")
        let tracked = store.totalSeconds(on: now)
        AppController.shared.notify(
            id: "endofday",
            title: "Update your timesheet",
            body: tracked > 0
                ? "Today so far: \(Fmt.hours(store.billableSeconds(on: now)))h billable. Click to open your timesheet, then copy it into Spacecamp."
                : "Nothing tracked today yet. Click to open your timesheet and fill in the gaps.",
            action: "timesheet"
        )
    }
}
