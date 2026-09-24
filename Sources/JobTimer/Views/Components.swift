import AppKit
import SwiftUI

/// Background view that drags the window it's in.
struct DragHandle: NSViewRepresentable {
    var onDoubleClick: (() -> Void)? = nil

    final class HandleView: NSView {
        var onDoubleClick: (() -> Void)?

        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2, let onDoubleClick {
                onDoubleClick()
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: HandleView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }
}

struct ColorDot: View {
    let color: Color
    var size: CGFloat = 9

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// A job in a pickable list (menu bar popover, quick switcher).
struct JobPickRow: View {
    let job: Job
    let isRunning: Bool
    let today: TimeInterval
    var selected = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            ColorDot(color: job.color)
            Text(job.displayName).lineLimit(1)
            if job.pinned {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
            }
            Spacer()
            if today > 0 {
                Text(Fmt.hm(today)).monospacedDigit().foregroundStyle(.secondary)
            }
            if isRunning {
                Image(systemName: "timer").foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(background))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if selected { return Color.accentColor.opacity(0.25) }
        if hovering { return Color.primary.opacity(0.08) }
        if isRunning { return job.color.opacity(0.12) }
        return .clear
    }
}

/// The current timer with note field and quick backdating.
struct CurrentTimerCard: View {
    private var store = Store.shared

    var body: some View {
        if let entry = store.running, let job = store.job(for: entry.jobID) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ColorDot(color: job.color, size: 10)
                    Text(job.displayName).font(.headline).lineLimit(1)
                    Spacer()
                    Text(Fmt.hms(entry.duration(now: store.now)))
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                }
                HStack(spacing: 6) {
                    TextField("Note for Spacecamp (optional)", text: noteBinding)
                        .textFieldStyle(.roundedBorder)
                    Button { store.stop() } label: {
                        Image(systemName: "stop.fill")
                    }
                    .help("Stop timer")
                }
                HStack(spacing: 4) {
                    Text("Started \(Fmt.time.string(from: entry.start))")
                    Menu("Started earlier") {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { m in
                            Button("\(m) min earlier") { store.backdateRunning(minutes: m) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                Text("Not tracking").font(.headline)
                Spacer()
                Text("⌥⌘T to start").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var noteBinding: Binding<String> {
        Binding(get: { store.running?.note ?? "" }, set: { store.setRunningNote($0) })
    }
}
