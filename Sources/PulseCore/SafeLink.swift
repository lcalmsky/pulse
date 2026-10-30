import Foundation

/// 화면에서 여는 링크는 http·https 만, 페이지 알림은 file 만 받는다. 그 밖의 스킴은 앱이 열 수 있는 대상을 넓힌다.
public enum SafeLink {
    public static func httpURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty
        else { return nil }
        return url
    }

    public static func fileURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              url.isFileURL,
              url.scheme?.lowercased() == "file"
        else { return nil }
        return url
    }
}
