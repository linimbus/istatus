import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                modulesSection
                displaySection
                colorSection
                refreshSection
                temperatureSection
                launchSection
                aboutSection
            }
            .padding(18)
        }
        .frame(width: 460, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            settings.refreshLoginItemState()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.blue, AppTheme.teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("iStatus")
                    .font(.system(size: 18, weight: .semibold))
                Text("轻量级系统状态栏工具")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("v\(SystemInfo.appVersion)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Modules

    private var modulesSection: some View {
        SettingsSection(title: "状态栏显示") {
            VStack(spacing: 0) {
                ForEach(Array(MetricModule.allCases.enumerated()), id: \.element.id) { index, module in
                    ModuleRow(module: module, settings: settings)
                    if index < MetricModule.allCases.count - 1 {
                        Divider().opacity(0.45)
                    }
                }
            }
        }
    }

    // MARK: - Display style

    private var displaySection: some View {
        SettingsSection(title: "显示方式") {
            VStack(alignment: .leading, spacing: 9) {
                Picker("", selection: $settings.config.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(settings.config.menuBarStyle.hint)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)

                Text(previewText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
            }
        }
    }

    private var previewText: String {
        var parts: [String] = []
        for module in MetricModule.allCases where settings.config[module] {
            let value = previewValue(for: module)
            if settings.config.menuBarStyle == .letterValue {
                parts.append("\(module.letter) \(value)")
            } else {
                parts.append(value)
            }
        }
        return parts.isEmpty ? "未选择状态栏模块" : parts.joined(separator: "   ")
    }

    private func previewValue(for module: MetricModule) -> String {
        let metrics = monitor.metrics
        switch module {
        case .cpu:
            return Fmt.fixedPercent(metrics.cpu.usage)
        case .memory:
            return Fmt.fixedPercent(metrics.memory.usage)
        case .gpu:
            return Fmt.fixedPercent(metrics.gpu.utilization)
        case .disk:
            return Fmt.fixedPercent(metrics.disk.usage)
        case .network:
            return Fmt.networkStatus(
                down: metrics.network.downPerSecond,
                up: metrics.network.upPerSecond
            )
        case .fan:
            return Fmt.fixedRPM(metrics.thermal.fans.first?.current)
        case .temperature:
            return Fmt.fixedTemperature(
                metrics.thermal.cpuTemp,
                unit: settings.config.temperatureUnit
            )
        }
    }

    // MARK: - Status bar color

    private var colorSection: some View {
        SettingsSection(title: "状态栏颜色") {
            VStack(alignment: .leading, spacing: 9) {
                Picker("", selection: $settings.config.statusBarColorMode) {
                    ForEach(StatusBarColorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(settings.config.statusBarColorMode.description)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)

                if settings.config.statusBarColorMode == .custom {
                    ColorPicker(
                        "自定义颜色",
                        selection: customColorBinding,
                        supportsOpacity: false
                    )
                    .font(.system(size: 10))
                }

                HStack(spacing: 8) {
                    colorPreview(
                        title: "浅色菜单栏",
                        background: Color(white: 0.95),
                        labelColor: Color.black.opacity(0.45),
                        appearance: .aqua
                    )
                    colorPreview(
                        title: "深色菜单栏",
                        background: Color(white: 0.14),
                        labelColor: Color.white.opacity(0.45),
                        appearance: .darkAqua
                    )
                }

                Text("macOS 菜单栏可能因壁纸保持深色；若自动模式不易阅读，请选择白色或自选颜色。")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("高负载或高温告警时，状态项仍会使用橙色/红色提示。")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.config.customStatusBarColor.nsColor) },
            set: { newValue in
                let nsColor = NSColor(newValue).usingColorSpace(.sRGB) ?? .white
                settings.config.customStatusBarColor = StatusBarColor(
                    red: Double(nsColor.redComponent),
                    green: Double(nsColor.greenComponent),
                    blue: Double(nsColor.blueComponent)
                )
            }
        )
    }

    private func colorPreview(
        title: String,
        background: Color,
        labelColor: Color,
        appearance: NSAppearance.Name
    ) -> some View {
        let nsAppearance = NSAppearance(named: appearance) ?? NSAppearance(named: .aqua)!
        let color = settings.config.statusBarColorMode.color(
            for: nsAppearance,
            custom: settings.config.customStatusBarColor
        )

        return VStack(alignment: .leading, spacing: 4) {
            Text("CPU 12%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(nsColor: color))
            Text(title)
                .font(.system(size: 8))
                .foregroundStyle(labelColor)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Refresh

    private var refreshSection: some View {
        SettingsSection(title: "刷新频率") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $settings.config.refreshInterval) {
                    Text("0.5 秒").tag(0.5)
                    Text("1 秒").tag(1.0)
                    Text("2 秒").tag(2.0)
                    Text("5 秒").tag(5.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text("采样间隔越短越实时，也会略微增加能耗。1 秒是推荐值。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var temperatureSection: some View {
        SettingsSection(title: "温度单位") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $settings.config.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text("同时作用于状态栏与全局面板中的 CPU、GPU、SSD 和传感器温度。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Launch at login

    private var launchSection: some View {
        SettingsSection(title: "开机自启动") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { settings.loginItemState.isOn },
                    set: { settings.setLaunchAtLogin($0) }
                )) {
                    HStack(spacing: 9) {
                        Image(systemName: "power")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("登录时自动运行")
                                .font(.system(size: 11, weight: .medium))
                            Text(settings.loginItemState.description)
                                .font(.system(size: 9))
                                .foregroundStyle(loginStateColor)
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if settings.loginItemState == .requiresApproval {
                    Button("打开系统设置中的登录项") {
                        settings.openLoginItemsSettings()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 9.5))
                }

                if let error = settings.loginError {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if settings.loginItemState != .enabled {
                    Text("提示：把 iStatus.app 放入“应用程序”文件夹后再开启，登录项指向会更稳定。")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var loginStateColor: Color {
        switch settings.loginItemState {
        case .enabled:
            return AppTheme.green
        case .requiresApproval:
            return AppTheme.orange
        case .failed:
            return AppTheme.red
        case .disabled, .unavailable:
            return .secondary
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        SettingsSection(title: "关于") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.blue)
                    Text("iStatus \(SystemInfo.appVersion)")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("原生 · 无依赖")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                Text("SwiftUI + IOKit + SMC + Mach 内核 API，全本地运行，不联网、不采集隐私。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)

                Text("点击状态栏图标打开全局面板；右键任一状态项可快速打开设置或退出。")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct ModuleRow: View {
    let module: MetricModule
    @ObservedObject var settings: AppSettings

    var body: some View {
        Toggle(isOn: Binding(
            get: { settings.config[module] },
            set: { settings.config[module] = $0 }
        )) {
            HStack(spacing: 10) {
                Image(systemName: module.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.blue)
                    .frame(width: 19)
                VStack(alignment: .leading, spacing: 1) {
                    Text(module.title)
                        .font(.system(size: 11, weight: .medium))
                    Text(module.subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.vertical, 6)
    }
}
