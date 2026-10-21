import Foundation

public enum ThemePreference: String, CaseIterable, Equatable {
    case system
    case light
    case dark
}

public struct AppSettings: Equatable {
    public static let densityKey = "density"
    public static let themeKey = "theme"
    public static let attentionNotificationsKey = "attentionNotifications"
    public static let doneNotificationsKey = "doneNotifications"

    public var density: Density
    public var theme: ThemePreference
    public var attentionNotifications: Bool
    public var doneNotifications: Bool

    public static let `default` = AppSettings()

    public init(
        density: Density = .rich,
        theme: ThemePreference = .system,
        attentionNotifications: Bool = true,
        doneNotifications: Bool = true
    ) {
        self.density = density
        self.theme = theme
        self.attentionNotifications = attentionNotifications
        self.doneNotifications = doneNotifications
    }

    /// 저장된 원문을 읽는다. 키가 없거나 알 수 없는 값이면 기본값을 쓴다.
    public init(
        densityRaw: String?,
        themeRaw: String?,
        attentionNotifications: Bool?,
        doneNotifications: Bool? = nil
    ) {
        self.init(
            density: densityRaw.flatMap(Density.init(rawValue:)) ?? .rich,
            theme: themeRaw.flatMap(ThemePreference.init(rawValue:)) ?? .system,
            attentionNotifications: attentionNotifications ?? true,
            doneNotifications: doneNotifications ?? true
        )
    }
}
