import Foundation
@main
struct Check {
    static func main() {
        var output = ""
        var completions = 0
        var passed = false
        CosmosCommandRunner.run(executable: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", "for ((i=0;i<10000;i++)); do echo output-line; done; echo error-line >&2; exit 7"],
            directory: URL(fileURLWithPath: "/tmp"), environment: ProcessInfo.processInfo.environment,
            onOutput: { output += $0 },
            onCompletion: { result in
                completions += 1
                guard case .success(7) = result else { fatalError("wrong exit status") }
                precondition(output.components(separatedBy: "output-line").count == 10001)
                precondition(output.contains("error-line"))
                CosmosCommandRunner.run(executable: URL(fileURLWithPath: "/missing/cosmos-command"),
                    arguments: [], directory: URL(fileURLWithPath: "/tmp"), environment: [:],
                    onOutput: { _ in fatalError("missing executable produced output") },
                    onCompletion: { result in
                        guard case .failure = result else { fatalError("missing executable accepted") }
                        passed = true
                    })
            })
        let deadline = Date().addingTimeInterval(15)
        while !passed && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(passed && completions == 1, "command timed out or completed twice")
        print("PASS: large stdout/stderr, nonzero exit, missing executable, ordered completion")
    }
}
