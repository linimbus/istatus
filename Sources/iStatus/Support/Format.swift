import Foundation

/// Small, allocation-light formatting helpers shared by the menu bar and the dashboard.
enum Fmt {
    /// 0.0 ... 1.0 -> "42%"
    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func percentValue(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }

    /// "0 B", "9.4 GB", "805 GB"
    static func bytes(_ value: Double, decimals: Bool = true) -> String {
        let value = max(0, value)
        if value < 1024 { return "\(Int(value)) B" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var v = value / 1024
        var idx = 0
        while v >= 1024 && idx < units.count - 1 {
            v /= 1024
            idx += 1
        }
        if decimals && v < 100 {
            return String(format: "%.1f %@", v, units[idx])
        }
        return String(format: "%.0f %@", v, units[idx])
    }

    /// "1.2 MB/s", "0 B/s"
    static func rate(_ bytesPerSecond: Double) -> String {
        bytes(max(0, bytesPerSecond)) + "/s"
    }

    /// Compact network rate with a maximum width of four characters.
    /// Examples: "0B", "999B", "1.2K", "99K", "999M", "1.0G".
    static func compactRate(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        if value < 1000 { return "\(Int(value))B" }
        let units = ["K", "M", "G", "T"]
        var v = value / 1024
        var idx = 0
        while v >= 999.5 && idx < units.count - 1 {
            v /= 1024
            idx += 1
        }
        if v < 10 { return String(format: "%.1f%@", v, units[idx]) }
        if v < 100 { return String(format: "%.0f%@", v, units[idx]) }
        return String(format: "%.0f%@", min(v, 999), units[idx])
    }

    /// Fixed-width percentage for the menu bar: "  5%", " 42%", "100%".
    static func fixedPercent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "   —" }
        return String(format: "%3d%%", Int((value * 100).rounded()))
    }

    /// Fixed-width fan speed for the menu bar: " 999", "1000".
    static func fixedRPM(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "   —" }
        return String(format: "%4d", Int(value.rounded()))
    }

    /// Fixed-width temperature for the menu bar: " 47°", "100°".
    static func fixedTemperature(_ celsius: Double?, unit: TemperatureUnit) -> String {
        guard let celsius, celsius.isFinite else { return "   —" }
        let value = unit == .celsius ? celsius : celsius * 9 / 5 + 32
        return String(format: "%3d°", Int(value.rounded()))
    }

    /// Pads a compact rate to four characters so menu bar items never resize.
    static func fixedCompactRate(_ bytesPerSecond: Double) -> String {
        let text = compactRate(bytesPerSecond)
        let padding = max(0, 4 - text.count)
        return String(repeating: " ", count: padding) + text
    }

    /// Fixed-width bidirectional network status: "↓1.2M ↑340K".
    static func networkStatus(down: Double, up: Double) -> String {
        "↓\(fixedCompactRate(down)) ↑\(fixedCompactRate(up))"
    }

    static func temperature(_ celsius: Double, unit: TemperatureUnit, includeUnit: Bool = true) -> String {
        let value = unit == .celsius ? celsius : celsius * 9 / 5 + 32
        let rounded = Int(value.rounded())
        guard includeUnit else { return "\(rounded)°" }
        return "\(rounded)°\(unit == .celsius ? "C" : "F")"
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)天 \(hours)小时 \(minutes)分" }
        if hours > 0 { return "\(hours)小时 \(minutes)分" }
        if minutes > 0 { return "\(minutes)分 \(total % 60)秒" }
        return "\(total)秒"
    }

    static func loadAverage(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
