import Foundation
import Observation

@Observable
@MainActor
final class ProcessStore {
    var apps: [AppProcess] = []
    var lastUpdated = Date()

    private let sampler: ProcessSampler
    private var isRefreshing = false
    private var timer: Timer?

    init(sampler: ProcessSampler = ProcessSampler(), refreshInterval: TimeInterval = 3) {
        self.sampler = sampler

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
            self.apps = apps
            self.lastUpdated = Date()
            self.isRefreshing = false
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
