import Foundation

/// Confirm the short AppleScript handoff, separately from the long-running
/// installer. An accepted handoff does not mean installation succeeded.
enum TerminalHandoffRunner {
    static func run(executable: URL = URL(fileURLWithPath: "/usr/bin/osascript"), arguments: [String], directory: URL,
                    completion: @escaping (String?) -> Void) {
        var output = ""
        CosmosCommandRunner.run(executable: executable, arguments: arguments, directory: directory,
            environment: ProcessInfo.processInfo.environment,
            onOutput: { output = String((output + $0).suffix(16384)) }, onCompletion: { result in
                switch result {
                case .success(let code):
                    completion(code == 0 ? nil : "Terminal did not accept the command (exit \(code)). \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                case .failure(let error): completion("Could not open Terminal: \(error.localizedDescription)")
                }
            })
    }
}
