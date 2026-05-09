import Foundation

struct AppResourceSample: Identifiable, Sendable {
    let time: Date
    let cpuPercent: Double
    let memoryBytes: Int64

    var id: Date { time }
}

