import Foundation

/// Describe the operation, not its implementation or an unverified game process state.
enum CosmosOperationLabel {
    static func title(script: String, arguments: [String]) -> String {
        switch script {
        case "scripts/install_program.command": return "Installing your Windows game…"
        case "detect_steam_games.command":
            return arguments.contains("--list") || arguments.contains("--verify")
                ? "Checking installed games…" : "Updating your game library…"
        case "import_game.command": return "Importing games…"
        case "install_cosmos.command": return "Installing Cosmos launchers…"
        case "profile.command": return "Updating game settings…"
        case "repair.command": return "Checking and repairing your game environment…"
        case "bottle.command": return "Updating Windows environment…"
        case "port.command":
            switch arguments.first {
            case "launch": return "Opening your port…"
            case "build": return "Making a Mac app…"
            case "create": return "Creating a port…"
            case "delete": return "Removing a port…"
            default: return "Updating ports…"
            }
        case "cosmosdb.command": return "Checking compatibility…"
        case "scripts/build_highball.command": return "Building Highball…"
        case "scripts/build_vermut.command": return "Building Vermut…"
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
            case "--gptk-layout-status": return "Checking the D3DMetal layout…"
            case "--gptk-layout": return "Installing the D3DMetal layout…"
            case "--gptk-layout-revert": return "Removing the D3DMetal layout…"
            case "--battlenet-seed": return "Updating Battle.net…"
            case "--opengl-status": return "Checking the OpenGL fix…"
            case "--opengl-patch": return "Applying the OpenGL fix…"
            case "--opengl-revert": return "Removing the OpenGL fix…"
            default: return "Updating Cosmos…"
            }
        default: return "Working…"
        }
    }
}
