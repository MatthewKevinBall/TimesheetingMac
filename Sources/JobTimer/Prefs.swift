import Foundation

/// UserDefaults-backed settings. Views use @AppStorage with the same keys.
enum Prefs {
    private static var d: UserDefaults { .standard }

    static func registerDefaults() {
        d.register(defaults: [
            "idleMinutes": 5,
            "nudgeMinutes": 15,
            "longRunHours": 2,
            "workStartHour": 8,
            "workEndHour": 17,
            "weekdaysOnly": true,
            "endOfDayReminder": true,
            "timesheetReminderMinutes": 16 * 60, // 4:00 pm
            "rounding": RoundingMode.nearest.rawValue,
            "showFloating": true,
            "showInDock": false,
        ])
    }

    static var idleMinutes: Int { d.integer(forKey: "idleMinutes") }
    static var nudgeMinutes: Int { d.integer(forKey: "nudgeMinutes") }
    static var longRunHours: Int { d.integer(forKey: "longRunHours") }
    static var workStartHour: Int { d.integer(forKey: "workStartHour") }
    static var workEndHour: Int { d.integer(forKey: "workEndHour") }
    static var weekdaysOnly: Bool { d.bool(forKey: "weekdaysOnly") }
    static var endOfDayReminder: Bool { d.bool(forKey: "endOfDayReminder") }
    /// Time of day for the "update your timesheet" reminder, in minutes after midnight.
    static var timesheetReminderMinutes: Int { d.integer(forKey: "timesheetReminderMinutes") }
    static var showFloating: Bool { d.bool(forKey: "showFloating") }
    static var showInDock: Bool { d.bool(forKey: "showInDock") }
    static var rounding: RoundingMode { RoundingMode(rawValue: d.string(forKey: "rounding") ?? "") ?? .nearest }

    static func isWorkday(_ date: Date) -> Bool {
        !weekdaysOnly || !Calendar.current.isDateInWeekend(date)
    }

    static func isWorkTime(_ date: Date) -> Bool {
        let h = Calendar.current.component(.hour, from: date)
        return isWorkday(date) && h >= workStartHour && h < workEndHour
    }
}
