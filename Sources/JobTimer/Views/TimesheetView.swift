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
                summarySection
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            HStack(spacing: 4) {
                                Text(Fmt.hm(s.seconds))
                                    .monospacedDigit()
                                    .foregroundStyle(s.adjustment == 0 ? Color.secondary : Color.orange)
                                    .help(s.adjustment == 0 ? "" : "Manually edited (timer: \(Fmt.hm(s.seconds - s.adjustment)))")
                                EditTrackedButton(summary: s, day: day)
                            }
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

/// Pencil button that lets you override a job's total for the day.
private struct EditTrackedButton: View {
    let summary: JobSummary
    let day: Date
    private var store = Store.shared
    @State private var editing = false
    @State private var text = ""

    init(summary: JobSummary, day: Date) {
        self.summary = summary
        self.day = day
    }

    private var parsed: TimeInterval? { Fmt.parseDuration(text) }

    var body: some View {
        Button {
            text = Fmt.hm(summary.seconds)
            editing = true
        } label: {
            Image(systemName: "pencil").font(.caption)
        }
        .buttonStyle(.borderless)
        .help("Edit time")
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(summary.job.displayName).font(.headline).lineLimit(1)
                TextField("1:30 or 1.5", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit(save)
                Text(parsed.map { "\(Fmt.hours(Billing.round($0)))h after rounding" } ?? "Enter a time like 1:30, 1.5 or 90m")
                    .font(.caption)
                    .foregroundStyle(parsed == nil ? Color.red : Color.secondary)
                HStack {
                    if summary.adjustment != 0 {
                        Button("Reset to Timer") {
                            store.clearAdjustment(for: summary.job.id, on: day)
                            editing = false
                        }
                    }
                    Spacer()
                    Button("Cancel") { editing = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(parsed == nil)
                }
            }
            .padding(14)
        }
    }

    private func save() {
        guard let seconds = parsed else { return }
        store.setSeconds(seconds, for: summary.job.id, on: day)
        editing = false
    }
}
