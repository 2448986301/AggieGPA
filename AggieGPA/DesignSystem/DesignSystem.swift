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
        /// Presses, menus, inline validation, and lightweight feedback.
        static let quick = Animation.easeOut(duration: 0.18)
        /// List insertion, removal, and ordinary content replacement.
        static let standard = Animation.smooth(duration: 0.32)
        /// Important grade changes. Critically damped so recorded scores never feel celebratory.
        static let emphasized = Animation.spring(duration: 0.40, bounce: 0)
        /// Direct-manipulation controls may inherit velocity, but should not overshoot.
        static let interactive = Animation.interactiveSpring(response: 0.30, dampingFraction: 1)
        /// A short non-spatial alternative that retains understandable state feedback.
        static let reduced = Animation.easeInOut(duration: 0.16)

        static func quick(reduceMotion: Bool) -> Animation {
            reduceMotion ? reduced : quick
        }

        static func standard(reduceMotion: Bool) -> Animation {
            reduceMotion ? reduced : standard
        }

        static func emphasized(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : emphasized
        }

        static func feedbackTransition(reduceMotion: Bool) -> AnyTransition {
            reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
        }
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
    let radius: CGFloat

    func body(content: Content) -> some View {
        let fillOpacity = reduceTransparency ? 1.0 : (colorScheme == .dark ? 0.94 : 0.90)

        content
            .background(
                Color(.secondarySystemGroupedBackground).opacity(fillOpacity),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
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

    func contentSurface(radius: CGFloat = DesignSystem.Radius.section) -> some View {
        modifier(ContentSurfaceModifier(radius: radius))
    }
}

enum LiquidGlassButtonShape {
    case capsule
    case circle
    case roundedRectangle(CGFloat)

    var shape: AnyShape {
        switch self {
        case .capsule:
            AnyShape(Capsule())
        case .circle:
            AnyShape(Circle())
        case .roundedRectangle(let radius):
            AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

/// Keeps the label above the glass material so the pressed highlight can never mask text.
///
/// The glass surface still responds physically: it compresses while held, then settles with
/// a short spring. Reduce Motion keeps the state change but removes the elastic deformation.
struct LiquidGlassPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let shape: LiquidGlassButtonShape
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, shape == .circle ? 9 : 14)
            .padding(.vertical, 8)
            .background {
                Color.clear
                    .glassEffect(
                        tint.map { Glass.clear.tint($0) } ?? .clear,
                        in: shape.shape
                    )
            }
            .contentShape(shape.shape)
            .scaleEffect(
                x: configuration.isPressed && !reduceMotion ? 0.97 : 1,
                y: configuration.isPressed && !reduceMotion ? 0.92 : 1
            )
            .animation(
                reduceMotion
                    ? DesignSystem.Motion.reduced
                    : .interactiveSpring(response: 0.24, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}

extension LiquidGlassButtonShape: Equatable {}

struct AggieFeedbackBanner<Action: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    let systemImage: String
    let action: Action

    init(
        _ title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        systemImage: String,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.action = action()
    }

    var body: some View {
        Group {
            if reduceTransparency {
                bannerContent
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    )
            } else {
                bannerContent
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .strokeBorder(.primary.opacity(reduceTransparency ? 0.14 : 0.06), lineWidth: 1)
        }
        .shadow(color: DesignSystem.softShadow, radius: 12, y: 4)
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .containerShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var bannerContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSystem.Spacing.small) {
                feedbackLabel
                Spacer(minLength: DesignSystem.Spacing.small)
                action
            }
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                feedbackLabel
                action.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: DesignSystem.Radius.compact))
        .controlSize(.regular)
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
        .frame(maxWidth: 540)
    }

    private var feedbackLabel: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(DesignSystem.ColorToken.gold)
        }
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
