import Foundation

public enum ThemePreference: String, CaseIterable, Equatable {
    case system
    case light
    case dark
}

public enum AttentionAlert: String, CaseIterable, Equatable {
    case cardAndSound
    case cardOnly
    case off

    public var showsCard: Bool { self != .off }

    public var soundName: String? { self == .cardAndSound ? "Tink" : nil }
}

public enum DoneAlert: String, CaseIterable, Equatable {
    case card
    case off

    public var showsCard: Bool { self != .off }
}

public struct AppSettings: Equatable {
    public static let densityKey = "density"
    public static let themeKey = "theme"
    public static let attentionAlertKey = "attentionAlert"
    public static let doneAlertKey = "doneAlert"
    /// 이전 불리언 키. 새 키가 없을 때 이행용으로만 읽는다.
    public static let attentionNotificationsKey = "attentionNotifications"
    public static let doneNotificationsKey = "doneNotifications"

    public var density: Density
    public var theme: ThemePreference
    public var attentionAlert: AttentionAlert
    public var doneAlert: DoneAlert

    public static let `default` = AppSettings()

    public init(
        density: Density = .rich,
        theme: ThemePreference = .system,
        attentionAlert: AttentionAlert = .cardAndSound,
        doneAlert: DoneAlert = .card
    ) {
        self.density = density
        self.theme = theme
        self.attentionAlert = attentionAlert
        self.doneAlert = doneAlert
    }

    /// 저장된 원문을 읽는다. 새 키가 알려진 값이면 그것을, 아니면 이전 불리언을, 둘 다 없으면 기본값을 쓴다.
    public init(
        densityRaw: String?,
        themeRaw: String?,
        attentionAlertRaw: String? = nil,
        doneAlertRaw: String? = nil,
        legacyAttention: Bool? = nil,
        legacyDone: Bool? = nil
    ) {
        self.init(
            density: densityRaw.flatMap(Density.init(rawValue:)) ?? .rich,
            theme: themeRaw.flatMap(ThemePreference.init(rawValue:)) ?? .system,
            attentionAlert: attentionAlertRaw.flatMap(AttentionAlert.init(rawValue:))
                ?? legacyAttention.map { $0 ? .cardAndSound : .off }
                ?? .cardAndSound,
            doneAlert: doneAlertRaw.flatMap(DoneAlert.init(rawValue:))
                ?? legacyDone.map { $0 ? .card : .off }
                ?? .card
        )
    }
}
