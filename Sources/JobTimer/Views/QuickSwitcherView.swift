import SwiftUI

/// Spotlight-style job picker opened with ⌥⌘T.
struct QuickSwitcherView: View {
    static let width: CGFloat = 480
    static let height: CGFloat = 380

    let onClose: () -> Void
    private var store = Store.shared
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    private enum Row: Identifiable {
        case job(Job)
        case create(String)
        case stop

        var id: String {
            switch self {
            case .job(let j): return j.id.uuidString
            case .create: return "create"
            case .stop: return "stop"
            }
        }
    }

    private var rows: [Row] {
        var rows: [Row] = store.filteredJobs(query).map { .job($0) }
        let q = query.trimmed
        if !q.isEmpty && !store.hasExactMatch(q) { rows.append(.create(q)) }
        if q.isEmpty && store.running != nil { rows.append(.stop) }
        return rows
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "timer").font(.title2).foregroundStyle(.secondary)
                TextField("Switch to job, or type a new one…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($focused)
                    .onSubmit { choose(rows) }
                    .onKeyPress(.upArrow) {
                        selection = max(0, selection - 1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        selection = min(max(0, rows.count - 1), selection + 1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        onClose()
                        return .handled
                    }
            }
            .padding(14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            rowView(row, selected: index == selection)
                                .id(index)
                                .onTapGesture {
                                    selection = index
                                    choose(rows)
                                }
                        }
                        if rows.isEmpty {
                            Text("Type a job name to create your first job.\nTip: start with the job number, e.g. “4521 Acme website”.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selection) { _, new in proxy.scrollTo(new) }
            }

            Divider()

            HStack {
                Text("↑↓ select   ↩ start   esc close")
                Spacer()
                if let job = store.runningJob, let entry = store.running {
                    Text("Now: \(job.shortLabel) \(Fmt.hm(entry.duration(now: store.now)))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: Self.width, height: Self.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
        .onChange(of: query) { selection = 0 }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    @ViewBuilder
    private func rowView(_ row: Row, selected: Bool) -> some View {
        switch row {
        case .job(let job):
            JobPickRow(job: job,
                       isRunning: store.running?.jobID == job.id,
                       today: store.seconds(for: job.id, on: store.now),
                       selected: selected)
        case .create(let text):
            actionRow(icon: "plus.circle.fill", color: .green, title: "Create “\(text)” and start", selected: selected)
        case .stop:
            actionRow(icon: "stop.circle.fill", color: .red, title: "Stop timer", selected: selected)
        }
    }

    private func actionRow(icon: String, color: Color, title: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(title)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.25) : .clear))
        .contentShape(Rectangle())
    }

    private func choose(_ rows: [Row]) {
        guard rows.indices.contains(selection) else { return }
        switch rows[selection] {
        case .job(let job): store.start(job)
        case .create(let text): store.start(store.addJob(fromText: text))
        case .stop: store.stop()
        }
        onClose()
    }
}
