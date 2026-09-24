import Foundation

enum Fmt {
    /// 1:05
    static func hm(_ s: TimeInterval) -> String {
        let m = Int(max(0, s)) / 60
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// 1:05:32
    static func hms(_ s: TimeInterval) -> String {
        let t = Int(max(0, s))
        return String(format: "%d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60)
    }

    /// 1.25
    static func hours(_ s: TimeInterval) -> String {
        String(format: "%.2f", s / 3600)
    }

    /// "1h 5m" / "23 min"
    static func duration(_ s: TimeInterval) -> String {
        let m = Int(max(0, s)) / 60
        return m < 60 ? "\(m) min" : "\(m / 60)h \(m % 60)m"
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static let longDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM yyyy"
        return f
    }()
}

enum RoundingMode: String, CaseIterable, Identifiable {
    case nearest, nearestMin, up

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nearest: return "Nearest 15 min"
        case .nearestMin: return "Nearest 15 min (minimum 15)"
        case .up: return "Always round up"
        }
    }
}

enum Billing {
    static let block: TimeInterval = 15 * 60

    static func round(_ s: TimeInterval, mode: RoundingMode = Prefs.rounding) -> TimeInterval {
        guard s > 0 else { return 0 }
        let blocks = s / block
        switch mode {
        case .nearest: return blocks.rounded() * block
        case .nearestMin: return max(1, blocks.rounded()) * block
        case .up: return (blocks - 1e-6).rounded(.up) * block
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
