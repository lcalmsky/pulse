import Foundation
import OSLog
import PulseCore

final class PageAlertSource {
    private static let logger = Logger(subsystem: "io.github.lcalmsky.pulse", category: "page")

    let directory: URL

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        directory = PageAlerts.directory(environment: environment)
    }

    func read() -> PageAlertReadResult {
        let result = PageAlerts.load(directory: directory)
        if result.directoryUnreadable {
            Self.logger.error("페이지 디렉터리를 읽지 못했다: \(self.directory.path, privacy: .public)")
        }
        for name in result.unreadableFiles {
            Self.logger.error("페이지 파일을 읽지 못했다: \(name, privacy: .public)")
        }
        return result
    }

    func remove(fileName: String) {
        do {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
        } catch {
            Self.logger.error(
                "페이지 파일을 지우지 못했다: \(fileName, privacy: .public) \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
