import Foundation

enum MetricModule: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case gpu
    case disk
    case network
    case fan
    case temperature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "内存"
        case .gpu: return "GPU"
        case .disk: return "SSD"
        case .network: return "网络"
        case .fan: return "风扇"
        case .temperature: return "温度"
        }
    }

    var letter: String {
        switch self {
        case .cpu: return "C"
        case .memory: return "M"
        case .gpu: return "G"
        case .disk: return "D"
        case .network: return "N"
        case .fan: return "F"
        case .temperature: return "T"
        }
    }

    var subtitle: String {
        switch self {
        case .cpu: return "使用率、核心与负载"
        case .memory: return "已用内存、交换与压力"
        case .gpu: return "利用率与统一内存"
        case .disk: return "容量、读写速度"
        case .network: return "实时上行 / 下行"
        case .fan: return "当前转速与范围"
        case .temperature: return "CPU / GPU / SSD 温度"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .gpu: return "display"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .fan: return "fan"
        case .temperature: return "thermometer.medium"
        }
    }

    /// Tag used to identify the sender of a status bar button action.
    var menuTag: Int {
        (MetricModule.allCases.firstIndex(of: self) ?? 0) + 1
    }

    static func from(menuTag: Int) -> MetricModule? {
        MetricModule.allCases.first(where: { $0.menuTag == menuTag })
    }
}

struct CPUSample: Equatable {
    var usage: Double = 0
    var user: Double = 0
    var system: Double = 0
    var idle: Double = 1
    var perCore: [Double] = []
    var load1: Double = 0
    var load5: Double = 0
    var load15: Double = 0
}

struct MemorySample: Equatable {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var free: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressureLevel: Int = 0

    var usage: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(used) / Double(total))
    }

    var pressureText: String {
        switch pressureLevel {
        case 1: return "正常"
        case 2: return "警告"
        case 4: return "严重"
        default: return "正常"
        }
    }
}

struct GPUSample: Equatable {
    var name: String = ""
    var coreCount: Int?
    var utilization: Double?
    var memoryInUse: UInt64?
    var memoryAllocated: UInt64?
    var available: Bool = false
}

struct DiskSample: Equatable {
    var total: Int64 = 0
    var free: Int64 = 0
    var used: Int64 = 0
    var usage: Double = 0
    var readPerSecond: Double = 0
    var writePerSecond: Double = 0
    var volumeName: String = "Macintosh HD"
}

struct NetworkSample: Equatable {
    var interfaceName: String = "—"
    var ipAddress: String?
    var downPerSecond: Double = 0
    var upPerSecond: Double = 0
    var receivedTotal: UInt64 = 0
    var sentTotal: UInt64 = 0
}

struct FanReading: Identifiable, Equatable {
    let index: Int
    var current: Double = 0
    var minimum: Double = 0
    var maximum: Double = 0

    var id: Int { index }
    var name: String { "风扇 \(index + 1)" }
}

enum SensorGroup: String {
    case cpu = "CPU"
    case gpu = "GPU"
    case memory = "内存"
    case disk = "SSD"
    case other = "其他"
}

struct TemperatureReading: Identifiable, Equatable {
    let key: String
    let name: String
    let group: SensorGroup
    var celsius: Double

    var id: String { key }
}

struct ThermalSample: Equatable {
    var fans: [FanReading] = []
    var cpuTemp: Double?
    var cpuAverage: Double?
    var gpuTemp: Double?
    var ssdTemp: Double?
    var hottest: Double?
    var sensors: [TemperatureReading] = []

    var hasAnySensor: Bool {
        cpuTemp != nil || gpuTemp != nil || ssdTemp != nil || !sensors.isEmpty
    }
}

struct Metrics: Equatable {
    var cpu = CPUSample()
    var memory = MemorySample()
    var gpu = GPUSample()
    var disk = DiskSample()
    var network = NetworkSample()
    var thermal = ThermalSample()
    var uptime: TimeInterval = 0
    var timestamp = Date.distantPast

    static let empty = Metrics()
}

/// Rolling history used by the small sparklines in the dashboard.
struct SampleHistory {
    static let capacity = 120

    private(set) var cpu: [Double] = []
    private(set) var memory: [Double] = []
    private(set) var gpu: [Double] = []
    private(set) var networkDown: [Double] = []
    private(set) var networkUp: [Double] = []
    private(set) var diskRead: [Double] = []
    private(set) var diskWrite: [Double] = []

    mutating func push(_ metrics: Metrics) {
        append(metrics.cpu.usage, to: &cpu)
        append(metrics.memory.usage, to: &memory)
        append(metrics.gpu.utilization ?? 0, to: &gpu)
        append(metrics.network.downPerSecond, to: &networkDown)
        append(metrics.network.upPerSecond, to: &networkUp)
        append(metrics.disk.readPerSecond, to: &diskRead)
        append(metrics.disk.writePerSecond, to: &diskWrite)
    }

    private func append(_ value: Double, to array: inout [Double]) {
        guard value.isFinite else { return }
        array.append(max(0, value))
        if array.count > Self.capacity {
            array.removeFirst(array.count - Self.capacity)
        }
    }
}
