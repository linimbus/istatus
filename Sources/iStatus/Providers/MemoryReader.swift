import Foundation
import Darwin

/// Reads physical memory, compressed/wired/cached breakdown and swap usage.
final class MemoryReader {
    func sample() -> MemorySample {
        var sample = MemorySample()
        sample.total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize > 0 ? pageSize : vm_page_size)

        if result == KERN_SUCCESS {
            let internalPages = UInt64(stats.internal_page_count)
            let purgeablePages = UInt64(stats.purgeable_count)
            let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0

            sample.app = appPages * page
            sample.wired = UInt64(stats.wire_count) * page
            sample.compressed = UInt64(stats.compressor_page_count) * page
            sample.cached = (UInt64(stats.external_page_count) + purgeablePages) * page

            let used = sample.app + sample.wired + sample.compressed
            sample.used = min(sample.total, used)
            sample.free = sample.total > sample.used + sample.cached
                ? sample.total - sample.used - sample.cached
                : 0
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.stride
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            sample.swapTotal = swap.xsu_total
            sample.swapUsed = swap.xsu_used
        }

        var pressure: Int32 = 1
        var pressureSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0 {
            sample.pressureLevel = Int(pressure)
        } else {
            sample.pressureLevel = 1
        }

        return sample
    }
}
