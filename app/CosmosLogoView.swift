import SwiftUI

// MARK: - Brand colours
extension Color {
    /// Deep indigo that matches the "Cosmos" wordmark in the logo.
    static let cosmosPrimary = Color(red: 0.18, green: 0.07, blue: 0.56)
    /// Bright violet used for the swirling light streaks.
    static let cosmosBright  = Color(red: 0.58, green: 0.18, blue: 0.90)
    /// Darker background fill for the galaxy disc.
    static let cosmosDark    = Color(red: 0.08, green: 0.01, blue: 0.20)
}

// MARK: - Logo mark
/// A SwiftUI recreation of the Cosmos galaxy / black-hole logo mark.
struct CosmosLogoMark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            // ── Galaxy disc background ───────────────────────────────────────
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.28, green: 0.06, blue: 0.55),
                            Color.cosmosDark
                        ],
                        center: UnitPoint(x: 0.42, y: 0.48),
                        startRadius: size * 0.05,
                        endRadius: size * 0.80
                    )
                )
                .frame(width: size * 1.52, height: size)
                .shadow(color: Color.cosmosBright.opacity(0.55), radius: size * 0.18)

            // ── Swirling arc 1 (outer, wide) ────────────────────────────────
            Circle()
                .trim(from: 0.05, to: 0.58)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.cosmosBright.opacity(0.0), location: 0.0),
                            .init(color: Color.cosmosBright.opacity(0.85), location: 0.5),
                            .init(color: Color.cosmosBright.opacity(0.0), location: 1.0)
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round)
                )
                .frame(width: size * 0.76, height: size * 0.76)
                .rotationEffect(.degrees(-25))

            // ── Swirling arc 2 (mid, narrower) ──────────────────────────────
            Circle()
                .trim(from: 0.10, to: 0.62)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(red: 0.85, green: 0.45, blue: 1.0).opacity(0.0), location: 0.0),
                            .init(color: Color(red: 0.85, green: 0.45, blue: 1.0).opacity(0.95), location: 0.45),
                            .init(color: Color(red: 0.85, green: 0.45, blue: 1.0).opacity(0.0), location: 1.0)
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: size * 0.04, lineCap: .round)
                )
                .frame(width: size * 0.58, height: size * 0.58)
                .rotationEffect(.degrees(130))

            // ── Inner glowing ring ───────────────────────────────────────────
            Circle()
                .trim(from: 0.15, to: 0.72)
                .stroke(
                    Color(red: 0.78, green: 0.36, blue: 1.0).opacity(0.9),
                    style: StrokeStyle(lineWidth: size * 0.032, lineCap: .round)
                )
                .frame(width: size * 0.44, height: size * 0.44)
                .rotationEffect(.degrees(205))
                .blur(radius: 0.8)

            // ── Faint outer sweep (tail) ─────────────────────────────────────
            Circle()
                .trim(from: 0.0, to: 0.35)
                .stroke(
                    Color.cosmosBright.opacity(0.35),
                    style: StrokeStyle(lineWidth: size * 0.025, lineCap: .round)
                )
                .frame(width: size * 0.88, height: size * 0.88)
                .rotationEffect(.degrees(-80))
                .blur(radius: 1.0)

            // ── Star sparkles (fixed opacities; stable across redraws) ───────
            ForEach(CosmosLogoMark.sparkleOffsets, id: \.point.x) { sparkle in
                Circle()
                    .fill(Color.white.opacity(sparkle.opacity))
                    .frame(width: size * 0.022, height: size * 0.022)
                    .offset(x: sparkle.point.x * size, y: sparkle.point.y * size)
            }

            // ── Central black hole ───────────────────────────────────────────
            ZStack {
                Circle()
                    .fill(Color.cosmosBright.opacity(0.45))
                    .frame(width: size * 0.28, height: size * 0.28)
                    .blur(radius: size * 0.06)

                Circle()
                    .fill(Color.black)
                    .frame(width: size * 0.22, height: size * 0.22)
            }
        }
        .frame(width: size * 1.52, height: size)
        .clipShape(Ellipse())
    }

    // Fixed positions and opacities so sparkles are stable across redraws.
    private static let sparkleOffsets: [(point: CGPoint, opacity: Double)] = [
        (CGPoint(x:  0.28, y: -0.30), 0.80),
        (CGPoint(x: -0.30, y: -0.18), 0.65),
        (CGPoint(x:  0.35, y:  0.08), 0.75),
        (CGPoint(x: -0.22, y:  0.28), 0.60),
        (CGPoint(x:  0.12, y:  0.35), 0.70),
        (CGPoint(x: -0.40, y:  0.05), 0.55),
        (CGPoint(x:  0.42, y: -0.10), 0.85),
        (CGPoint(x: -0.08, y: -0.38), 0.65)
    ]
}

// MARK: - Full logo (mark + wordmark)
struct CosmosLogo: View {
    var markSize: CGFloat = 72

    var body: some View {
        VStack(spacing: markSize * 0.18) {
            CosmosLogoMark(size: markSize)

            Text("Cosmos")
                .font(.system(size: markSize * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(Color.cosmosPrimary)
        }
    }
}

#if DEBUG
#Preview("Logo mark") {
    CosmosLogoMark(size: 100)
        .padding(40)
}

#Preview("Full logo") {
    CosmosLogo(markSize: 100)
        .padding(40)
}
#endif
