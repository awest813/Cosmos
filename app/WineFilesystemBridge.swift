import Foundation

/// Runs only Cosmos's local Python reader; never invokes Wine or repairs files.
enum WineFilesystemBridge {
    static func resolve(_ path: String, prefix: URL) throws -> URL {
        URL(fileURLWithPath: try read("host", path: path, prefix: prefix))
    }
    static func windowsPath(_ path: String, prefix: URL) throws -> String {
        try read("windows", path: path, prefix: prefix)
    }
    private static func read(_ operation: String, path: String, prefix: URL) throws -> String {
        guard let root = CosmosPaths.cosmosRoot() else {
            throw NSError(domain: "Cosmos.Filesystem", code: 1, userInfo: [NSLocalizedDescriptionKey: "Filesystem helper is unavailable."])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", root.appendingPathComponent("scripts/lib/wine_filesystem.py").path, operation, prefix.path, path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: timeout)
        defer { timeout.cancel() }
        // Drain before waiting, including errors; the reader's output is bounded.
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()
        let valid = operation == "host" ? output.hasPrefix("/") : output.range(of: "^[A-Za-z]:\\\\", options: .regularExpression) != nil
        guard process.terminationStatus == 0, valid else {
            throw NSError(domain: "Cosmos.Filesystem", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "The file check was interrupted or timed out. Reconnect the drive and retry." : output])
        }
        return output
    }
}
