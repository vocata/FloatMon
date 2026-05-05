import AppKit
import ApplicationServices
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
        let windowSnapshots = snapshots.map(WindowLookupSnapshot.init)
        let metricsTask = Task.detached(priority: .utility) {
            metrics(for: pids)
        }
        let windowsTask = Task.detached(priority: .utility) {
            windowInfoByPID(for: windowSnapshots)
        }
        let metricsByPID = await metricsTask.value
        let windowsByPID = await windowsTask.value

        return snapshots.map { app in
            let appMetrics = metricsByPID[app.pid] ?? .empty
            return AppProcess(
                id: app.pid,
                name: app.name,
                bundleIdentifier: app.bundleIdentifier,
                bundleURL: app.bundleURL,
                icon: app.icon,
                cpuPercent: appMetrics.cpu,
                memoryBytes: appMetrics.rssBytes,
                windows: windowsByPID[app.pid] ?? []
            )
        }
    }
}

private struct AppSnapshot {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    let icon: NSImage?

    init(app: NSRunningApplication) {
        pid = app.processIdentifier
        name = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        bundleIdentifier = app.bundleIdentifier
        bundleURL = app.bundleURL
        icon = app.icon
    }
}

private struct WindowLookupSnapshot: Sendable {
    let pid: pid_t
    let name: String

    init(app: AppSnapshot) {
        pid = app.pid
        name = app.name
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

private func windowInfoByPID(for apps: [WindowLookupSnapshot]) -> [pid_t: [AppWindowInfo]] {
    guard !apps.isEmpty else { return [:] }

    let appNameByPID = Dictionary(uniqueKeysWithValues: apps.map { (Int($0.pid), $0.name) })
    let wantedPIDs = Set(appNameByPID.keys)
    guard
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
    else {
        return [:]
    }

    var result: [pid_t: [AppWindowInfo]] = [:]
    var untitledCounts: [pid_t: Int] = [:]
    var windowOrderByPID: [pid_t: Int] = [:]
    let axTitlesByPID = accessibilityWindowTitlesByPID(for: apps)

    for window in windowList {
        guard
            let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
            wantedPIDs.contains(ownerPID),
            let windowID = window[kCGWindowNumber as String] as? Int,
            let boundsValue = window[kCGWindowBounds as String] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: boundsValue)
        else {
            continue
        }

        let pid = pid_t(ownerPID)
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        guard layer == 0 else { continue }

        let rawTitle = (window[kCGWindowName as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let order = windowOrderByPID[pid] ?? 0
        windowOrderByPID[pid] = order + 1
        let title: String
        if let rawTitle, !rawTitle.isEmpty {
            title = rawTitle
        } else if
            let axTitles = axTitlesByPID[pid],
            axTitles.indices.contains(order),
            !axTitles[order].isEmpty
        {
            title = axTitles[order]
        } else {
            let count = (untitledCounts[pid] ?? 0) + 1
            untitledCounts[pid] = count
            let appName = appNameByPID[ownerPID] ?? "App"
            title = "\(appName) Window \(count)"
        }

        result[pid, default: []].append(
            AppWindowInfo(
                id: windowID,
                title: title,
                frame: frame
            )
        )
    }

    return result.mapValues { windows in
        windows.sorted {
            if $0.title != $1.title {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.id < $1.id
        }
    }
}

private func accessibilityWindowTitlesByPID(for apps: [WindowLookupSnapshot]) -> [pid_t: [String]] {
    guard AXIsProcessTrusted() else {
        return [:]
    }

    var result: [pid_t: [String]] = [:]
    for app in apps {
        let appElement = AXUIElementCreateApplication(app.pid)
        var windowsValue: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        guard windowsResult == .success, let windows = windowsValue as? [AXUIElement] else {
            continue
        }

        let titles = windows.compactMap { window -> String? in
            var titleValue: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(
                window,
                kAXTitleAttribute as CFString,
                &titleValue
            )

            guard
                titleResult == .success,
                let title = titleValue as? String
            else {
                return nil
            }

            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedTitle.isEmpty ? nil : trimmedTitle
        }

        if !titles.isEmpty {
            result[app.pid] = titles
        }
    }

    return result
}
