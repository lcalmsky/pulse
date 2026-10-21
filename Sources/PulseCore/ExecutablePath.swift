import Foundation

/// 외부 실행 파일은 PATH 로 찾지 않고, 고정해 둔 절대 경로 후보에서만 고른다.
/// 실행 환경마다 PATH 가 달라지고, 쓰기 가능한 디렉터리가 앞서면 다른 프로그램이 대신 실행된다.
public enum ExecutablePath {
    /// 후보 중 절대 경로이면서 실행 가능한 첫 경로를 돌려준다. 없으면 nil.
    /// 절대 경로가 아닌 후보는 판정하지 않고 건너뛴다.
    public static func firstExecutable(
        in candidates: [String],
        isExecutable: (String) -> Bool
    ) -> String? {
        for candidate in candidates where candidate.hasPrefix("/") {
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }
}
