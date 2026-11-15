import AppKit

if CommandLine.arguments.contains("--dump") {
    Diagnostics.run()
    exit(0)
}

// Development helper used to verify the SMAppService login item without the UI.
if let loginArgument = CommandLine.arguments.first(where: { $0.hasPrefix("--login-") }) {
    let settings = AppSettings()
    switch loginArgument {
    case "--login-enable":
        settings.setLaunchAtLogin(true)
    case "--login-disable":
        settings.setLaunchAtLogin(false)
    default:
        break
    }
    print("login item: \(settings.loginItemState)")
    print("detail: \(settings.loginItemState.description)")
    if let error = settings.loginError {
        print("error: \(error)")
    }
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)

// Development helper: render the interface in a fixed appearance for screenshots.
if let index = CommandLine.arguments.firstIndex(of: "--appearance"),
   index + 1 < CommandLine.arguments.count {
    let value = CommandLine.arguments[index + 1]
    application.appearance = NSAppearance(named: value == "light" ? .aqua : .darkAqua)
}

application.run()
