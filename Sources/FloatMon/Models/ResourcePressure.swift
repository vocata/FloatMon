import Foundation

enum ResourcePressure {
    private enum Threshold {
        static let mediumPercent = 20.0
        static let highPercent = 60.0
    }

    case none
    case low
    case medium
    case high

    init(app: AppProcess, sortMode: ProcessSortMode) {
        switch sortMode {
        case .cpu:
            self = Self.cpu(app.cpuPercent)
        case .memory:
            self = Self.memory(app.memoryBytes)
        }
    }

    private static func cpu(_ value: Double) -> ResourcePressure {
        if value >= Threshold.highPercent { return .high }
        if value >= Threshold.mediumPercent { return .medium }
        return .low
    }

    private static func memory(_ bytes: Int64) -> ResourcePressure {
        let percent = Double(bytes) / Double(ProcessInfo.processInfo.physicalMemory) * 100
        if percent >= Threshold.highPercent { return .high }
        if percent >= Threshold.mediumPercent { return .medium }
        return .low
    }
}
