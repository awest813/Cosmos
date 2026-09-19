import Foundation

/// Owns a process on a worker thread until both its output and exit status have
/// been collected. Main-queue callbacks are ordered: output always precedes exit.
enum CosmosCommandRunner {
    /// Optional lifecycle tracing for diagnosing native command delivery.
    static func trace(_ message: String) {
        guard ProcessInfo.processInfo.environment["COSMOS_COMMAND_TRACE"] == "1" else { return }
        FileHandle.standardError.write(Data(("Cosmos command: " + message + "\n").utf8))
    }

    static func run(
        executable: URL,
        arguments: [String],
        directory: URL,
        environment: [String: String],
        onOutput: @escaping (String) -> Void,
        onCompletion: @escaping (Result<Int32, Error>) -> Void
    ) {
        trace("scheduled")
        DispatchQueue.global(qos: .userInitiated).async {
            trace("worker started")
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
                trace("process started")
                // Drain while the process runs, so a large download/build log
                // cannot fill the pipe and block the child before it exits.
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    let text = String(decoding: data, as: UTF8.self)
                    DispatchQueue.main.async { trace("delivering output"); onOutput(text) }
                }
                process.waitUntilExit()
                let status = process.terminationStatus
                trace("process exited: \(status)")
                DispatchQueue.main.async { trace("delivering completion"); onCompletion(.success(status)) }
            } catch {
                trace("process could not start")
                DispatchQueue.main.async { trace("delivering launch failure"); onCompletion(.failure(error)) }
            }
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
    }
}
