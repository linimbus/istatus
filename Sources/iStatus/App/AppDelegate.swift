import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let monitor = SystemMonitor()
    private var statusBar: StatusBarController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()

        monitor.start(interval: settings.config.refreshInterval)

        let statusBar = StatusBarController(settings: settings, monitor: monitor)
        statusBar.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        statusBar.onQuit = {
            NSApp.terminate(nil)
        }
        self.statusBar = statusBar

        settings.onChange = { [weak self] in
            guard let self else { return }
            self.monitor.setInterval(self.settings.config.refreshInterval)
            self.statusBar?.applySettings()
        }

        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.statusBar?.showPanel()
            }
        }

        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.showSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Settings window

    @objc private func showSettings() {
        statusBar?.closePanel()

        if settingsWindow == nil {
            let view = SettingsView(settings: settings, monitor: monitor)
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "iStatus 设置"
            if let index = CommandLine.arguments.firstIndex(of: "--appearance"),
               index + 1 < CommandLine.arguments.count {
                window.appearance = NSAppearance(
                    named: CommandLine.arguments[index + 1] == "light" ? .aqua : .darkAqua
                )
            }
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.center()
            window.setFrameAutosaveName("iStatus.settings.window")
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    @objc private func showAbout() {
        let credits = NSAttributedString(
            string: "轻量原生的 macOS 系统状态栏工具\nCPU · 内存 · GPU · SSD · 网络 · 风扇 · 温度",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationVersion: SystemInfo.appVersion
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Main menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(title: "关于 iStatus", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 iStatus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}
