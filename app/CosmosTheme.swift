import AppKit
import SwiftUI

// MARK: - Brand palette

extension Color {
    /// Deep indigo — primary brand accent.
    static let cosmosPrimary = Color(red: 0.18, green: 0.07, blue: 0.56)
    /// Bright violet — gradients and highlights.
    static let cosmosBright = Color(red: 0.58, green: 0.18, blue: 0.90)
    /// Galaxy disc fill in the logo mark.
    static let cosmosDark = Color(red: 0.08, green: 0.01, blue: 0.20)

    // MARK: Semantic surfaces (adapt to light / dark)

    static let cosmosSidebarBackground = Color.adaptive(
        light: NSColor(red: 0.97, green: 0.96, blue: 0.99, alpha: 1),
        dark: NSColor(red: 0.09, green: 0.05, blue: 0.14, alpha: 1)
    )

    static let cosmosContentBackground = Color.adaptive(
        light: NSColor(red: 0.99, green: 0.98, blue: 1.0, alpha: 1),
        dark: NSColor(red: 0.07, green: 0.04, blue: 0.11, alpha: 1)
    )

    static let cosmosCardFill = Color.adaptive(
        light: NSColor(red: 1, green: 1, blue: 1, alpha: 0.92),
        dark: NSColor(red: 0.12, green: 0.07, blue: 0.18, alpha: 0.85)
    )

    static let cosmosCardBorder = Color.adaptive(
        light: NSColor(red: 0.18, green: 0.07, blue: 0.56, alpha: 0.12),
        dark: NSColor(red: 0.58, green: 0.18, blue: 0.90, alpha: 0.18)
    )

    static let cosmosTileFill = Color.adaptive(
        light: NSColor(white: 0, alpha: 0.04),
        dark: NSColor(white: 1, alpha: 0.05)
    )

    static let cosmosConsoleBackground = Color.adaptive(
        light: NSColor(red: 0.12, green: 0.08, blue: 0.20, alpha: 1),
        dark: NSColor(red: 0.05, green: 0.02, blue: 0.10, alpha: 1)
    )

    static let cosmosConsoleText = Color.adaptive(
        light: NSColor(red: 0.88, green: 0.84, blue: 0.98, alpha: 1),
        dark: NSColor(red: 0.85, green: 0.80, blue: 1.0, alpha: 1)
    )

    // MARK: Semantic status colors

    /// Single source of truth for success / warning / danger states across the
    /// dashboard (status rows, command banners, compatibility badges). Centralized
    /// so status semantics stay consistent and can be retuned in one place.
    static let cosmosSuccess = Color.green
    static let cosmosWarning = Color.orange
    static let cosmosDanger = Color.red
    /// Shared informational accent for non-blocking guidance and ready states.
    static let cosmosInfo = Color.accentColor

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        }))
    }
}

// MARK: - Typography

enum CosmosTypography {
    static let heroTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    static let sectionTitle = Font.title3.weight(.semibold)
    static let captionLabel = Font.caption.weight(.semibold)
    static let monoBody = Font.system(.body, design: .monospaced)
}

// MARK: - Gradients

enum CosmosGradients {
    static let primaryButton = LinearGradient(
        colors: [Color.cosmosBright, Color.cosmosPrimary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroTitle = LinearGradient(
        colors: [Color.cosmosBright, Color.cosmosPrimary],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let sidebarHeader = LinearGradient(
        colors: [
            Color.cosmosPrimary.opacity(0.06),
            Color.cosmosBright.opacity(0.03),
            Color.clear,
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - View modifiers

struct CosmosSidebarBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.cosmosSidebarBackground)
    }
}

struct CosmosContentBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color.cosmosContentBackground
                    RadialGradient(
                        colors: [
                            Color.cosmosBright.opacity(0.04),
                            Color.clear,
                        ],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 520
                    )
                }
            )
    }
}

extension View {
    func cosmosSidebarBackground() -> some View {
        modifier(CosmosSidebarBackground())
    }

    func cosmosContentBackground() -> some View {
        modifier(CosmosContentBackground())
    }
}
