import Foundation

/// 세션을 눌렀을 때 할 일. 끝난 세션이면 터미널로 이동하지 않고, 아니면 Orca 핸들 → cwd 로
/// 터미널 찾기 순으로 고르며 둘 다 없으면 아무것도 없다.
public enum SessionClickAction: Equatable {
    case orca(String)
    case cwd(String)
    case ended
    case none
}

public enum SessionClick {
    public static func resolve(
        orcaTerminal: String?,
        cwd: String? = nil,
        ended: Bool = false
    ) -> SessionClickAction {
        let terminal = trimmed(orcaTerminal)
        let directory = trimmed(cwd)
        if ended, terminal != nil || directory != nil {
            return .ended
        }
        if let terminal {
            return .orca(terminal)
        }
        if let directory {
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
