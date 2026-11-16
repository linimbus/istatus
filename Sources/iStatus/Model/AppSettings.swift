import Foundation
import AppKit
import ServiceManagement

enum MenuBarStyle: String, Codable, CaseIterable, Identifiable {
    case iconValue
    case valueOnly
    case letterValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconValue: return "图标 + 数值"
        case .valueOnly: return "仅数值"
        case .letterValue: return "字母 + 数值"
        }
    }

    var hint: String {
        switch self {
        case .iconValue: return "每个模块使用 SF Symbols 图标，可逐项关闭"
        case .valueOnly: return "只显示数值，不显示图标或字母"
        case .letterValue: return "用 C / M / G 等字母代替图标，可逐项关闭"
        }
    }
}

enum MenuBarIconPosition: String, Codable, CaseIterable, Identifiable {
    case top
    case bottom
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: return "上"
        case .bottom: return "下"
        case .left: return "左"
        case .right: return "右"
        }
    }

    var hint: String {
        switch self {
        case .top: return "图标/字母显示在数值上方"
        case .bottom: return "图标/字母显示在数值下方"
        case .left: return "图标/字母显示在数值左侧"
        case .right: return "图标/字母显示在数值右侧"
        }
    }

    var symbolName: String {
        switch self {
        case .top: return "arrow.up"
        case .bottom: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
    }
}

enum TemperatureUnit: String, Codable, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .celsius: return "摄氏度 °C"
        case .fahrenheit: return "华氏度 °F"
        }
    }

    var shortTitle: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }
}

enum StatusBarColorMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case white
    case black
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "自动"
        case .white: return "白色"
        case .black: return "黑色"
        case .custom: return "自选"
        }
    }

    var description: String {
        switch self {
        case .automatic:
            return "跟随系统外观：浅色用黑色，深色用白色。"
        case .white:
            return "始终使用白色，适合深色菜单栏或深色壁纸。"
        case .black:
            return "始终使用黑色，适合浅色菜单栏或浅色壁纸。"
        case .custom:
            return "使用下方自选颜色。"
        }
    }

    func color(for appearance: NSAppearance, custom: StatusBarColor) -> NSColor {
        switch self {
        case .automatic:
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? .white : .black
        case .white:
            return .white
        case .black:
            return .black
        case .custom:
            return custom.nsColor
        }
    }
}

struct StatusBarColor: Codable, Equatable {
    var red: Double = 0.23
    var green: Double = 0.55
    var blue: Double = 1.0

    static let defaultColor = StatusBarColor()

    var nsColor: NSColor {
        NSColor(
            srgbRed: component(red),
            green: component(green),
            blue: component(blue),
            alpha: 1
        )
    }

    private func component(_ value: Double) -> CGFloat {
        CGFloat(min(max(value, 0), 1))
    }
}

enum LoginItemState: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
    case failed(String)

    var isOn: Bool {
        self == .enabled || self == .requiresApproval
    }

    var description: String {
        switch self {
        case .enabled:
            return "已注册为登录项，开机后自动运行"
        case .disabled:
            return "尚未开启开机自启动"
        case .requiresApproval:
            return "需要在“系统设置 › 通用 › 登录项”中允许 iStatus"
        case .unavailable:
            return "请将 iStatus.app 放入“应用程序”文件夹后再开启"
        case .failed(let message):
            return message
        }
    }
}

struct AppConfig: Codable, Equatable {
    var showCPU = true
    var showMemory = true
    var showGPU = true
    var showDisk = true
    var showNetwork = true
    var showFan = false
    var showTemperature = true
    var showMainIcon = true

    var menuBarStyle: MenuBarStyle = .iconValue
    var iconPosition: MenuBarIconPosition = .top
    var moduleIcons: [String: Bool] = [:]
    var moduleOrder: [String] = AppConfig.defaultModuleOrder
    var barFontSize: Double = 9.0
    var barIconSize: Double = 8.0
    var refreshInterval: Double = 1.0
    var temperatureUnit: TemperatureUnit = .celsius
    var statusBarColorMode: StatusBarColorMode = .automatic
    var customStatusBarColor: StatusBarColor = .defaultColor

    static let barFontSizeRange: ClosedRange<Double> = 7.0...32.0
    static let barIconSizeRange: ClosedRange<Double> = 6.0...32.0
    static let defaultModuleOrder = MetricModule.allCases.map(\.rawValue)

    init() {}

    /// All configured modules in their saved order. Unknown or duplicate entries
    /// are dropped and any newly added modules are appended at the end.
    var orderedModules: [MetricModule] {
        var seen = Set<String>()
        var result: [MetricModule] = []

        for rawValue in moduleOrder {
            guard let module = MetricModule(rawValue: rawValue), !seen.contains(rawValue) else {
                continue
            }
            seen.insert(rawValue)
            result.append(module)
        }

        for module in MetricModule.allCases where !seen.contains(module.rawValue) {
            result.append(module)
        }
        return result
    }

    /// The main gauge is drawn larger than module icons, but follows the same slider.
    var mainIconPointSize: Double {
        let scaled = min(max(barIconSize * 1.6, 8), 32)
        return (scaled * 2).rounded() / 2
    }

    func showsIcon(_ module: MetricModule) -> Bool {
        moduleIcons[module.rawValue] ?? true
    }

    mutating func setShowsIcon(_ show: Bool, for module: MetricModule) {
        moduleIcons[module.rawValue] = show
    }

    private enum CodingKeys: String, CodingKey {
        case showCPU
        case showMemory
        case showGPU
        case showDisk
        case showNetwork
        case showFan
        case showTemperature
        case showMainIcon
        case menuBarStyle
        case iconPosition
        case moduleIcons
        case moduleOrder
        case barFontSize
        case barIconSize
        case refreshInterval
        case temperatureUnit
        case statusBarColorMode
        case customStatusBarColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showCPU = try container.decodeIfPresent(Bool.self, forKey: .showCPU) ?? true
        showMemory = try container.decodeIfPresent(Bool.self, forKey: .showMemory) ?? true
        showGPU = try container.decodeIfPresent(Bool.self, forKey: .showGPU) ?? true
        showDisk = try container.decodeIfPresent(Bool.self, forKey: .showDisk) ?? true
        showNetwork = try container.decodeIfPresent(Bool.self, forKey: .showNetwork) ?? true
        showFan = try container.decodeIfPresent(Bool.self, forKey: .showFan) ?? false
        showTemperature = try container.decodeIfPresent(Bool.self, forKey: .showTemperature) ?? true
        showMainIcon = try container.decodeIfPresent(Bool.self, forKey: .showMainIcon) ?? true
        menuBarStyle = try container.decodeIfPresent(MenuBarStyle.self, forKey: .menuBarStyle) ?? .iconValue
        iconPosition = try container.decodeIfPresent(MenuBarIconPosition.self, forKey: .iconPosition) ?? .top
        moduleIcons = try container.decodeIfPresent([String: Bool].self, forKey: .moduleIcons) ?? [:]
        moduleOrder = try container.decodeIfPresent([String].self, forKey: .moduleOrder) ?? Self.defaultModuleOrder
        barFontSize = try container.decodeIfPresent(Double.self, forKey: .barFontSize) ?? 9.0
        barIconSize = try container.decodeIfPresent(Double.self, forKey: .barIconSize) ?? 8.0
        refreshInterval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? 1.0
        temperatureUnit = try container.decodeIfPresent(TemperatureUnit.self, forKey: .temperatureUnit) ?? .celsius
        statusBarColorMode = try container.decodeIfPresent(StatusBarColorMode.self, forKey: .statusBarColorMode) ?? .automatic
        customStatusBarColor = try container.decodeIfPresent(StatusBarColor.self, forKey: .customStatusBarColor) ?? .defaultColor
    }

    subscript(module: MetricModule) -> Bool {
        get {
            switch module {
            case .cpu: return showCPU
            case .memory: return showMemory
            case .gpu: return showGPU
            case .disk: return showDisk
            case .network: return showNetwork
            case .fan: return showFan
            case .temperature: return showTemperature
            }
        }
        set {
            switch module {
            case .cpu: showCPU = newValue
            case .memory: showMemory = newValue
            case .gpu: showGPU = newValue
            case .disk: showDisk = newValue
            case .network: showNetwork = newValue
            case .fan: showFan = newValue
            case .temperature: showTemperature = newValue
            }
        }
    }
}

final class AppSettings: ObservableObject {
    @Published var config: AppConfig {
        didSet {
            guard oldValue != config else { return }
            save()
            onChange?()
        }
    }

    @Published private(set) var loginItemState: LoginItemState = .disabled
    @Published private(set) var loginError: String?

    /// Called after a persisted setting changed.
    var onChange: (() -> Void)?

    private static let defaultsKey = "com.linimbus.istatus.config.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = decoded
        } else {
            config = AppConfig()
        }
        refreshLoginItemState()
    }

    func refreshLoginItemState() {
        guard Self.isBundledApp else {
            loginItemState = .unavailable
            return
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            loginItemState = .enabled
        case .requiresApproval:
            loginItemState = .requiresApproval
        case .notFound:
            // Can happen before the first registration (and for apps outside /Applications).
            // Let the user try; register() reports a concrete error if the bundle is unusable.
            loginItemState = .disabled
        case .notRegistered:
            loginItemState = .disabled
        @unknown default:
            loginItemState = .disabled
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard Self.isBundledApp else {
            loginItemState = .unavailable
            return
        }

        loginError = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = error.localizedDescription
        }
        refreshLoginItemState()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }
}
