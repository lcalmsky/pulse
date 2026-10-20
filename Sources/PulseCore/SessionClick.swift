import Foundation

/// 세션을 눌렀을 때 할 일. 페이지 → Orca 핸들 → cwd 로 터미널 찾기 순으로 고르고, 셋 다 없으면 아무것도 없다.
public enum SessionClickAction: Equatable {
    case detail(String)
    case orca(String)
    case cwd(String)
    case none
}

public enum SessionClick {
    public static func resolve(href: String?, orcaTerminal: String?, cwd: String? = nil) -> SessionClickAction {
        if let href = trimmed(href) {
            return .detail(href)
        }
        if let terminal = trimmed(orcaTerminal) {
            return .orca(terminal)
        }
        if let directory = trimmed(cwd) {
            return .cwd(directory)
        }
        return .none
    }

    static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
