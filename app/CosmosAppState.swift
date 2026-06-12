import Combine
import Foundation

/// Shared app flags for menu commands and cross-view state.
final class CosmosAppState: ObservableObject {
    static let shared = CosmosAppState()

    private static let setupCompleteKey = "CosmosSetupComplete"

    @Published private(set) var isSetupComplete: Bool
    @Published private(set) var canAcceptCommands: Bool = true
    @Published private(set) var canLaunchSelectedProfile: Bool = false

    private init() {
        isSetupComplete = UserDefaults.standard.bool(forKey: Self.setupCompleteKey)
    }

    func updateSetupComplete(_ complete: Bool) {
        guard isSetupComplete != complete else { return }
        isSetupComplete = complete
        UserDefaults.standard.set(complete, forKey: Self.setupCompleteKey)
    }

    func updateCommandAvailability(canAccept: Bool, canLaunchSelected: Bool) {
        if canAcceptCommands != canAccept {
            canAcceptCommands = canAccept
        }
        if canLaunchSelectedProfile != canLaunchSelected {
            canLaunchSelectedProfile = canLaunchSelected
        }
    }
}
