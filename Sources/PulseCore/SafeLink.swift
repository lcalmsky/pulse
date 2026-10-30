import Foundation

/// 화면에서 여는 링크는 http·https 만, 페이지 알림은 있는 html 파일만 받는다. 그 밖의 대상은 앱이 열 수 있는 범위를 넓힌다.
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

    /// 기본 앱으로 열 페이지 주소. 존재·일반 파일 확인은 IO 라 호출 쪽에서 넘긴다.
    public static func pageFileURL(_ string: String, isRegularFile: (String) -> Bool) -> URL? {
        guard let url = URL(string: string),
              url.scheme?.lowercased() == "file",
              !url.path.isEmpty
        else { return nil }
        let fileExtension = url.pathExtension.lowercased()
        guard fileExtension == "html" || fileExtension == "htm",
              isRegularFile(url.path)
        else { return nil }
        return url
    }
}
