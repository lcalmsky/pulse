import AppKit
import PulseCore

switch LaunchCommand.parse(CommandLine.arguments) {
case .run:
    break
case .version:
    print("pulse \(AppInfo.version)")
    exit(0)
case .help:
    print(L10n.usage)
    exit(0)
case .unknown(let option):
    FileHandle.standardError.write(Data((L10n.unknownOption(option) + "\n\n" + L10n.usage + "\n").utf8))
    exit(2)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
