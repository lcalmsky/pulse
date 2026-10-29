import Foundation

/// 세션을 눌렀을 때 할 일. 멀티플렉서 패널 → Orca 핸들 → cwd 로 터미널 찾기 순으로 고르며
/// 모두 없으면 아무것도 없다.
public enum SessionClickAction: Equatable {
    case multiplexer(MultiplexerPane)
    case orca(String)
    case cwd(String)
    case none
}

public enum SessionClick {
    public static func resolve(
        orcaTerminal: String?,
        cwd: String? = nil,
        multiplexer: MultiplexerPane? = nil
    ) -> SessionClickAction {
        // tmux 서버를 Orca 터미널에서 시작하면 그 안의 세션이 엉뚱한 ORCA_TERMINAL_HANDLE 을 물려받는다.
        if let multiplexer {
            return .multiplexer(multiplexer)
        }
        let terminal = trimmed(orcaTerminal)
        let directory = trimmed(cwd)
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
