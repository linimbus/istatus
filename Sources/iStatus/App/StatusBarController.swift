import AppKit
import SwiftUI

final class StatusBarController: NSObject, NSPopoverDelegate {
    private enum WarningLevel: Equatable {
        case none
        case caution
        case critical

        var color: NSColor? {
            switch self {
            case .none: return nil
            // Explicit colors keep the tint stable in both light and dark menu bars.
            case .caution: return NSColor(srgbRed: 1.0, green: 0.58, blue: 0.20, alpha: 1)
            case .critical: return NSColor(srgbRed: 1.0, green: 0.30, blue: 0.30, alpha: 1)
            }
        }
    }

    private struct Payload {
        let value: String
        let tooltip: String
        let warning: WarningLevel
    }

    private let settings: AppSettings
    private let monitor: SystemMonitor

    private var mergedItem: NSStatusItem?
    private var mergedView: StatusItemView?
    private var appearanceObservation: NSKeyValueObservation?
    private var themeObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?

    private let popover = NSPopover()

    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    init(settings: AppSettings, monitor: SystemMonitor) {
        self.settings = settings
        self.monitor = monitor
        super.init()

        setupItem()
        setupPopover()
        observeAppearance()
        applySettings()

        monitor.onSample = { [weak self] _ in
            self?.updateTitles()
        }
    }

    deinit {
        appearanceObservation?.invalidate()
        if let themeObserver {
            DistributedNotificationCenter.default.removeObserver(themeObserver)
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    // MARK: - Public

    func applySettings() {
        updateTitles()
    }

    func showPanel() {
        guard let view = mergedView else { return }
        monitor.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func closePanel() {
        popover.performClose(nil)
    }

    // MARK: - Setup

    private var barHeight: CGFloat {
        max(22, NSStatusBar.system.thickness)
    }

    private func setupItem() {
        let height = barHeight
        let item = NSStatusBar.system.statusItem(withLength: 80)
        item.autosaveName = "iStatus.merged"

        let view = StatusItemView(frame: NSRect(x: 0, y: 0, width: 80, height: height))
        view.onClick = { [weak self] in
            self?.togglePopover()
        }
        view.onRightClick = { [weak self] in
            self?.showContextMenu()
        }

        item.view = view
        mergedItem = item
        mergedView = view
    }

    private func setupPopover() {
        let view = DashboardView(
            monitor: monitor,
            settings: settings,
            openSettings: { [weak self] in
                self?.openSettings()
            },
            quit: { [weak self] in
                self?.quit()
            }
        )
        popover.contentViewController = NSHostingController(rootView: view)
        popover.contentSize = NSSize(width: 372, height: 680)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    // MARK: - Appearance

    /// The menu bar can be light or dark independently of the app. Dynamic semantic
    /// colors are resolved explicitly and applied to the custom-drawn view, so the
    /// user-selected color is never overridden by AppKit.
    private func observeAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.appearanceChanged()
            }
        }

        themeObserver = DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appearanceChanged()
        }

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appearanceChanged()
        }
    }

    private func appearanceChanged() {
        mergedView?.needsDisplay = true
        updateTitles()
        popover.contentViewController?.view.needsDisplay = true
    }

    // MARK: - Actions

    private func togglePopover() {
        guard let view = mergedView else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        monitor.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    private func showContextMenu() {
        guard let view = mergedView else { return }
        let menu = NSMenu()

        let panel = NSMenuItem(title: "打开全局面板", action: #selector(menuOpenPanel), keyEquivalent: "")
        panel.target = self
        menu.addItem(panel)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 iStatus", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: view.bounds.height),
                in: view
            )
        }
    }

    @objc private func menuOpenPanel() {
        showPanel()
    }

    @objc private func menuOpenSettings() {
        openSettings()
    }

    @objc private func menuQuit() {
        quit()
    }

    private func openSettings() {
        popover.performClose(nil)
        onOpenSettings?()
    }

    private func quit() {
        popover.performClose(nil)
        onQuit?()
    }

    // MARK: - Popover delegate

    func popoverDidShow(_ notification: Notification) {
        guard let window = popover.contentViewController?.view.window else { return }
        window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        if let forcedAppearance {
            window.appearance = forcedAppearance
        }
        window.orderFrontRegardless()
    }

    /// Development-only override used by `--appearance light|dark` for screenshots.
    private var forcedAppearance: NSAppearance? {
        guard let index = CommandLine.arguments.firstIndex(of: "--appearance"),
              index + 1 < CommandLine.arguments.count else {
            return nil
        }
        let name: NSAppearance.Name = CommandLine.arguments[index + 1] == "light" ? .aqua : .darkAqua
        return NSAppearance(named: name)
    }

    // MARK: - Title rendering

    private var baseColor: NSColor {
        settings.config.statusBarColorMode.color(
            for: NSApp.effectiveAppearance,
            custom: settings.config.customStatusBarColor
        )
    }

    private func updateTitles() {
        guard let view = mergedView, let item = mergedItem else { return }

        let base = baseColor
        let style = settings.config.menuBarStyle
        var segments: [StatusItemView.Segment] = []
        var summary: [String] = []

        for module in MetricModule.allCases where settings.config[module] {
            let payload = payload(for: module)
            let showsSlot = style != .valueOnly && settings.config.showsIcon(module)
            segments.append(
                StatusItemView.Segment(
                    symbolName: showsSlot && style == .iconValue ? module.symbol : nil,
                    letter: showsSlot && style == .letterValue ? module.letter : nil,
                    value: payload.value,
                    tint: payload.warning.color ?? base,
                    accessibilityLabel: module.title
                )
            )
            summary.append(
                "\(module.title) \(payload.value.trimmingCharacters(in: .whitespaces))"
            )
        }

        let tooltip = summary.isEmpty
            ? "iStatus — 点击打开全局面板；右键打开菜单"
            : "iStatus · " + summary.joined(separator: " · ")

        view.update(
            segments: segments,
            iconPosition: settings.config.iconPosition,
            mainIconVisible: settings.config.showMainIcon,
            mainTint: base,
            tooltip: tooltip
        )

        let width = view.preferredWidth
        guard width > 0 else {
            item.isVisible = false
            return
        }

        item.isVisible = true
        if abs(item.length - width) > 0.5 {
            item.length = width
            view.frame = NSRect(x: 0, y: 0, width: width, height: barHeight)
        }
    }

    private func payload(for module: MetricModule) -> Payload {
        let metrics = monitor.metrics
        let unit = settings.config.temperatureUnit

        switch module {
        case .cpu:
            let value = metrics.cpu.usage
            return Payload(
                value: Fmt.fixedPercent(value),
                tooltip: "CPU \(Fmt.percent(value)) · 负载 \(Fmt.loadAverage(metrics.cpu.load1)) / \(Fmt.loadAverage(metrics.cpu.load5)) / \(Fmt.loadAverage(metrics.cpu.load15))",
                warning: usageWarning(value, high: 0.75, critical: 0.90)
            )

        case .memory:
            let value = metrics.memory.usage
            return Payload(
                value: Fmt.fixedPercent(value),
                tooltip: "内存 \(Fmt.bytes(Double(metrics.memory.used))) / \(Fmt.bytes(Double(metrics.memory.total))) · 交换 \(Fmt.bytes(Double(metrics.memory.swapUsed)))",
                warning: usageWarning(value, high: 0.80, critical: 0.90)
            )

        case .gpu:
            guard let utilization = metrics.gpu.utilization else {
                return Payload(
                    value: Fmt.fixedPercent(nil),
                    tooltip: "GPU 利用率不可用",
                    warning: .none
                )
            }
            var tooltip = "GPU \(Fmt.percent(utilization))"
            if let inUse = metrics.gpu.memoryInUse {
                tooltip += " · 统一内存 \(Fmt.bytes(Double(inUse)))"
            }
            return Payload(
                value: Fmt.fixedPercent(utilization),
                tooltip: tooltip,
                warning: usageWarning(utilization, high: 0.75, critical: 0.90)
            )

        case .disk:
            let value = metrics.disk.usage
            let tooltip = "SSD 已用 \(Fmt.percent(value)) · 可用 \(Fmt.bytes(Double(metrics.disk.free))) · 读 \(Fmt.rate(metrics.disk.readPerSecond)) · 写 \(Fmt.rate(metrics.disk.writePerSecond))"
            return Payload(
                value: Fmt.fixedPercent(value),
                tooltip: tooltip,
                warning: usageWarning(value, high: 0.90, critical: 0.95)
            )

        case .network:
            let tooltip = "\(metrics.network.interfaceName)\(metrics.network.ipAddress.map { " · \($0)" } ?? "") · ↓\(Fmt.rate(metrics.network.downPerSecond)) ↑\(Fmt.rate(metrics.network.upPerSecond))"
            return Payload(
                value: Fmt.networkStatus(
                    down: metrics.network.downPerSecond,
                    up: metrics.network.upPerSecond
                ),
                tooltip: tooltip,
                warning: .none
            )

        case .fan:
            guard let fan = metrics.thermal.fans.first else {
                return Payload(
                    value: Fmt.fixedRPM(nil),
                    tooltip: "未检测到风扇",
                    warning: .none
                )
            }
            let ratio = fan.maximum > 0 ? fan.current / fan.maximum : 0
            return Payload(
                value: Fmt.fixedRPM(fan.current),
                tooltip: "\(fan.name) \(Int(fan.current.rounded())) RPM · \(Int(fan.minimum.rounded()))–\(Int(fan.maximum.rounded())) RPM",
                warning: ratio >= 0.90 ? .caution : .none
            )

        case .temperature:
            guard let celsius = metrics.thermal.cpuTemp else {
                return Payload(
                    value: Fmt.fixedTemperature(nil, unit: unit),
                    tooltip: "未检测到温度传感器",
                    warning: .none
                )
            }
            var details = ["CPU \(Fmt.temperature(celsius, unit: unit))"]
            if let gpu = metrics.thermal.gpuTemp {
                details.append("GPU \(Fmt.temperature(gpu, unit: unit))")
            }
            if let ssd = metrics.thermal.ssdTemp {
                details.append("SSD \(Fmt.temperature(ssd, unit: unit))")
            }
            return Payload(
                value: Fmt.fixedTemperature(celsius, unit: unit),
                tooltip: details.joined(separator: " · "),
                warning: temperatureWarning(celsius)
            )
        }
    }

    private func usageWarning(_ value: Double, high: Double, critical: Double) -> WarningLevel {
        if value >= critical { return .critical }
        if value >= high { return .caution }
        return .none
    }

    private func temperatureWarning(_ celsius: Double) -> WarningLevel {
        if celsius >= 85 { return .critical }
        if celsius >= 70 { return .caution }
        return .none
    }
}
