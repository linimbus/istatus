import Foundation
import IOKit

/// Reads volume capacity and cumulative SSD I/O counters.
final class DiskReader {
    private var service: io_service_t = 0
    private var previousRead: UInt64 = 0
    private var previousWrite: UInt64 = 0
    private var previousTime: TimeInterval = 0

    private var cachedTotal: Int64 = 0
    private var cachedFree: Int64 = 0
    private var cachedVolumeName = "Macintosh HD"
    private var capacityUpdatedAt: TimeInterval = 0

    init() {
        scan()
        updateCapacity(force: true)
    }

    deinit {
        if service != 0 {
            IOObjectRelease(service)
        }
    }

    func sample() -> DiskSample {
        var sample = DiskSample()

        updateCapacity(force: false)
        sample.total = cachedTotal
        sample.free = cachedFree
        sample.volumeName = cachedVolumeName
        sample.used = max(0, cachedTotal - cachedFree)
        if cachedTotal > 0 {
            sample.usage = min(1, Double(sample.used) / Double(cachedTotal))
        }

        if service == 0 {
            scan()
        }
        guard service != 0, let statistics = statistics() else {
            return sample
        }

        let read = (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
        let write = (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        let now = Date.timeIntervalSinceReferenceDate

        if previousTime > 0 {
            let elapsed = now - previousTime
            if elapsed > 0 {
                if read >= previousRead {
                    sample.readPerSecond = Double(read - previousRead) / elapsed
                }
                if write >= previousWrite {
                    sample.writePerSecond = Double(write - previousWrite) / elapsed
                }
            }
        }

        previousRead = read
        previousWrite = write
        previousTime = now
        return sample
    }

    // MARK: - Private

    private func statistics() -> [String: Any]? {
        guard service != 0 else { return nil }
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "Statistics" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [String: Any] else {
            IOObjectRelease(service)
            service = 0
            return nil
        }
        return value
    }

    private func scan() {
        if service != 0 {
            IOObjectRelease(service)
            service = 0
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }

        // Prefer the drive with the highest cumulative I/O. This avoids selecting
        // a mounted disk image when several IOBlockStorageDriver instances exist.
        var bestService: io_service_t = 0
        var bestBytes: UInt64 = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let statistics = IORegistryEntryCreateCFProperty(
                entry,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] {
                let read = (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                let write = (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
                let total = read &+ write
                if total >= bestBytes {
                    if bestService != 0 {
                        IOObjectRelease(bestService)
                    }
                    bestService = entry
                    bestBytes = total
                } else {
                    IOObjectRelease(entry)
                }
            } else {
                IOObjectRelease(entry)
            }
            entry = IOIteratorNext(iterator)
        }
        service = bestService
    }

    private func updateCapacity(force: Bool) {
        let now = Date.timeIntervalSinceReferenceDate
        if !force, now - capacityUpdatedAt < 10 { return }
        capacityUpdatedAt = now

        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return }

        if let total = values.volumeTotalCapacity {
            cachedTotal = Int64(total)
        }
        if let free = values.volumeAvailableCapacityForImportantUsage {
            cachedFree = free
        } else if let free = values.volumeAvailableCapacity {
            cachedFree = Int64(free)
        }
        if let name = values.volumeName, !name.isEmpty {
            cachedVolumeName = name
        }
    }
}
