import AppKit

if CommandLine.arguments.contains("--version") {
    print("deadhd-bar \(AppInfo.version)")
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
