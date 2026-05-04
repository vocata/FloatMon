import Foundation

enum ResourcePressure {
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
        if value >= 60 { return .high }
        if value >= 20 { return .medium }
        return .low
    }

    private static func memory(_ bytes: Int64) -> ResourcePressure {
        let percent = Double(bytes) / Double(ProcessInfo.processInfo.physicalMemory) * 100
        if percent >= 60 { return .high }
        if percent >= 20 { return .medium }
        return .low
    }
}
