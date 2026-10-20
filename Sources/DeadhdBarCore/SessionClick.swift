import Foundation

/// 세션을 눌렀을 때 할 일. 페이지가 있으면 페이지, 없으면 Orca 터미널, 둘 다 없으면 아무것도 없다.
public enum SessionClickAction: Equatable {
    case detail(String)
    case orca(String)
    case none
}

public enum SessionClick {
    public static func resolve(href: String?, orcaTerminal: String?) -> SessionClickAction {
        if let href = trimmed(href) {
            return .detail(href)
        }
        if let terminal = trimmed(orcaTerminal) {
            return .orca(terminal)
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
