import Foundation

/// Reads fan speeds and platform-appropriate temperature sensors from SMC.
final class ThermalReader {
    private struct Spec {
        let key: String
        let name: String
        let group: SensorGroup
    }

    private let smc: SMCReader?
    private var specs: [Spec] = []

    init() {
        let reader = SMCReader()
        smc = reader.isAvailable ? reader : nil
        guard let smc else { return }

        let chip = Sysctl.string("machdep.cpu.brand_string") ?? ""
        var candidates = Self.specs(for: chip)
        if !chip.hasPrefix("Apple") {
            candidates.append(contentsOf: Self.appleSiliconSSDSpecs)
        }

        var available = candidates.filter { smc.hasKey($0.key) }

        // Number GPU sensors consecutively so missing keys do not produce gaps.
        var gpuIndex = 0
        for index in available.indices where available[index].group == .gpu {
            gpuIndex += 1
            let item = available[index]
            available[index] = Spec(key: item.key, name: "GPU \(gpuIndex)", group: .gpu)
        }
        specs = available
    }

    func sample() -> ThermalSample {
        var sample = ThermalSample()
        guard let smc else { return sample }

        sample.fans = smc.fans()

        var readings: [TemperatureReading] = []
        readings.reserveCapacity(specs.count)
        for spec in specs {
            guard let value = smc.readDouble(spec.key),
                  value.isFinite, value > 0.5, value < 130 else { continue }
            readings.append(
                TemperatureReading(
                    key: spec.key,
                    name: spec.name,
                    group: spec.group,
                    celsius: value
                )
            )
        }

        let cpu = readings.filter { $0.group == .cpu }.map(\.celsius)
        let gpu = readings.filter { $0.group == .gpu }.map(\.celsius)
        let ssd = readings.filter { $0.group == .disk }.map(\.celsius)

        sample.sensors = readings
        sample.cpuTemp = cpu.max()
        sample.gpuTemp = gpu.max()
        sample.ssdTemp = ssd.max()
        if !cpu.isEmpty {
            sample.cpuAverage = cpu.reduce(0, +) / Double(cpu.count)
        }
        sample.hottest = readings.map(\.celsius).max()
        return sample
    }

    // MARK: - Sensor maps

    private static let appleSiliconSSDSpecs: [Spec] = [
        Spec(key: "TH0a", name: "SSD 1", group: .disk),
        Spec(key: "TH0b", name: "SSD 2", group: .disk),
        Spec(key: "TH0p", name: "SSD 3", group: .disk),
        Spec(key: "TH0x", name: "SSD 4", group: .disk)
    ]

    private static func specs(for chip: String) -> [Spec] {
        if chip.contains("Apple M6") {
            var list: [Spec] = []
            let superCores = ["Tp0j", "Tp0g", "Tp09", "Tp07"]
            for (index, key) in superCores.enumerated() {
                list.append(Spec(key: key, name: "CPU 超级核 \(index + 1)", group: .cpu))
            }
            list.append(contentsOf: commonAppleSiliconSpecs)
            return list
        }

        if chip.contains("Apple M5") {
            var list: [Spec] = []
            let superCores = ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K"]
            let performanceCores = ["Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"]
            for (index, key) in superCores.enumerated() {
                list.append(Spec(key: key, name: "CPU 超级核 \(index + 1)", group: .cpu))
            }
            for (index, key) in performanceCores.enumerated() {
                list.append(Spec(key: key, name: "CPU 性能核 \(index + 1)", group: .cpu))
            }
            for (index, key) in ["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"].enumerated() {
                list.append(Spec(key: key, name: "GPU \(index + 1)", group: .gpu))
            }
            list.append(contentsOf: commonAppleSiliconSpecs)
            return list
        }

        if chip.contains("Apple M4") {
            var list: [Spec] = []
            for (index, key) in ["Te05", "Te0S", "Te09", "Te0H"].enumerated() {
                list.append(Spec(key: key, name: "CPU 能效核 \(index + 1)", group: .cpu))
            }
            for (index, key) in ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"].enumerated() {
                list.append(Spec(key: key, name: "CPU 性能核 \(index + 1)", group: .cpu))
            }
            for (index, key) in ["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"].enumerated() {
                list.append(Spec(key: key, name: "GPU \(index + 1)", group: .gpu))
            }
            list.append(contentsOf: [
                Spec(key: "Tm0p", name: "内存 1", group: .memory),
                Spec(key: "Tm1p", name: "内存 2", group: .memory),
                Spec(key: "Tm2p", name: "内存 3", group: .memory)
            ])
            list.append(contentsOf: appleSiliconSSDSpecs)
            return list
        }

        if chip.contains("Apple M3") {
            var list: [Spec] = []
            for (index, key) in ["Te05", "Te0L", "Te0P", "Te0S"].enumerated() {
                list.append(Spec(key: key, name: "CPU 能效核 \(index + 1)", group: .cpu))
            }
            for (index, key) in ["Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"].enumerated() {
                list.append(Spec(key: key, name: "CPU 性能核 \(index + 1)", group: .cpu))
            }
            for (index, key) in ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"].enumerated() {
                list.append(Spec(key: key, name: "GPU \(index + 1)", group: .gpu))
            }
            list.append(contentsOf: appleSiliconSSDSpecs)
            return list
        }

        if chip.contains("Apple M2") {
            var list: [Spec] = []
            for (index, key) in ["Tp1h", "Tp1t", "Tp1p", "Tp1l"].enumerated() {
                list.append(Spec(key: key, name: "CPU 能效核 \(index + 1)", group: .cpu))
            }
            for (index, key) in ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"].enumerated() {
                list.append(Spec(key: key, name: "CPU 性能核 \(index + 1)", group: .cpu))
            }
            for (index, key) in ["Tg0f", "Tg0j"].enumerated() {
                list.append(Spec(key: key, name: "GPU \(index + 1)", group: .gpu))
            }
            list.append(contentsOf: [
                Spec(key: "Tm02", name: "内存 1", group: .memory),
                Spec(key: "Tm06", name: "内存 2", group: .memory),
                Spec(key: "Tm08", name: "内存 3", group: .memory),
                Spec(key: "Tm09", name: "内存 4", group: .memory)
            ])
            list.append(contentsOf: appleSiliconSSDSpecs)
            return list
        }

        if chip.contains("Apple M1") {
            var list: [Spec] = []
            for (index, key) in ["Tp09", "Tp0T"].enumerated() {
                list.append(Spec(key: key, name: "CPU 能效核 \(index + 1)", group: .cpu))
            }
            for (index, key) in ["Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"].enumerated() {
                list.append(Spec(key: key, name: "CPU 性能核 \(index + 1)", group: .cpu))
            }
            for (index, key) in ["Tg05", "Tg0D", "Tg0L", "Tg0T"].enumerated() {
                list.append(Spec(key: key, name: "GPU \(index + 1)", group: .gpu))
            }
            list.append(contentsOf: [
                Spec(key: "Tm02", name: "内存 1", group: .memory),
                Spec(key: "Tm06", name: "内存 2", group: .memory),
                Spec(key: "Tm08", name: "内存 3", group: .memory),
                Spec(key: "Tm09", name: "内存 4", group: .memory)
            ])
            list.append(contentsOf: appleSiliconSSDSpecs)
            return list
        }

        // Intel Macs.
        return [
            Spec(key: "TC0P", name: "CPU 核心 1", group: .cpu),
            Spec(key: "TC0D", name: "CPU 核心 2", group: .cpu),
            Spec(key: "TC0E", name: "CPU 核心 3", group: .cpu),
            Spec(key: "TC0F", name: "CPU 核心 4", group: .cpu),
            Spec(key: "TC0H", name: "CPU 散热器", group: .cpu),
            Spec(key: "TCAC", name: "CPU 封装", group: .cpu),
            Spec(key: "TG0P", name: "GPU 1", group: .gpu),
            Spec(key: "TG0D", name: "GPU 2", group: .gpu),
            Spec(key: "TG0H", name: "GPU 散热器", group: .gpu),
            Spec(key: "TH0A", name: "SSD 1", group: .disk),
            Spec(key: "TH0B", name: "SSD 2", group: .disk),
            Spec(key: "TH0C", name: "SSD 3", group: .disk)
        ]
    }

    private static let commonAppleSiliconSpecs: [Spec] = [
        Spec(key: "Tm0p", name: "内存 1", group: .memory),
        Spec(key: "Tm1p", name: "内存 2", group: .memory),
        Spec(key: "Tm2p", name: "内存 3", group: .memory)
    ] + appleSiliconSSDSpecs
}
