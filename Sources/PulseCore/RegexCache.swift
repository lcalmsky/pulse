import Foundation

/// 패턴마다 한 번만 컴파일한다. NSRegularExpression 은 불변이라 여러 스레드가 함께 써도 된다.
enum RegexCache {
    private static let lock = NSLock()
    private static var compiled: [String: NSRegularExpression] = [:]

    static func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = compiled[pattern] {
            return cached
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        compiled[pattern] = regex
        return regex
    }
}
