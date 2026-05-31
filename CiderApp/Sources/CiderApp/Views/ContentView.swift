import SwiftUI

/// Root view with a sidebar for the four main sections.
struct ContentView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case setup    = "Setup"
        case library  = "Library"
        case launchers = "Launchers"
        case repair   = "Repair"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .setup:     return "checkmark.circle"
            case .library:   return "books.vertical"
            case .launchers: return "apps.iphone"
            case .repair:    return "wrench.and.screwdriver"
            }
        }
    }

    @State private var selection: Tab = .setup

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $selection) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selection {
            case .setup:     SetupStatusView()
            case .library:   LibraryView()
            case .launchers: LaunchersView()
            case .repair:    RepairView()
            }
        }
        .navigationTitle("Cider")
    }
}
