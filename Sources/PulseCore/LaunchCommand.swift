import Foundation

/// `pulse` 실행 인자로 고르는 동작. 앱을 띄우는 것 말고는 출력만 하고 끝낸다.
public enum LaunchCommand: Equatable {
    case run
    case version
    case help
    case unknown(String)

    /// `-키 값` 처럼 대시 하나로 시작하는 인자는 UserDefaults 인자 도메인이라 그대로 앱에 넘긴다.
    public static func parse(_ arguments: [String]) -> LaunchCommand {
        for argument in arguments.dropFirst() {
            switch argument {
            case "--version":
                return .version
            case "--help", "-h":
                return .help
            default:
                if argument.hasPrefix("--") { return .unknown(argument) }
            }
        }
        return .run
    }
}
