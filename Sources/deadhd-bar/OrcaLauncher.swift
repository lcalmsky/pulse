import AppKit
import Foundation

enum OrcaLauncher {
    private static let bundleIdentifier = "com.stablyai.orca"
    private static let appPath = "/Applications/Orca.app"
    private static let cliPath = "/Applications/Orca.app/Contents/Resources/bin/orca"

    /// Orca 터미널로 이동한다. 완료 콜백은 메인 스레드에서 호출된다.
    static func switchTerminal(handle: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            if FileManager.default.isExecutableFile(atPath: cliPath) {
                process.executableURL = URL(fileURLWithPath: cliPath)
                process.arguments = ["terminal", "switch", "--terminal", handle, "--json"]
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["orca", "terminal", "switch", "--terminal", handle, "--json"]
            }
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            var succeeded = false
            do {
                try process.run()
                process.waitUntilExit()
                succeeded = process.terminationStatus == 0
            } catch {
                succeeded = false
            }

            DispatchQueue.main.async {
                if succeeded { bringForward() }
                completion(succeeded)
            }
        }
    }

    private static func bringForward() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                _ = NSWorkspace.shared.open(URL(fileURLWithPath: appPath))
            }
        } else {
            _ = NSWorkspace.shared.open(URL(fileURLWithPath: appPath))
        }
    }
}
