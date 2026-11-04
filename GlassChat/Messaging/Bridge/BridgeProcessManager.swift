import Foundation

/// Launches and supervises the bundled `glasschat-bridge` helper.
@MainActor
final class BridgeProcessManager {
    private var process: Process?
    private let supportDirectory: URL

    var socketURL: URL {
        supportDirectory.appendingPathComponent("bridge.sock")
    }

    var dataDirectory: URL {
        supportDirectory.appendingPathComponent("whatsmeow", isDirectory: true)
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        supportDirectory = base.appendingPathComponent("GlassChat", isDirectory: true)
    }

    func ensureRunning() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

        if let process, process.isRunning {
            return
        }

        let executable = try resolveBridgeExecutable()
        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "-socket", socketURL.path,
            "-data", dataDirectory.path
        ]
        process.standardOutput = FileHandle.nullDevice
        // Keep stderr visible in Console.app via a pipe if needed later.
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
    }

    func waitForSocket(timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: socketURL.path) {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw MessagingError.bridgeUnavailable("Bridge socket did not appear at \(socketURL.path)")
    }

    func stop() {
        process?.terminate()
        process = nil
        try? FileManager.default.removeItem(at: socketURL)
    }

    private func resolveBridgeExecutable() throws -> URL {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "glasschat-bridge") {
            return bundled
        }
        if let resource = Bundle.main.url(forResource: "glasschat-bridge", withExtension: nil) {
            return resource
        }

        // Development fallback: Bridge/glasschat-bridge next to the repo / derived sources.
        let candidates = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Bridge/
                .deletingLastPathComponent() // Messaging/
                .deletingLastPathComponent() // GlassChat/
                .deletingLastPathComponent() // repo root
                .appendingPathComponent("Bridge/glasschat-bridge"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Projects/GlassChat/Bridge/glasschat-bridge")
        ]
        for url in candidates where FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }

        throw MessagingError.bridgeUnavailable(
            "glasschat-bridge binary not found. Build it with `cd Bridge && go build -o glasschat-bridge ./cmd/glasschat-bridge`."
        )
    }
}
