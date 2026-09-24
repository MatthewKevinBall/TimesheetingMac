import SwiftUI

struct JobsView: View {
    private var store = Store.shared
    @State private var newCode = ""
    @State private var newName = ""
    @State private var showArchived = false

    private var visibleJobs: [Job] {
        showArchived ? store.activeJobs + store.jobs.filter(\.archived) : store.activeJobs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TextField("Job number", text: $newCode)
                    .frame(width: 120)
                TextField("Job name / client", text: $newName)
                    .onSubmit(add)
                Button("Add Job", action: add)
                    .disabled(newCode.trimmed.isEmpty && newName.trimmed.isEmpty)
            }
            .textFieldStyle(.roundedBorder)
            .padding(16)

            Divider()

            if visibleJobs.isEmpty {
                Text("No jobs yet. Add the jobs you work on regularly.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleJobs) { job in
                        JobEditRow(job: job)
                    }
                }
            }

            Divider()

            HStack {
                Toggle("Show archived jobs", isOn: $showArchived)
                Spacer()
                Text("Click a colour dot to change it · ★ pins a job to the top")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private func add() {
        guard !(newCode.trimmed.isEmpty && newName.trimmed.isEmpty) else { return }
        store.addJob(code: newCode, name: newName)
        newCode = ""
        newName = ""
    }
}

private struct JobEditRow: View {
    let job: Job
    private var store = Store.shared

    init(job: Job) {
        self.job = job
    }

    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                store.updateJob(job.id) { $0.colorIndex = ($0.colorIndex + 1) % JobPalette.colors.count }
            } label: {
                ColorDot(color: job.color, size: 14)
            }
            .buttonStyle(.plain)
            .help("Change colour")

            TextField("Number", text: binding(\.code))
                .frame(width: 110)
            TextField("Name", text: binding(\.name))

            Text("This week \(Fmt.hm(store.seconds(for: job.id, since: weekStart)))")
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)

            Button {
                store.updateJob(job.id) { $0.pinned.toggle() }
            } label: {
                Image(systemName: job.pinned ? "star.fill" : "star")
                    .foregroundStyle(job.pinned ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(job.pinned ? "Unpin" : "Pin to top")

            Button {
                store.updateJob(job.id) { $0.archived.toggle() }
            } label: {
                Image(systemName: job.archived ? "tray.and.arrow.up" : "archivebox")
            }
            .buttonStyle(.borderless)
            .help(job.archived ? "Unarchive" : "Archive (hide from lists, keep history)")

            Button {
                store.deleteJob(job.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(store.hasEntries(job.id))
            .help(store.hasEntries(job.id) ? "Has tracked time. Archive it instead." : "Delete job")
        }
        .textFieldStyle(.roundedBorder)
        .opacity(job.archived ? 0.55 : 1)
        .padding(.vertical, 2)
    }

    private func binding(_ keyPath: WritableKeyPath<Job, String>) -> Binding<String> {
        let id = job.id
        return Binding(
            get: { store.job(for: id)?[keyPath: keyPath] ?? "" },
            set: { value in store.updateJob(id) { $0[keyPath: keyPath] = value } }
        )
    }
}
