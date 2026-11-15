import Foundation
import Darwin

/// Reads CPU load with `host_processor_info` and the system load average.
final class CPUReader {
    private var previousTicks: [UInt32] = []

    func sample() -> CPUSample {
        var sample = CPUSample()

        var loads = [Double](repeating: 0, count: 3)
        var load1 = 0.0
        var load5 = 0.0
        var load15 = 0.0
        loads.withUnsafeMutableBufferPointer { pointer in
            if getloadavg(pointer.baseAddress, 3) >= 0 {
                load1 = pointer[0]
                load5 = pointer[1]
                load15 = pointer[2]
            }
        }
        sample.load1 = load1
        sample.load5 = load5
        sample.load15 = load15

        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )

        guard result == KERN_SUCCESS, let info else {
            return sample
        }

        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
        }

        let stateCount = Int(CPU_STATE_MAX)
        let coreCount = Int(cpuCount)
        var current = [UInt32]()
        current.reserveCapacity(coreCount * stateCount)
        for index in 0..<(coreCount * stateCount) {
            current.append(UInt32(bitPattern: info[index]))
        }

        let hasPrevious = previousTicks.count == current.count
        var perCore = [Double]()
        perCore.reserveCapacity(coreCount)

        var userDeltaTotal = 0.0
        var systemDeltaTotal = 0.0
        var idleDeltaTotal = 0.0
        var niceDeltaTotal = 0.0

        for core in 0..<coreCount {
            let base = core * stateCount
            let userIndex = base + Int(CPU_STATE_USER)
            let systemIndex = base + Int(CPU_STATE_SYSTEM)
            let idleIndex = base + Int(CPU_STATE_IDLE)
            let niceIndex = base + Int(CPU_STATE_NICE)

            let user = delta(previousTicks, current, userIndex, enabled: hasPrevious)
            let system = delta(previousTicks, current, systemIndex, enabled: hasPrevious)
            let idle = delta(previousTicks, current, idleIndex, enabled: hasPrevious)
            let nice = delta(previousTicks, current, niceIndex, enabled: hasPrevious)

            userDeltaTotal += user
            systemDeltaTotal += system
            idleDeltaTotal += idle
            niceDeltaTotal += nice

            let total = user + system + idle + nice
            perCore.append(total > 0 ? min(1, (user + system + nice) / total) : 0)
        }

        previousTicks = current
        sample.perCore = perCore

        let totalDelta = userDeltaTotal + systemDeltaTotal + idleDeltaTotal + niceDeltaTotal
        if totalDelta > 0 {
            sample.user = userDeltaTotal / totalDelta
            sample.system = systemDeltaTotal / totalDelta
            sample.idle = idleDeltaTotal / totalDelta
            sample.usage = min(1, (userDeltaTotal + systemDeltaTotal + niceDeltaTotal) / totalDelta)
        }

        return sample
    }

    private func delta(_ old: [UInt32], _ new: [UInt32], _ index: Int, enabled: Bool) -> Double {
        guard enabled, index < old.count, index < new.count else { return 0 }
        return Double(new[index] &- old[index])
    }
}
