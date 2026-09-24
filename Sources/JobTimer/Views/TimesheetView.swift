import AppKit
import SwiftUI

struct TimesheetView: View {
    private var store = Store.shared
    @State private var day = Date()
    @State private var copied = false
    @AppStorage("rounding") private var roundingRaw = RoundingMode.nearest.rawValue

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summarySection
                    entriesSection
                }
                .padding(20)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
            DatePicker("", selection: $day, displayedComponents: .date)
                .labelsHidden()
                .fixedSize()
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
            Button("Today") { day = Date() }
                .disabled(calendar.isDateInToday(day))
            Text(Fmt.longDate.string(from: day))
                .font(.title3.weight(.semibold))
                .padding(.leading, 8)
            Spacer()
            Picker("Rounding", selection: $roundingRaw) {
                ForEach(RoundingMode.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .fixedSize()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(store.summaryText(on: day), forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Label(copied ? "Copied!" : "Copy Summary", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func shiftDay(_ n: Int) {
        day = calendar.date(byAdding: .day, value: n, to: day) ?? day
    }

    // MARK: Summary

    private var summarySection: some View {
        let summary = store.summary(on: day)
        let mode = RoundingMode(rawValue: roundingRaw) ?? .nearest
        let total = summary.reduce(0) { $0 + $1.seconds }
        let billable = summary.reduce(0) { $0 + Billing.round($1.seconds, mode: mode) }

        return VStack(alignment: .leading, spacing: 10) {
            Text("For Spacecamp").font(.headline)
            if summary.isEmpty {
                Text("Nothing tracked on this day.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("Job")
                        Text("Tracked")
                        Text("Hours")
                        Text("Notes")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach(summary) { s in
                        let hours = Fmt.hours(Billing.round(s.seconds, mode: mode))
                        GridRow {
                            HStack(spacing: 6) {
                                ColorDot(color: s.job.color)
                                Text(s.job.displayName).lineLimit(1)
                            }
                            Text(Fmt.hm(s.seconds)).monospacedDigit().foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Text(hours).monospacedDigit().bold()
                                CopyButton(text: hours, help: "Copy hours")
                            }
                            HStack(spacing: 4) {
                                Text(s.notes.joined(separator: "; "))
                                    .lineLimit(2)
                                    .foregroundStyle(.secondary)
                                if !s.notes.isEmpty {
                                    CopyButton(text: s.notes.joined(separator: "; "), help: "Copy notes")
                                }
                            }
                            .gridColumnAlignment(.leading)
                        }
                    }

                    Divider()

                    GridRow {
                        Text("Total").bold()
                        Text(Fmt.hm(total)).monospacedDigit().foregroundStyle(.secondary)
                        Text(Fmt.hours(billable)).monospacedDigit().bold()
                        Text("")
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            }
        }
    }

    // MARK: Entries

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Entries").font(.headline)
                Spacer()
                Button {
                    addManualEntry()
                } label: {
                    Label("Add Entry", systemImage: "plus")
                }
                .disabled(store.activeJobs.isEmpty)
            }

            let items = store.timeline(on: day)
            if items.isEmpty {
                Text("No entries. Use “Add Entry” to add time you forgot to track.")
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                switch item {
                case .entry(let e): EntryRow(entry: e)
                case .gap(let s, let e): GapRow(start: s, end: e)
                }
            }
        }
    }

    private func addManualEntry() {
        guard let job = store.activeJobs.first else { return }
        let dayEntries = store.entries(on: day)
        let nineAM = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        let start = dayEntries.compactMap(\.end).max() ?? nineAM
        store.addEntry(jobID: job.id, start: start, end: start.addingTimeInterval(Billing.block))
    }
}

private struct CopyButton: View {
    let text: String
    let help: String

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc").font(.caption)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

private struct EntryRow: View {
    let entry: TimeEntry
    private var store = Store.shared

    init(entry: TimeEntry) {
        self.entry = entry
    }

    var body: some View {
        HStack(spacing: 10) {
            ColorDot(color: store.job(for: entry.jobID)?.color ?? .gray, size: 10)

            Picker("", selection: binding(\.jobID)) {
                ForEach(store.pickerJobs(including: entry.jobID)) { job in
                    Text(job.displayName).tag(job.id)
                }
            }
            .labelsHidden()
            .frame(width: 220)

            DatePicker("", selection: binding(\.start), displayedComponents: .hourAndMinute)
                .labelsHidden()
            Text("–")
            if entry.isRunning {
                Text("now")
                    .foregroundStyle(.green)
                    .frame(width: 70, alignment: .leading)
            } else {
                DatePicker("", selection: endBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }

            Text(Fmt.hm(entry.duration(now: store.now)))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)

            TextField("Note", text: binding(\.note))
                .textFieldStyle(.roundedBorder)

            if entry.isRunning {
                Button { store.stop() } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.borderless)
                    .help("Stop timer")
            }
            Button { store.deleteEntry(entry.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete entry")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private func binding<T>(_ keyPath: WritableKeyPath<TimeEntry, T>) -> Binding<T> {
        let id = entry.id
        let fallback = entry[keyPath: keyPath]
        return Binding(
            get: { store.entries.first { $0.id == id }?[keyPath: keyPath] ?? fallback },
            set: { value in store.updateEntry(id) { $0[keyPath: keyPath] = value } }
        )
    }

    private var endBinding: Binding<Date> {
        let id = entry.id
        return Binding(
            get: { store.entries.first { $0.id == id }?.end ?? Date() },
            set: { value in store.updateEntry(id) { $0.end = value } }
        )
    }
}

private struct GapRow: View {
    let start: Date
    let end: Date
    private var store = Store.shared

    init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            Text("Untracked \(Fmt.time.string(from: start)) – \(Fmt.time.string(from: end))")
            Text(Fmt.hm(end.timeIntervalSince(start))).monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            Menu("Assign to Job") {
                ForEach(store.activeJobs) { job in
                    Button(job.displayName) { store.addEntry(jobID: job.id, start: start, end: end) }
                }
            }
            .fixedSize()
            .disabled(store.activeJobs.isEmpty)
        }
        .font(.callout)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary.opacity(0.5))
        )
    }
}
