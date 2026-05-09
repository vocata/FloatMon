import Foundation
import Observation

@Observable
@MainActor
final class ProcessStore {
    var apps: [AppProcess] = []
    var lastUpdated = Date()

    private let sampler: ProcessSampler
    private let historyDuration: TimeInterval
    private var isRefreshing = false
    private var timer: Timer?
    private var historyByPID: [pid_t: [AppResourceSample]] = [:]

    init(
        sampler: ProcessSampler = ProcessSampler(),
        refreshInterval: TimeInterval = 3,
        historyDuration: TimeInterval = 300
    ) {
        self.sampler = sampler
        self.historyDuration = historyDuration

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        Task { [sampler] in
            let apps = await sampler.sample()
            let now = Date()
            self.apps = self.enrich(apps, now: now)
            self.lastUpdated = now
            self.isRefreshing = false
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func enrich(_ apps: [AppProcess], now: Date) -> [AppProcess] {
        let activePIDs = Set(apps.map(\.id))
        let cutoff = now.addingTimeInterval(-historyDuration)

        for app in apps {
            var samples = historyByPID[app.id, default: []]
            samples.append(
                AppResourceSample(
                    time: now,
                    cpuPercent: app.cpuPercent,
                    memoryBytes: app.memoryBytes
                )
            )
            historyByPID[app.id] = samples.filter { $0.time >= cutoff }
        }

        historyByPID = historyByPID.filter { activePIDs.contains($0.key) }

        return apps.map { app in
            var app = app
            let history = historyByPID[app.id] ?? []
            app.historySamples = history
            return app
        }
    }
}
