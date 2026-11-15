import Foundation
import IOKit

/// Minimal AppleSMC client. Only public IOKit calls are used; no privileged helper is required.
final class SMCReader {
    private struct Vers {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    private struct KeyData {
        var key: UInt32 = 0
        var vers = Vers()
        var pLimitData = LimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private enum Command {
        static let kernelIndex: UInt32 = 2
        static let readBytes: UInt8 = 5
        static let readKeyInfo: UInt8 = 9
    }

    private var connection: io_connect_t = 0
    private var keyInfoCache: [UInt32: KeyInfo] = [:]
    private var missingKeys: Set<UInt32> = []

    private(set) var isAvailable = false

    init() {
        open()
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    /// Reads a numeric SMC key. Returns nil when the key does not exist or uses an unknown encoding.
    func read(_ key: String) -> (type: String, value: Double)? {
        guard let raw = readRaw(key), let value = decode(type: raw.type, bytes: raw.bytes) else {
            return nil
        }
        return (raw.type, value)
    }

    func readDouble(_ key: String) -> Double? {
        read(key)?.value
    }

    func hasKey(_ key: String) -> Bool {
        guard connection != 0 else { return false }
        let code = fourCC(key)
        if missingKeys.contains(code) { return false }
        if keyInfoCache[code] != nil { return true }

        var input = KeyData()
        input.key = code
        input.data8 = Command.readKeyInfo
        var output = KeyData()
        guard call(&input, &output) == KERN_SUCCESS, output.result == 0, output.keyInfo.dataSize > 0 else {
            missingKeys.insert(code)
            return false
        }
        keyInfoCache[code] = output.keyInfo
        return true
    }

    func fanCount() -> Int {
        guard let value = readDouble("FNum"), value.isFinite else { return 0 }
        return min(max(Int(value), 0), 8)
    }

    func fans() -> [FanReading] {
        let count = fanCount()
        guard count > 0 else { return [] }

        var result: [FanReading] = []
        for index in 0..<count {
            let current = readDouble("F\(index)Ac") ?? 0
            let minimum = readDouble("F\(index)Mn") ?? 0
            let maximum = readDouble("F\(index)Mx") ?? 0
            guard current.isFinite, minimum.isFinite, maximum.isFinite else { continue }
            result.append(FanReading(index: index, current: current, minimum: minimum, maximum: maximum))
        }
        return result
    }

    // MARK: - Private

    private func open() {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleSMC")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }

        let device = IOIteratorNext(iterator)
        guard device != 0 else { return }
        defer { IOObjectRelease(device) }

        let result = IOServiceOpen(device, mach_task_self_, 0, &connection)
        isAvailable = result == KERN_SUCCESS && connection != 0
    }

    private func readRaw(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard connection != 0 else { return nil }
        let code = fourCC(key)
        if missingKeys.contains(code) { return nil }

        let info: KeyInfo
        if let cached = keyInfoCache[code] {
            info = cached
        } else {
            var input = KeyData()
            input.key = code
            input.data8 = Command.readKeyInfo
            var output = KeyData()
            guard call(&input, &output) == KERN_SUCCESS, output.result == 0,
                  output.keyInfo.dataSize > 0, output.keyInfo.dataSize <= 32 else {
                missingKeys.insert(code)
                return nil
            }
            info = output.keyInfo
            keyInfoCache[code] = info
        }

        var input = KeyData()
        input.key = code
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Command.readBytes
        var output = KeyData()
        guard call(&input, &output) == KERN_SUCCESS, output.result == 0 else {
            keyInfoCache.removeValue(forKey: code)
            return nil
        }

        let size = Int(min(info.dataSize, 32))
        let bytes = withUnsafeBytes(of: output.bytes) { raw in
            Array(raw.prefix(size))
        }
        return (str4(info.dataType), bytes)
    }

    private func call(_ input: inout KeyData, _ output: inout KeyData) -> kern_return_t {
        var outputSize = MemoryLayout<KeyData>.stride
        return IOConnectCallStructMethod(
            connection,
            Command.kernelIndex,
            &input,
            MemoryLayout<KeyData>.stride,
            &output,
            &outputSize
        )
    }

    private func fourCC(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in string.utf8.prefix(4) {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    private func str4(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    private func decode(type: String, bytes: [UInt8]) -> Double? {
        func bigEndian16() -> UInt16? {
            guard bytes.count >= 2 else { return nil }
            return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        }

        func bigEndian32() -> UInt32? {
            guard bytes.count >= 4 else { return nil }
            return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        }

        switch type {
        case "flt ":
            // SMC float values are raw little-endian IEEE-754 bytes.
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))

        case "fpe2":
            guard let raw = bigEndian16() else { return nil }
            return Double(raw) / 4.0

        case "fp88":
            guard let raw = bigEndian16() else { return nil }
            return Double(raw) / 256.0

        case "ui8 ", "ui8":
            return bytes.first.map(Double.init)

        case "ui16":
            return bigEndian16().map(Double.init)

        case "ui32":
            return bigEndian32().map(Double.init)

        case "si8 ":
            return bytes.first.map { Double(Int8(bitPattern: $0)) }

        case "si16":
            return bigEndian16().map { Double(Int16(bitPattern: $0)) }

        case "sp78":
            return bigEndian16().map { Double(Int16(bitPattern: $0)) / 256.0 }

        case "sp4b":
            return bigEndian16().map { Double(Int16(bitPattern: $0)) / 16.0 }

        case "sp5a":
            return bigEndian16().map { Double(Int16(bitPattern: $0)) / 32.0 }

        case "sp69":
            return bigEndian16().map { Double(Int16(bitPattern: $0)) / 64.0 }

        case "sp87":
            return bigEndian16().map { Double(Int16(bitPattern: $0)) / 128.0 }

        default:
            return nil
        }
    }
}
