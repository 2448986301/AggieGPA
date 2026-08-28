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

    enum Typography {
        static let heroNumber = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let pageTitle = Font.title.bold()
        static let sectionTitle = Font.title3.bold()
        static let metric = Font.title2.bold().monospacedDigit()
        static let supporting = Font.subheadline
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

/// The 2.0 hierarchy starts with type and spacing. This container deliberately adds
/// no background so data can remain the interface instead of becoming another card.
struct AppSection<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(DesignSystem.Typography.sectionTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A contextual surface, not a default wrapper. Use only when grouping or focus is
/// essential; AppSection remains the default for ordinary data.
struct AppCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DesignSystem.Spacing.medium)
            .contentSurface(radius: DesignSystem.Radius.section)
    }
}

struct AppInteractiveRow<Content: View, Trailing: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing

    init(@ViewBuilder content: () -> Content, @ViewBuilder trailing: () -> Trailing) {
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.small) {
            content
            Spacer(minLength: DesignSystem.Spacing.small)
            trailing
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct AppGlassControl<Label: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let action: () -> Void
    @ViewBuilder let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Group {
            if reduceTransparency || colorSchemeContrast == .increased {
                Button(action: action) { label }
                    .buttonStyle(.bordered)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.glass(.regular.interactive()))
            }
        }
        .buttonBorderShape(.capsule)
        .contentShape(Capsule())
    }
}

/// A quiet, opaque-enough content surface for grouped information.
///
/// Liquid Glass is reserved for floating controls and navigation chrome. This keeps stacked
/// content readable over `CampusBackground`, including with Reduce Transparency enabled.
struct ContentSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme
    let radius: CGFloat

    func body(content: Content) -> some View {
        let usesOpaqueSurface = reduceTransparency || colorSchemeContrast == .increased
        let fillOpacity = usesOpaqueSurface ? 1.0 : (colorScheme == .dark ? 0.94 : 0.90)

        content
            .background(
                Color(.secondarySystemGroupedBackground).opacity(fillOpacity),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.primary.opacity(usesOpaqueSurface ? 0.20 : 0.06), lineWidth: 1)
            }
    }
}

private struct AggieInputSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let capsule: Bool
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    private var strokeOpacity: Double {
        reduceTransparency || colorSchemeContrast == .increased ? 0.22 : 0.09
    }

    func body(content: Content) -> some View {
        if capsule {
            content
                .textFieldStyle(.plain)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(minHeight: 44)
                .background(Color(.tertiarySystemFill), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.primary.opacity(strokeOpacity), lineWidth: 1)
                }
                .contentShape(Capsule())
        } else {
            content
                .textFieldStyle(.plain)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(minHeight: 44)
                .background(
                    Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: DesignSystem.Radius.compact, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.compact, style: .continuous)
                        .strokeBorder(.primary.opacity(strokeOpacity), lineWidth: 1)
                }
                .contentShape(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.compact, style: .continuous)
                )
        }
    }
}

struct CampusBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Group {
            if reduceTransparency || colorSchemeContrast == .increased {
                // A solid system surface keeps text and controls stable when
                // the user asks iOS to reduce transparency or increase contrast.
                Color(.systemGroupedBackground)
            } else {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [DesignSystem.ColorToken.navy, Color.black]
                        : [Color(.systemGroupedBackground), DesignSystem.ColorToken.ice.opacity(0.20)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(DesignSystem.ColorToken.gold.opacity(0.12))
                        .frame(width: 280, height: 280)
                        .blur(radius: 70)
                        .offset(x: 100, y: -100)
                }
            }
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

    /// A consistent continuous-corner field for forms placed on content surfaces.
    func roundedInputSurface() -> some View {
        modifier(
            AggieInputSurfaceModifier(
                capsule: false,
                horizontalPadding: DesignSystem.Spacing.small,
                verticalPadding: DesignSystem.Spacing.small
            )
        )
    }

    /// A compact numeric field whose interaction and visual boundary match a pill control.
    func capsuleInputSurface() -> some View {
        modifier(
            AggieInputSurfaceModifier(
                capsule: true,
                horizontalPadding: DesignSystem.Spacing.small,
                verticalPadding: DesignSystem.Spacing.small
            )
        )
    }
}

struct AggieFeedbackBanner<Action: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
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
            if reduceTransparency || colorSchemeContrast == .increased {
                bannerContent
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    )
            } else {
                bannerContent
                    .glassEffect(
                        .regular.tint(DesignSystem.ColorToken.gold.opacity(0.08)).interactive(),
                        in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .strokeBorder(.primary.opacity(reduceTransparency || colorSchemeContrast == .increased ? 0.20 : 0.06), lineWidth: 1)
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
        .buttonStyle(.glass(.regular.interactive()))
        .buttonBorderShape(.capsule)
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
    @Environment(\.locale) private var locale

    var body: some View {
        Label {
            Text(verbatim: AppLocalization.string("Unofficial student tool. Not affiliated with UC Davis.", locale: locale))
        } icon: {
            Image(systemName: "info.circle")
        }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text(verbatim: AppLocalization.string("Unofficial student tool. Not affiliated with U C Davis.", locale: locale)))
    }
}
