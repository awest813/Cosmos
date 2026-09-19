import Foundation

/// Describe the operation, not its implementation or an unverified game process state.
enum CosmosOperationLabel {
    static func title(script: String, arguments: [String]) -> String {
        switch script {
        case "detect_steam_games.command":
            return arguments.contains("--list") || arguments.contains("--verify")
                ? "Checking installed games…" : "Updating your game library…"
        case "import_game.command": return "Importing games…"
        case "install_cosmos.command": return "Installing Cosmos launchers…"
        case "profile.command": return "Updating game settings…"
        case "repair.command": return "Checking and repairing your game environment…"
        case "bottle.command": return "Updating Windows environment…"
        case "cosmosdb.command": return "Checking compatibility…"
        case "run.command":
            switch arguments.first {
            case "--download-component": return "Downloading components…"
            case "--build-spockd3d9": return "Building SpockD3D9…"
            case "--game", "--profile": return "Starting your game…"
            case "--steam": return "Opening Steam…"
            case "--setup-steam": return "Preparing Windows environment…"
            case "--install-steam": return "Installing Steam…"
            case "--install-rosetta": return "Installing Rosetta…"
            case "--check-update": return "Checking for updates…"
            case "--logs": return "Opening logs…"
            case "--compat-check": return "Checking compatibility…"
            case "--status", "--verify-steam": return "Checking your setup…"
            default: return "Updating Cosmos…"
            }
        default: return "Working…"
        }
    }
}
