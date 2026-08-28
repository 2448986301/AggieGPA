import SwiftUI

struct ScoreImpactPresentation: Identifiable {
    let id = UUID()
    let itemID: UUID
    let itemTitle: String
    let change: RecordedScoreChange
    let currentGradeBefore: Decimal?
    let currentGradeAfter: Decimal?
    let projectedFinalBefore: Decimal?
    let projectedFinalAfter: Decimal?
    let projectedLetterBefore: GradeLetter?
    let projectedLetterAfter: GradeLetter?
    let termGPABefore: Decimal?
    let termGPAAfter: Decimal?
}

struct ScoreImpactBanner: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.locale) private var locale
    let impact: ScoreImpactPresentation
    let undo: () -> Void
    let dismiss: () -> Void
    @State private var showsDetails = false

    private var usesOpaqueSurface: Bool {
        reduceTransparency || colorSchemeContrast == .increased
    }

    var body: some View {
        Group {
            if usesOpaqueSurface {
                content
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    )
            } else {
                content
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .strokeBorder(.primary.opacity(usesOpaqueSurface ? 0.20 : 0.08), lineWidth: 1)
        }
        .shadow(color: DesignSystem.softShadow, radius: 14, y: 5)
        .containerShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous))
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .frame(maxWidth: 600)
        .accessibilityIdentifier("scoreImpactBanner")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Label("Score Impact", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass(.regular.interactive()))
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(Text(verbatim: AppLocalization.string("Dismiss score impact", locale: locale)))
            }

            HStack(spacing: 4) {
                Text(impact.itemTitle)
                Text("Score saved")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if currentGradeChanged {
                changeRow(
                    "Current course grade",
                    before: formattedPercent(impact.currentGradeBefore),
                    after: formattedPercent(impact.currentGradeAfter)
                )
            }
            if projectedFinalChanged {
                changeRow(
                    "Projected final",
                    before: projectedFinal(impact.projectedFinalBefore, impact.projectedLetterBefore),
                    after: projectedFinal(impact.projectedFinalAfter, impact.projectedLetterAfter)
                )
            }
            if termGPAChanged {
                changeRow(
                    "Estimated term GPA",
                    before: DecimalFormatters.string(impact.termGPABefore),
                    after: DecimalFormatters.string(impact.termGPAAfter)
                )
            }

            if showsDetails {
                Divider()
                Text("The recorded score changed this estimate. Your official course grade was not changed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            HStack {
                Button(showsDetails ? "Hide Details" : "Details") {
                    withAnimation(DesignSystem.Motion.quick(reduceMotion: reduceMotion)) {
                        showsDetails.toggle()
                    }
                }
                .buttonStyle(.glass(.regular.interactive()))
                .buttonBorderShape(.capsule)
                Spacer()
                Button(action: undo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .accessibilityIdentifier("undoRecordedScoreButtonLabel")
                }
                    .buttonStyle(.glass(.regular.interactive()))
                    .buttonBorderShape(.capsule)
                    .fontWeight(.semibold)
                    .accessibilityLabel(Text(verbatim: AppLocalization.string("Undo", locale: locale)))
                    .accessibilityIdentifier("undoRecordedScoreButton")
            }
        }
        .padding(DesignSystem.Spacing.medium)
    }

    private func changeRow(_ title: LocalizedStringKey, before: String, after: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(before)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(after)
                .fontWeight(.semibold)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private var currentGradeChanged: Bool {
        impact.currentGradeBefore != impact.currentGradeAfter
    }

    private var projectedFinalChanged: Bool {
        impact.projectedFinalBefore != impact.projectedFinalAfter
            || impact.projectedLetterBefore != impact.projectedLetterAfter
    }

    private var termGPAChanged: Bool {
        impact.termGPABefore != impact.termGPAAfter
    }

    private func formattedPercent(_ value: Decimal?) -> String {
        value.map { "\(compact($0))%" } ?? "—"
    }

    private func projectedFinal(_ value: Decimal?, _ letter: GradeLetter?) -> String {
        let percentage = formattedPercent(value)
        return letter.map { "\(percentage) · \($0.rawValue)" } ?? percentage
    }
}
