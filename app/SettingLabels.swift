import Foundation

/// Maps steam.conf / graphics keys to user-facing labels for save confirmations.
enum SettingLabels {
    static func displayName(for key: String) -> String {
        switch key {
        case "COSMOS_BACKEND": return "Graphics backend"
        case "WINDOWS_VERSION": return "Windows version"
        case "WINE_RETINA_MODE": return "Retina mode"
        case "COSMOS_DETACH": return "Detach Steam from Terminal"
        case "COSMOS_STEAM_SILENT": return "Unattended Steam install"
        case "COSMOS_STEAM_NATIVE_SCAN": return "Scan native Steam libraries"
        case "COSMOS_DXMT_CHANNEL": return "DXMT channel"
        case "COSMOS_MVK_PRESET": return "MoltenVK preset"
        case "COSMOS_METALFX": return "MetalFX"
        case "GPTK_PATH": return "Game Porting Toolkit path"
        case "SPOCK_D3D9_PATH": return "SpockD3D9 path"
        case "COSMOS_SYNC_MODE": return "Thread sync mode"
        default:
            return key
                .replacingOccurrences(of: "_", with: " ")
                .lowercased()
                .capitalized
        }
    }

    static func backendDisplayName(_ backend: String) -> String {
        switch backend {
        case "recommended": return "Recommended"
        case "dxmt": return "DXMT"
        case "d3dmetal": return "D3DMetal (GPTK)"
        case "dxvk": return "DXVK (experimental)"
        case "wined3d": return "WineD3D"
        case "spockd3d9": return "SpockD3D9 (experimental)"
        default: return backend
        }
    }

    /// Short helper shown under backend pickers.
    static func backendCaption(_ backend: String) -> String? {
        switch backend {
        case "recommended":
            return "Uses the profile's recommended backend — DXMT by default, or D3DMetal when GPTK_PATH is set."
        case "dxmt":
            return "D3D10/11 → Metal. D3D9 still uses WineD3D unless you switch to SpockD3D9."
        case "d3dmetal":
            return "DX11/12 → Metal via Apple's Game Porting Toolkit. Requires GPTK_PATH."
        case "dxvk":
            return "Experimental D3D9/10/11 → Vulkan. Needs DXVK_PATH and MoltenVK."
        case "wined3d":
            return "Wine's built-in D3D → OpenGL. Slowest, broadest compatibility."
        case "spockd3d9":
            return "Experimental D3D9 → Vulkan plus DXMT for D3D10/11. Requires SPOCK_D3D9_PATH."
        default:
            return nil
        }
    }

    static func windowsDisplayName(_ version: String) -> String {
        version.isEmpty ? "Wine default" : version
    }

    static func savedMessage(for key: String, appliesToSteam: Bool = true) -> String {
        let label = displayName(for: key)
        if appliesToSteam {
            return "\(label) saved. Changes apply on the next Steam or game launch."
        }
        return "\(label) saved. Changes apply on the next launch."
    }
}
