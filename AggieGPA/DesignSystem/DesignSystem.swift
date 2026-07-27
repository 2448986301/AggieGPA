import SwiftUI

enum DesignSystem {
    enum ColorToken {
        static let navy = Color(red: 0.035, green: 0.102, blue: 0.20)
        static let navyRaised = Color(red: 0.07, green: 0.16, blue: 0.28)
        static let gold = Color(red: 0.87, green: 0.65, blue: 0.22)
        static let ice = Color(red: 0.52, green: 0.83, blue: 0.98)
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
    }

    enum Spacing {
        static let xSmall: CGFloat = 6
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
    }

    enum Radius {
        static let compact: CGFloat = 12
        static let section: CGFloat = 16
        static let card: CGFloat = 20
        static let hero: CGFloat = 28
    }

    enum Motion {
        static let quick = 0.18
        static let standard = 0.32
        static let spring = Animation.spring(duration: 0.42, bounce: 0.16)
        /// The default for state-driven interface changes: smooth, immediate, and without overshoot.
        static let interfaceSpring = Animation.spring(duration: 0.4, bounce: 0)
    }

    static let softShadow = Color.black.opacity(0.12)
}

/// A quiet, opaque-enough content surface for grouped information.
///
/// Liquid Glass is reserved for floating controls and navigation chrome. This keeps stacked
/// content readable over `CampusBackground`, including with Reduce Transparency enabled.
struct ContentSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let fillOpacity = reduceTransparency ? 1.0 : (colorScheme == .dark ? 0.94 : 0.90)

        content
            .background(
                Color(.secondarySystemGroupedBackground).opacity(fillOpacity),
                in: RoundedRectangle(cornerRadius: DesignSystem.Radius.section, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.section, style: .continuous)
                    .strokeBorder(.primary.opacity(reduceTransparency ? 0.16 : 0.06), lineWidth: 1)
            }
    }
}

struct CampusBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [DesignSystem.ColorToken.navy, Color.black]
                : [Color(.systemGroupedBackground), DesignSystem.ColorToken.ice.opacity(0.20)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(DesignSystem.ColorToken.gold.opacity(reduceTransparency ? 0.04 : 0.12))
                .frame(width: 280, height: 280)
                .blur(radius: reduceTransparency ? 0 : 70)
                .offset(x: 100, y: -100)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Legacy compatibility for existing content cards.
    ///
    /// Content must never be translucent over another material. Liquid Glass is reserved for
    /// navigation chrome, floating primary actions, and brief status feedback; regular reading
    /// surfaces always use `contentSurface()`.
    @available(*, deprecated, message: "Use contentSurface() for content. Liquid Glass is reserved for floating chrome.")
    func glassCard(tint: Color? = nil, interactive: Bool = false) -> some View {
        contentSurface()
    }

    func contentSurface() -> some View {
        modifier(ContentSurfaceModifier())
    }
}

struct DisclaimerBanner: View {
    var body: some View {
        Label("Unofficial student tool. Not affiliated with UC Davis.", systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Unofficial student tool. Not affiliated with U C Davis.")
    }
}
