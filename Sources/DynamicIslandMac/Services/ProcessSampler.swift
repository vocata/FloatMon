import AppKit
import Foundation

struct ProcessSampler {
    @MainActor
    func sample() async -> [AppProcess] {
        let candidates = NSWorkspace.shared.runningApplications
            .filter { app in
                !app.isTerminated &&
                app.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
                (app.localizedName != nil || app.bundleIdentifier != nil)
            }
        let regularApps = candidates.filter { $0.activationPolicy == .regular }
        let apps = regularApps.isEmpty
            ? candidates.filter { $0.activationPolicy != .prohibited }
            : regularApps
        let snapshots = apps.map(AppSnapshot.init)
        let pids = snapshots.map(\.pid)
        let metricsByPID = await Task.detached(priority: .utility) {
            metrics(for: pids)
        }.value

        return snapshots.map { app in
            let metrics = metricsByPID[app.pid] ?? .empty
            return AppProcess(
                id: app.pid,
                name: app.name,
                bundleIdentifier: app.bundleIdentifier,
                bundleURL: app.bundleURL,
                icon: app.icon,
                cpuPercent: metrics.cpu,
                memoryBytes: metrics.rssBytes,
                isActive: app.isActive
            )
        }
        .sorted {
            if $0.isActive != $1.isActive {
                return $0.isActive
            }
            if $0.cpuPercent != $1.cpuPercent {
                return $0.cpuPercent > $1.cpuPercent
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

private struct AppSnapshot {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    let icon: NSImage?
    let isActive: Bool

    init(app: NSRunningApplication) {
        pid = app.processIdentifier
        name = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        bundleIdentifier = app.bundleIdentifier
        bundleURL = app.bundleURL
        icon = app.icon
        isActive = app.isActive
    }
}

private struct ProcessMetrics: Sendable {
    static let empty = ProcessMetrics(cpu: 0, rssBytes: 0)

    let cpu: Double
    let rssBytes: Int64
}

private func metrics(for pids: [pid_t]) -> [pid_t: ProcessMetrics] {
    guard !pids.isEmpty else { return [:] }

    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "pid=,%cpu=,rss="]
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return [:]
    }

    let wantedPIDs = Set(pids)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return [:] }

    var result: [pid_t: ProcessMetrics] = [:]
    for line in output.split(separator: "\n") {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard
            fields.count >= 3,
            let pid = pid_t(String(fields[0])),
            wantedPIDs.contains(pid)
        else {
            continue
        }

        let cpu = Double(fields[1]) ?? 0
        let rssKilobytes = Int64(fields[2]) ?? 0
        result[pid] = ProcessMetrics(cpu: cpu, rssBytes: rssKilobytes * 1024)
    }

    return result
}
