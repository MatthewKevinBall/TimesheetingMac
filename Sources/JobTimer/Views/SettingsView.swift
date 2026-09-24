import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage("rounding") private var rounding = RoundingMode.nearest.rawValue
    @AppStorage("idleMinutes") private var idleMinutes = 5
    @AppStorage("nudgeMinutes") private var nudgeMinutes = 15
    @AppStorage("longRunHours") private var longRunHours = 2
    @AppStorage("endOfDayReminder") private var endOfDayReminder = true
    @AppStorage("timesheetReminderMinutes") private var reminderMinutes = 16 * 60
    @AppStorage("workStartHour") private var workStartHour = 8
    @AppStorage("workEndHour") private var workEndHour = 17
    @AppStorage("weekdaysOnly") private var weekdaysOnly = true
    @AppStorage("showFloating") private var showFloating = true
    @AppStorage("showInDock") private var showInDock = false

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Timesheet") {
                Picker("Round hours to 15-minute blocks", selection: $rounding) {
                    ForEach(RoundingMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Text("Rounding is applied to each job's daily total.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reminders") {
                Stepper(value: $idleMinutes, in: 0...60) {
                    Text(idleMinutes == 0 ? "Away detection: off" : "Ask about time away after \(idleMinutes) min idle")
                }
                Stepper(value: $nudgeMinutes, in: 0...120, step: 5) {
                    Text(nudgeMinutes == 0 ? "“No timer running” reminder: off" : "Remind me after \(nudgeMinutes) min with no timer running")
                }
                Stepper(value: $longRunHours, in: 0...8) {
                    Text(longRunHours == 0 ? "“Still working on…?” reminder: off" : "Ask “still working on…?” every \(longRunHours)h")
                }
                Toggle("Remind me to update my timesheet (Mon–Fri)", isOn: $endOfDayReminder)
                if endOfDayReminder {
                    DatePicker("Reminder time", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
                Picker("Work day starts", selection: $workStartHour) {
                    ForEach(4..<13, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
                Picker("Work day ends", selection: $workEndHour) {
                    ForEach(13..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
                Toggle("Weekdays only", isOn: $weekdaysOnly)
            }

            Section("Appearance") {
                Toggle("Show floating timer", isOn: $showFloating)
                Toggle("Show in Dock", isOn: $showInDock)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Keyboard") {
                LabeledContent("Quick switcher", value: "⌥⌘T")
                LabeledContent("Copy timesheet summary", value: "⇧⌘C")
            }

            Section("Data") {
                LabeledContent("Stored in") {
                    Text(Store.shared.dataDirectory.path)
                        .textSelection(.enabled)
                        .font(.caption)
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.open(Store.shared.dataDirectory)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                reminderMinutes = (c.hour ?? 16) * 60 + (c.minute ?? 0)
                // Allow it to fire again today at the new time.
                UserDefaults.standard.removeObject(forKey: "endOfDayNotified")
            }
        )
    }

    private func hourLabel(_ h: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "h a"
        let date = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
        return f.string(from: date)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change login item: \(error.localizedDescription). Install the app in /Applications first."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
