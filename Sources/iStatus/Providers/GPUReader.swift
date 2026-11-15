import Foundation
import IOKit

/// Reads GPU utilization and unified-memory usage from the IOAccelerator registry entry.
final class GPUReader {
    private var service: io_service_t = 0
    private(set) var name: String = "GPU"
    private(set) var coreCount: Int?

    init() {
        scan()
        if name.isEmpty { name = "GPU" }
    }

    deinit {
        if service != 0 {
            IOObjectRelease(service)
        }
    }

    func sample() -> GPUSample {
        if service == 0 {
            scan()
        }
        if service == 0 {
            return GPUSample(name: name, coreCount: coreCount, available: false)
        }

        guard let statistics = statistics() else {
            // The accelerator entry can be replaced after a GPU reset; retry once.
            scan()
            guard let retry = statistics() else {
                return GPUSample(name: name, coreCount: coreCount, available: false)
            }
            return makeSample(from: retry)
        }

        return makeSample(from: statistics)
    }

    // MARK: - Private

    private func scan() {
        if service != 0 {
            IOObjectRelease(service)
            service = 0
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if service == 0, IORegistryEntryCreateCFProperty(
                entry,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            ) != nil {
                service = entry
                if let model = IORegistryEntryCreateCFProperty(
                    entry,
                    "model" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? String {
                    name = model
                }
                if let cores = IORegistryEntryCreateCFProperty(
                    entry,
                    "gpu-core-count" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? NSNumber {
                    coreCount = cores.intValue
                }
            } else {
                IOObjectRelease(entry)
            }
            entry = IOIteratorNext(iterator)
        }
    }

    private func statistics() -> [String: Any]? {
        guard service != 0 else { return nil }
        return IORegistryEntryCreateCFProperty(
            service,
            "PerformanceStatistics" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any]
    }

    private func makeSample(from statistics: [String: Any]) -> GPUSample {
        let utilization = (statistics["Device Utilization %"] as? NSNumber)?.doubleValue
        let inUse = (statistics["In use system memory"] as? NSNumber)?.uint64Value
        let allocated = (statistics["Alloc system memory"] as? NSNumber)?.uint64Value

        return GPUSample(
            name: name,
            coreCount: coreCount,
            utilization: utilization.map { min(max($0 / 100.0, 0), 1) },
            memoryInUse: inUse,
            memoryAllocated: allocated,
            available: utilization != nil || inUse != nil
        )
    }
}
