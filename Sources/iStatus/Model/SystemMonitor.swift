import Foundation
import Combine

/// Owns all readers and publishes one coherent snapshot per refresh tick.
final class SystemMonitor: NSObject, ObservableObject {
    @Published private(set) var metrics: Metrics = .empty
    @Published private(set) var history = SampleHistory()

    /// Called after each snapshot so the menu bar can update without SwiftUI overhead.
    var onSample: ((Metrics) -> Void)?

    private let cpuReader = CPUReader()
    private let memoryReader = MemoryReader()
    private let gpuReader = GPUReader()
    private let diskReader = DiskReader()
    private let networkReader = NetworkReader()
    private let thermalReader = ThermalReader()

    private var timer: Timer?
    private(set) var interval: TimeInterval = 1.0

    var gpuName: String { gpuReader.name }
    var gpuCoreCount: Int? { gpuReader.coreCount }

    func start(interval: TimeInterval) {
        self.interval = clampInterval(interval)
        restartTimer()
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setInterval(_ interval: TimeInterval) {
        let next = clampInterval(interval)
        guard next != self.interval else { return }
        self.interval = next
        if timer != nil {
            restartTimer()
        }
    }

    func refresh() {
        var snapshot = Metrics()
        snapshot.timestamp = Date()
        snapshot.uptime = ProcessInfo.processInfo.systemUptime
        snapshot.cpu = cpuReader.sample()
        snapshot.memory = memoryReader.sample()
        snapshot.gpu = gpuReader.sample()
        snapshot.disk = diskReader.sample()
        snapshot.network = networkReader.sample()
        snapshot.thermal = thermalReader.sample()

        metrics = snapshot
        history.push(snapshot)
        onSample?(snapshot)
    }

    private func restartTimer() {
        timer?.invalidate()
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = interval * 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func tick() {
        refresh()
    }

    private func clampInterval(_ value: TimeInterval) -> TimeInterval {
        min(max(value, 0.5), 10)
    }
}
