import Foundation

enum AppFormatters {
    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func cpu(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f%%", value) : String(format: "%.0f%%", value)
    }

    static func memory(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    static func integer(_ value: Int) -> String {
        integerFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func compactInteger(_ value: Int) -> String {
        switch value {
        case 1_000_000...:
            return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", Double(value) / 1_000)
        default:
            return integer(value)
        }
    }
}
