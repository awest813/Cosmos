import Combine
import Foundation

/// Shared app flags for menu commands and cross-view state.
final class CosmosAppState: ObservableObject {
    static let shared = CosmosAppState()

    private static let setupCompleteKey = "CosmosSetupComplete"

    @Published private(set) var isSetupComplete: Bool

    private init() {
        isSetupComplete = UserDefaults.standard.bool(forKey: Self.setupCompleteKey)
    }

    func updateSetupComplete(_ complete: Bool) {
        guard isSetupComplete != complete else { return }
        isSetupComplete = complete
        UserDefaults.standard.set(complete, forKey: Self.setupCompleteKey)
    }
}
