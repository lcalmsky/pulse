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

// 멀티플렉서 소켓이나 자식 프로세스 파이프가 먼저 닫혀도 앱이 꺼지지 않고 쓰기 오류로 받게 한다.
signal(SIGPIPE, SIG_IGN)

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
