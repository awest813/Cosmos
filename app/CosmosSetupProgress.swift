/// Counts only setup steps that apply to the current Mac.
enum CosmosSetupProgress {
    static func fraction(
        needsRosetta: Bool,
        rosettaReady: Bool,
        cosmosInstalled: Bool,
        prefixReady: Bool,
        steamInstalled: Bool,
        hasGames: Bool
    ) -> Double {
        var steps = [cosmosInstalled, prefixReady, steamInstalled, hasGames]
        if needsRosetta { steps.append(rosettaReady) }
        return Double(steps.filter { $0 }.count) / Double(steps.count)
    }
}
