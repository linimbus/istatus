import Foundation
import IOKit

enum SystemInfo {
    static let modelID = Sysctl.string("hw.model") ?? "Mac"
    static let chip = Sysctl.string("machdep.cpu.brand_string") ?? "Apple Silicon"
    static let coreCount = ProcessInfo.processInfo.processorCount
    static let performanceCores = Sysctl.int("hw.perflevel0.physicalcpu") ?? 0
    static let efficiencyCores = Sysctl.int("hw.perflevel1.physicalcpu") ?? 0
    static let totalMemory = ProcessInfo.processInfo.physicalMemory
    static let hostname = ProcessInfo.processInfo.hostName
        .replacingOccurrences(of: ".local", with: "")
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.2"

    static let modelName: String = {
        // The friendly name is exposed by the IODeviceTree `product` node.
        for path in ["IODeviceTree:/device-tree/product", "IODeviceTree:/product"] {
            let product = IORegistryEntryFromPath(kIOMainPortDefault, path)
            guard product != 0 else { continue }
            defer { IOObjectRelease(product) }
            if let name = ioregString(
                IORegistryEntryCreateCFProperty(
                    product,
                    "product-name" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue()
            ) {
                return name
            }
        }

        // Fallback for other hardware: search the device-tree plane recursively.
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return modelID }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            root,
            kIODeviceTreePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else {
            return modelID
        }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let name = ioregString(
                IORegistryEntryCreateCFProperty(
                    entry,
                    "product-name" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue()
            ) {
                IOObjectRelease(entry)
                return name
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return modelID
    }()

    static let osVersion: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.patchVersion > 0 {
            return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        }
        return "macOS \(version.majorVersion).\(version.minorVersion)"
    }()

    private static func ioregString(_ object: CFTypeRef?) -> String? {
        guard let object else { return nil }
        if let value = object as? String, !value.isEmpty {
            return value
        }
        if let data = object as? Data {
            let value = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    static var coreDescription: String {
        if performanceCores > 0 || efficiencyCores > 0 {
            return "\(coreCount) 核 · \(performanceCores)P + \(efficiencyCores)E"
        }
        return "\(coreCount) 核"
    }
}
