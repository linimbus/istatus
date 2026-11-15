import Foundation
import Darwin
import SystemConfiguration

/// Samples per-interface 64-bit traffic counters and selects the primary network service.
final class NetworkReader {
    private struct Counters {
        var received: UInt64
        var sent: UInt64
    }

    private var previous: [String: Counters] = [:]
    private var previousTime: TimeInterval = 0
    private var dynamicStore: SCDynamicStore?

    init() {
        dynamicStore = SCDynamicStoreCreate(nil, "iStatus" as CFString, nil, nil)
    }

    func sample() -> NetworkSample {
        var sample = NetworkSample()
        let counters = readCounters()
        let addresses = readIPv4Addresses()
        let primary = primaryInterface(from: counters)

        guard let current = counters[primary] else {
            sample.interfaceName = primary
            previous = counters
            previousTime = Date.timeIntervalSinceReferenceDate
            return sample
        }

        let now = Date.timeIntervalSinceReferenceDate
        if previousTime > 0, let old = previous[primary] {
            let elapsed = now - previousTime
            if elapsed > 0 {
                if current.received >= old.received {
                    sample.downPerSecond = Double(current.received - old.received) / elapsed
                }
                if current.sent >= old.sent {
                    sample.upPerSecond = Double(current.sent - old.sent) / elapsed
                }
            }
        }

        sample.interfaceName = primary
        sample.ipAddress = addresses[primary]
        sample.receivedTotal = current.received
        sample.sentTotal = current.sent

        previous = counters
        previousTime = now
        return sample
    }

    // MARK: - Interface counters

    private func readCounters() -> [String: Counters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        let mibCount = u_int(mib.count)
        var length = 0
        guard mib.withUnsafeMutableBufferPointer({
            sysctl($0.baseAddress, mibCount, nil, &length, nil, 0)
        }) == 0, length > 0 else {
            return [:]
        }

        var buffer = [UInt8](repeating: 0, count: length)
        let readResult = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return mib.withUnsafeMutableBufferPointer { mibPointer in
                sysctl(mibPointer.baseAddress, mibCount, base, &length, nil, 0)
            }
        }
        guard readResult == 0 else { return [:] }

        var result: [String: Counters] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }

                if Int32(header.ifm_type) == RTM_IFINFO2,
                   messageLength >= MemoryLayout<if_msghdr2>.size {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(info.ifm_index), &name) != nil {
                        let interface = String(cString: name)
                        result[interface] = Counters(
                            received: info.ifm_data.ifi_ibytes,
                            sent: info.ifm_data.ifi_obytes
                        )
                    }
                }

                offset += messageLength
            }
        }
        return result
    }

    private func primaryInterface(from counters: [String: Counters]) -> String {
        if let store = dynamicStore,
           let value = SCDynamicStoreCopyValue(
               store,
               "State:/Network/Global/IPv4" as CFString
           ) as? [String: Any],
           let primary = value["PrimaryInterface"] as? String,
           counters[primary] != nil {
            return primary
        }

        if counters["en0"] != nil { return "en0" }

        return counters
            .filter { isPhysical($0.key) }
            .max { $0.value.received + $0.value.sent < $1.value.received + $1.value.sent }?
            .key ?? "—"
    }

    private func isPhysical(_ name: String) -> Bool {
        let excludedPrefixes = ["lo", "utun", "awdl", "llw", "bridge", "ap", "gif", "stf", "anpi", "nan"]
        if excludedPrefixes.contains(where: { name.hasPrefix($0) }) { return false }
        return name.hasPrefix("en") || name.hasPrefix("pdp_ip") || name.hasPrefix("eth")
    }

    // MARK: - IPv4 addresses

    private func readIPv4Addresses() -> [String: String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }

        var result: [String: String] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            if let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let status = getnameinfo(
                    address,
                    socklen_t(address.pointee.sa_len),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if status == 0 {
                    result[String(cString: interface.ifa_name)] = String(cString: host)
                }
            }
            pointer = interface.ifa_next
        }
        return result
    }
}
