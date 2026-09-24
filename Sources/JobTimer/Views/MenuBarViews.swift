import SwiftUI

struct MenuBarLabel: View {
    private var store = Store.shared

    var body: some View {
        if let entry = store.running, let job = store.job(for: entry.jobID) {
            Image(systemName: "timer")
            Text("\(job.shortLabel) \(Fmt.hm(entry.duration(now: store.now)))")
        } else {
            Image(systemName: "pause.circle")
            Text("Not tracking")
        }
    }
}

struct MenuContentView: View {
    private var store = Store.shared
    @State private var query = ""

    private var filtered: [Job] { store.filteredJobs(query) }
    private var canCreate: Bool { !query.trimmed.isEmpty && !store.hasExactMatch(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CurrentTimerCard()

            Divider()

            TextField("Switch job, or type a new one…", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(filtered) { job in
                        Button {
                            store.start(job)
                            query = ""
                        } label: {
                            JobPickRow(job: job,
                                       isRunning: store.running?.jobID == job.id,
                                       today: store.seconds(for: job.id, on: store.now))
                        }
                        .buttonStyle(.plain)
                    }
                    if canCreate {
                        Button(action: createAndStart) {
                            HStack {
                                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                                Text("Create “\(query.trimmed)” and start")
                                Spacer()
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if store.jobs.isEmpty && query.isEmpty {
                        Text("No jobs yet. Type one above and press Return. Start with the job number to keep it separate, e.g. “4521 Acme website”.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
            }
            .frame(maxHeight: 260)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Text("Today")
                Spacer()
                Text("\(Fmt.hm(store.totalSeconds(on: store.now))) tracked · \(Fmt.hours(store.billableSeconds(on: store.now)))h billable")
                    .monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Button("Timesheet") { AppController.shared.showMainWindow(tab: .timesheet) }
                Button("Jobs") { AppController.shared.showMainWindow(tab: .jobs) }
                Spacer()
                Button { AppController.shared.showMainWindow(tab: .settings) } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                }
                .help("Quit Job Timer")
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    private func submit() {
        guard !query.trimmed.isEmpty else { return }
        if let first = filtered.first {
            store.start(first)
            query = ""
        } else {
            createAndStart()
        }
    }

    private func createAndStart() {
        let job = store.addJob(fromText: query)
        store.start(job)
        query = ""
    }
}
