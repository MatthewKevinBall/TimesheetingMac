import SwiftUI

/// Small always-on-top pill showing the current job.
struct FloatingTimerView: View {
    static let width: CGFloat = 300
    static let height: CGFloat = 40

    private var store = Store.shared

    var body: some View {
        let entry = store.running
        let job = entry.flatMap { store.job(for: $0.jobID) }
        let accent = job?.color ?? .orange

        HStack(spacing: 8) {
            ColorDot(color: accent, size: 10)

            Group {
                if let job {
                    Text(job.displayName)
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Text("Not tracking")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .contentShape(Rectangle())
            .onTapGesture { AppController.shared.showQuickSwitcher() }
            .help("Switch job (⌥⌘T)")

            Spacer(minLength: 4)

            if let entry {
                Text(Fmt.hms(entry.duration(now: store.now)))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                iconButton("stop.fill", help: "Stop timer") { store.stop() }
            } else {
                iconButton("play.fill", help: "Start a job (⌥⌘T)") { AppController.shared.showQuickSwitcher() }
            }

            Menu {
                Button("Switch Job…") { AppController.shared.showQuickSwitcher() }
                Button("Open Timesheet") { AppController.shared.showMainWindow(tab: .timesheet) }
                Button("Open Spacecamp") { NSWorkspace.shared.open(URL(string: "https://spacecamp2.satellite.co.nz/")!) }
                Divider()
                Button("Hide Floating Timer") { UserDefaults.standard.set(false, forKey: "showFloating") }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(width: Self.width, height: Self.height)
        .background(DragHandle { AppController.shared.showQuickSwitcher() })
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(accent.opacity(0.6), lineWidth: 1.5))
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
