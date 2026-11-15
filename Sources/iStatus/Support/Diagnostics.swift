import Foundation

/// Headless sampling used by `iStatus --dump` for verification and troubleshooting.
enum Diagnostics {
    static func run() {
        let monitor = SystemMonitor()
        monitor.refresh()
        Thread.sleep(forTimeInterval: 1.05)
        monitor.refresh()

        let metrics = monitor.metrics

        print("iStatus diagnostics")
        print("===================")
        print("机型: \(SystemInfo.modelName) (\(SystemInfo.modelID))")
        print("芯片: \(SystemInfo.chip) · \(SystemInfo.coreDescription)")
        print("主机: \(SystemInfo.hostname)")
        print("系统: \(SystemInfo.osVersion)")
        print("运行: \(Fmt.uptime(metrics.uptime))")
        print("")

        print("CPU: \(Fmt.percent(metrics.cpu.usage))")
        print("  用户 \(Fmt.percent(metrics.cpu.user)) / 系统 \(Fmt.percent(metrics.cpu.system)) / 空闲 \(Fmt.percent(metrics.cpu.idle))")
        print("  负载 \(Fmt.loadAverage(metrics.cpu.load1)) / \(Fmt.loadAverage(metrics.cpu.load5)) / \(Fmt.loadAverage(metrics.cpu.load15))")
        print("  核心: " + metrics.cpu.perCore.map { Fmt.percent($0) }.joined(separator: "  "))
        print("")

        let memory = metrics.memory
        print("内存: \(Fmt.bytes(Double(memory.used))) / \(Fmt.bytes(Double(memory.total))) (\(Fmt.percent(memory.usage)))")
        print("  应用 \(Fmt.bytes(Double(memory.app))) · 联动 \(Fmt.bytes(Double(memory.wired))) · 压缩 \(Fmt.bytes(Double(memory.compressed))) · 缓存 \(Fmt.bytes(Double(memory.cached))) · 空闲 \(Fmt.bytes(Double(memory.free)))")
        print("  交换 \(Fmt.bytes(Double(memory.swapUsed))) / \(Fmt.bytes(Double(memory.swapTotal))) · 压力 \(memory.pressureText)")
        print("")

        let gpu = metrics.gpu
        print("GPU: \(gpu.name)\(gpu.coreCount.map { " · \($0) 核" } ?? "")")
        if let utilization = gpu.utilization {
            print("  利用率 \(Fmt.percent(utilization)) · 统一内存 \(gpu.memoryInUse.map { Fmt.bytes(Double($0)) } ?? "—") · 分配 \(gpu.memoryAllocated.map { Fmt.bytes(Double($0)) } ?? "—")")
        } else {
            print("  利用率不可用")
        }
        print("")

        let disk = metrics.disk
        print("SSD: \(disk.volumeName) \(Fmt.bytes(Double(disk.used))) / \(Fmt.bytes(Double(disk.total))) (\(Fmt.percent(disk.usage)))")
        print("  可用 \(Fmt.bytes(Double(disk.free))) · 读 \(Fmt.rate(disk.readPerSecond)) · 写 \(Fmt.rate(disk.writePerSecond))")
        print("")

        let network = metrics.network
        print("网络: \(network.interfaceName)\(network.ipAddress.map { " · \($0)" } ?? "")")
        print("  下行 \(Fmt.rate(network.downPerSecond)) · 上行 \(Fmt.rate(network.upPerSecond))")
        print("  累计接收 \(Fmt.bytes(Double(network.receivedTotal))) · 发送 \(Fmt.bytes(Double(network.sentTotal)))")
        print("")

        let thermal = metrics.thermal
        print("温度与风扇: CPU \(thermal.cpuTemp.map { Fmt.temperature($0, unit: .celsius) } ?? "—") · GPU \(thermal.gpuTemp.map { Fmt.temperature($0, unit: .celsius) } ?? "—") · SSD \(thermal.ssdTemp.map { Fmt.temperature($0, unit: .celsius) } ?? "—")")
        if thermal.fans.isEmpty {
            print("  风扇: 未检测到")
        } else {
            for fan in thermal.fans {
                print("  \(fan.name): \(Int(fan.current.rounded())) RPM (\(Int(fan.minimum.rounded()))–\(Int(fan.maximum.rounded())))")
            }
        }
        print("  传感器 (\(thermal.sensors.count)):")
        for sensor in thermal.sensors {
            print("    \(sensor.name) [\(sensor.key)] \(Fmt.temperature(sensor.celsius, unit: .celsius))")
        }
    }
}
