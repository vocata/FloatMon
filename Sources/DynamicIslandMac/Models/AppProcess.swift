import Foundation
import AppKit

struct AppProcess: Identifiable {
    let id: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let cpuPercent: Double
    let memoryBytes: Int64
    let isActive: Bool
}
