import Foundation

/// Result of a background `list --json` detection pass.
enum GameListResult<Game: Equatable>: Equatable {
    case success([Game])
    case failed(exitCode: Int32)
    case timedOut
    case scriptUnavailable
    case parseFailed

    var games: [Game]? {
        if case .success(let games) = self { return games }
        return nil
    }
}
