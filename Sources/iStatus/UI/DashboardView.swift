import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var settings: AppSettings

    var openSettings: () -> Void
    var quit: () -> Void

    @State private var showAllSensors = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 9) {
                    cpuCard
                    memoryCard
                    gpuCard
                    diskCard
                    networkCard
                    thermalCard
                    systemCard
                }
                .padding(12)
            }

            Divider().opacity(0.55)
            footer
        }
        .frame(width: 372, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header & footer

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.blue, AppTheme.teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("系统状态")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(SystemInfo.modelName) · \(SystemInfo.chip)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Circle()
                    .fill(AppTheme.green)
                    .frame(width: 5, height: 5)
                Text("实时")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("每 \(refreshText) 秒刷新")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Spacer()
            FooterIconButton(icon: "arrow.clockwise", help: "立即刷新") {
                monitor.refresh()
            }
            FooterIconButton(icon: "gearshape", help: "设置") {
                openSettings()
            }
            FooterIconButton(icon: "power", help: "退出 iStatus") {
                quit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var refreshText: String {
        let value = settings.config.refreshInterval
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    // MARK: - CPU

    private var cpuCard: some View {
        let cpu = monitor.metrics.cpu
        return Card(
            title: "CPU",
            icon: "cpu",
            tint: AppTheme.blue,
            subtitle: SystemInfo.coreDescription
        ) {
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Fmt.percentValue(cpu.usage))")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 70, alignment: .leading)

                Sparkline(
                    values: monitor.history.cpu,
                    color: AppTheme.blue,
                    fixedMaximum: 1
                )
                .frame(height: 30)
            }

            HStack(spacing: 4) {
                Text("负载")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Text("\(Fmt.loadAverage(cpu.load1)) / \(Fmt.loadAverage(cpu.load5)) / \(Fmt.loadAverage(cpu.load15))")
                    .font(.system(size: 9.5, design: .monospaced))
                Spacer()
                Text("用户 \(Fmt.percent(cpu.user)) · 系统 \(Fmt.percent(cpu.system))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if !cpu.perCore.isEmpty {
                CoreBars(values: cpu.perCore)
                    .padding(.top, 1)
            }
        }
    }

    // MARK: - Memory

    private var memoryCard: some View {
        let memory = monitor.metrics.memory
        let pressureColor: Color = {
            switch memory.pressureLevel {
            case 2: return AppTheme.orange
            case 4: return AppTheme.red
            default: return AppTheme.green
            }
        }()

        return Card(
            title: "内存",
            icon: "memorychip",
            tint: AppTheme.purple,
            subtitle: Fmt.bytes(Double(memory.total))
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Fmt.bytes(Double(memory.used)))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("/ \(Fmt.bytes(Double(memory.total)))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text(memory.pressureText)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(pressureColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(pressureColor.opacity(0.12)))
            }

            UsageBar(
                segments: [
                    .init(value: Double(memory.app), color: AppTheme.blue),
                    .init(value: Double(memory.wired), color: AppTheme.purple),
                    .init(value: Double(memory.compressed), color: AppTheme.orange),
                    .init(value: Double(memory.cached), color: AppTheme.teal.opacity(0.55))
                ],
                total: Double(memory.total)
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 3
            ) {
                LegendItem(color: AppTheme.blue, label: "应用", value: Fmt.bytes(Double(memory.app)))
                LegendItem(color: AppTheme.purple, label: "联动", value: Fmt.bytes(Double(memory.wired)))
                LegendItem(color: AppTheme.orange, label: "压缩", value: Fmt.bytes(Double(memory.compressed)))
                LegendItem(color: AppTheme.teal.opacity(0.55), label: "缓存", value: Fmt.bytes(Double(memory.cached)))
            }

            HStack(spacing: 4) {
                Text("交换")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("\(Fmt.bytes(Double(memory.swapUsed))) / \(Fmt.bytes(Double(memory.swapTotal)))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("空闲 \(Fmt.bytes(Double(memory.free)))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - GPU

    private var gpuCard: some View {
        let gpu = monitor.metrics.gpu
        let subtitle = gpu.coreCount.map { "\($0) 核" } ?? (gpu.name.isEmpty ? nil : gpu.name)

        return Card(title: "GPU", icon: "display", tint: AppTheme.teal, subtitle: subtitle) {
            if let utilization = gpu.utilization {
                HStack(alignment: .center, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Fmt.percentValue(utilization))")
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 66, alignment: .leading)

                    Sparkline(
                        values: monitor.history.gpu,
                        color: AppTheme.teal,
                        fixedMaximum: 1
                    )
                    .frame(height: 24)
                }

                HStack(spacing: 4) {
                    Text("统一内存")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    if let inUse = gpu.memoryInUse {
                        Text(Fmt.bytes(Double(inUse)))
                            .font(.system(size: 9, design: .monospaced))
                    }
                    if let allocated = gpu.memoryAllocated {
                        Text("/ 分配 \(Fmt.bytes(Double(allocated)))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(gpu.name)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            } else {
                Text("当前设备未提供 GPU 利用率")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - SSD

    private var diskCard: some View {
        let disk = monitor.metrics.disk
        return Card(
            title: "SSD",
            icon: "internaldrive",
            tint: AppTheme.orange,
            subtitle: disk.volumeName
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Fmt.percentValue(disk.usage))%")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(disk.usage >= 0.9 ? AppTheme.orange : .primary)
                Text("已用 \(Fmt.bytes(Double(disk.used))) / \(Fmt.bytes(Double(disk.total)))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
            }

            UsageBar(
                segments: [
                    .init(value: Double(disk.used), color: disk.usage >= 0.9 ? AppTheme.orange : AppTheme.blue)
                ],
                total: Double(disk.total)
            )

            HStack(spacing: 4) {
                Text("可用 \(Fmt.bytes(Double(disk.free)))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Label(Fmt.rate(disk.readPerSecond), systemImage: "arrow.down")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Label(Fmt.rate(disk.writePerSecond), systemImage: "arrow.up")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Network

    private var networkCard: some View {
        let network = monitor.metrics.network
        return Card(
            title: "网络",
            icon: "network",
            tint: AppTheme.blue,
            subtitle: network.ipAddress ?? network.interfaceName
        ) {
            HStack(spacing: 12) {
                networkColumn(
                    icon: "arrow.down",
                    title: "下载",
                    value: Fmt.rate(network.downPerSecond),
                    color: AppTheme.blue,
                    values: monitor.history.networkDown
                )
                Divider().frame(height: 42)
                networkColumn(
                    icon: "arrow.up",
                    title: "上传",
                    value: Fmt.rate(network.upPerSecond),
                    color: AppTheme.purple,
                    values: monitor.history.networkUp
                )
            }

            HStack(spacing: 4) {
                Text(network.interfaceName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("累计 ↓\(Fmt.bytes(Double(network.receivedTotal))) ↑\(Fmt.bytes(Double(network.sentTotal)))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func networkColumn(
        icon: String,
        title: String,
        value: String,
        color: Color,
        values: [Double]
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                Text(title)
                    .font(.system(size: 9))
            }
            .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Sparkline(values: values, color: color)
                .frame(height: 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Thermals

    private var thermalCard: some View {
        let thermal = monitor.metrics.thermal
        let subtitle = thermal.hottest.map {
            "最高 \(Fmt.temperature($0, unit: settings.config.temperatureUnit))"
        }

        return Card(
            title: "温度与风扇",
            icon: "thermometer.medium",
            tint: AppTheme.orange,
            subtitle: subtitle
        ) {
            HStack(spacing: 6) {
                TempPill(label: "CPU", celsius: thermal.cpuTemp, unit: settings.config.temperatureUnit)
                TempPill(label: "GPU", celsius: thermal.gpuTemp, unit: settings.config.temperatureUnit)
                TempPill(label: "SSD", celsius: thermal.ssdTemp, unit: settings.config.temperatureUnit)
            }

            if !thermal.fans.isEmpty {
                VStack(spacing: 4) {
                    ForEach(thermal.fans) { fan in
                        HStack {
                            Label(fan.name, systemImage: "fan")
                                .font(.system(size: 10, weight: .medium))
                            Spacer()
                            Text("\(Int(fan.current.rounded())) RPM")
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        }
                        FanGauge(
                            current: fan.current,
                            minimum: fan.minimum,
                            maximum: fan.maximum
                        )
                        HStack {
                            Text("最低 \(Int(fan.minimum.rounded()))")
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("最高 \(Int(fan.maximum.rounded()))")
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.top, 2)
            }

            if !thermal.sensors.isEmpty {
                DisclosureGroup(isExpanded: $showAllSensors) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ],
                        spacing: 3
                    ) {
                        ForEach(thermal.sensors) { sensor in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(AppTheme.temperature(sensor.celsius))
                                    .frame(width: 4, height: 4)
                                Text(sensor.name)
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                Text(Fmt.temperature(sensor.celsius, unit: settings.config.temperatureUnit))
                                    .monospacedDigit()
                            }
                            .font(.system(size: 8.5))
                        }
                    }
                    .padding(.top, 5)
                } label: {
                    Text("全部传感器 (\(thermal.sensors.count))")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if thermal.fans.isEmpty && !thermal.hasAnySensor {
                Text("此设备未提供温度或风扇传感器")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - System

    private var systemCard: some View {
        Card(title: "系统", icon: "info.circle", tint: .secondary) {
            VStack(spacing: 4) {
                InfoRow(label: "机型", value: SystemInfo.modelName)
                InfoRow(label: "芯片", value: SystemInfo.chip)
                InfoRow(label: "系统", value: SystemInfo.osVersion)
                InfoRow(label: "主机", value: SystemInfo.hostname)
                InfoRow(label: "运行", value: Fmt.uptime(monitor.metrics.uptime))
                InfoRow(label: "刷新", value: "每 \(refreshText) 秒")
            }
        }
    }
}
