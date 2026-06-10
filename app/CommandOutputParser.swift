import Foundation

/// Parses shell command stdout/stderr for user-facing error hints.
enum CommandOutputParser {
    static func decode(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    /// Last `Error: …` line from Cosmos scripts (`die()`), without the prefix.
    static func lastErrorMessage(from output: String) -> String? {
        let lines = output.split(whereSeparator: \.isNewline).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for line in lines.reversed() {
            if line.hasPrefix("Error:") {
                let message = line.dropFirst("Error:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return message.isEmpty ? nil : message
            }
        }
        return nil
    }

    /// Short summary from `repair.command diagnose` output.
    static func diagnoseSummary(from output: String) -> String? {
        if let count = suggestedFixCount(from: output), count > 0 {
            let noun = count == 1 ? "issue" : "issues"
            return "Diagnosis found \(count) \(noun). Review the output below or apply safe fixes."
        }
        if output.contains("No issues detected") {
            return "No issues detected in the launch log. Try switching the graphics backend or re-running the game."
        }
        if output.contains("No launch log yet") || output.contains("Log: (not found") {
            return "No launch log found yet. Run the game once, then diagnose again."
        }
        return nil
    }

    static func suggestedFixCount(from output: String) -> Int? {
        let pattern = #"Suggested fixes \((\d+)\):"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: output,
                range: NSRange(output.startIndex..., in: output)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return Int(output[range])
    }

    /// Bound console size while keeping recent `Error:` lines at the top.
    static func trimPreservingErrors(_ output: String, maxChars: Int = 120_000, tailChars: Int = 100_000) -> (text: String, trimmed: Bool) {
        guard output.count > maxChars else {
            return (output, false)
        }
        let errorLines = output.split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Error:") }
            .suffix(5)
        let tail = String(output.suffix(tailChars))
        if errorLines.isEmpty {
            return ("…(earlier output trimmed)…\n" + tail, true)
        }
        let header = errorLines.joined(separator: "\n")
        return ("…(earlier output trimmed)…\n\(header)\n…\n" + tail, true)
    }

    /// Summary from `repair.command apply-suggested` output.
    static func applySuggestedSummary(from output: String) -> String? {
        let pattern = #"Applied (\d+) suggestion"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: output,
                range: NSRange(output.startIndex..., in: output)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: output),
              let count = Int(output[range]) else {
            return nil
        }
        return "Applied \(count) safe fix\(count == 1 ? "" : "es"). Retry the launch."
    }

    static func failureMessage(
        exitCode: Int32,
        intent: CommandFailureContext,
        output: String
    ) -> String {
        if let scriptError = lastErrorMessage(from: output) {
            return scriptError
        }
        switch intent {
        case .setup:
            return "Setup step failed (exit \(exitCode)). Open Logs for details, then retry the step above."
        case .gameLaunch:
            return "Launch failed (exit \(exitCode)). Running diagnosis…"
        case .diagnose:
            return diagnoseSummary(from: output) ?? "Diagnosis finished (exit \(exitCode)). See output below."
        case .general:
            return "Command exited with status \(exitCode). Check the output below."
        }
    }
}

enum CommandFailureContext: Equatable {
    case general
    case setup
    case diagnose
    case gameLaunch
}
