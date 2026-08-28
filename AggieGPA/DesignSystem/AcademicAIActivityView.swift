import SwiftUI
import ThinkingOrbsKit

/// Optional deterministic overrides for previews and snapshot tests; production
/// rendering remains driven by the system accessibility settings by default.
struct AcademicAIActivityAccessibilityOverrides: Equatable, Sendable {
    var reduceMotion: Bool?
    var reduceTransparency: Bool?

    init(reduceMotion: Bool? = nil, reduceTransparency: Bool? = nil) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
    }
}

private struct AcademicAIActivityAccessibilityOverridesKey: EnvironmentKey {
    static let defaultValue = AcademicAIActivityAccessibilityOverrides()
}

extension EnvironmentValues {
    var academicAIActivityAccessibilityOverrides: AcademicAIActivityAccessibilityOverrides {
        get { self[AcademicAIActivityAccessibilityOverridesKey.self] }
        set { self[AcademicAIActivityAccessibilityOverridesKey.self] = newValue }
    }
}

/// The small set of indeterminate AI activities that are meaningful to a student.
/// Feature views request one of these states; the upstream orb state stays an
/// implementation detail of this app-owned boundary.
enum AcademicAIActivityState: String, Equatable, Sendable {
    case preparingModel
    case searchingSyllabus
    case reasoningSyllabus
    case listening
    case transcribing
    case composingExplanation
    case weavingSections
    case shapingResult

    var orbState: OrbState {
        switch self {
        case .preparingModel: .working
        case .searchingSyllabus: .searching
        case .reasoningSyllabus: .solving
        case .listening, .transcribing: .listening
        case .composingExplanation: .composing
        case .weavingSections: .weaving
        case .shapingResult: .shaping
        }
    }

    var localizationKey: String {
        switch self {
        case .preparingModel: "Preparing Model"
        case .searchingSyllabus: "Searching Syllabus"
        case .reasoningSyllabus: "Analyzing Syllabus"
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .composingExplanation: "Preparing Explanation"
        case .weavingSections: "Combining Sections"
        case .shapingResult: "Preparing Result"
        }
    }

    var statusKey: LocalizedStringKey { LocalizedStringKey(localizationKey) }
}

/// A compact, non-blocking activity capsule for genuine indeterminate work.
/// The capsule is the only material surface; the orb is never placed inside a
/// second card or a nested loading panel.
struct AcademicAIActivityView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.academicAIActivityAccessibilityOverrides) private var accessibilityOverrides

    let state: AcademicAIActivityState
    var allowsCancellation = false
    var onCancel: (() -> Void)?
    var onPressChanged: ((Bool) -> Void)?

    // Expansion is a press affordance, not a second navigation state. The
    // long-press pressing callback keeps the larger surface tied to the
    // finger-down interval, so a later analysis state can never inherit it
    // accidentally.
    @State private var isPressing = false
    @State private var visibleActivityState: AcademicAIActivityState
    @State private var outgoingActivityState: AcademicAIActivityState?
    @State private var pendingActivityState: AcademicAIActivityState?
    @State private var isRollingActivity = false
    @State private var activityTransitionTask: Task<Void, Never>?
    @State private var showsExpandedContent = false
    @State private var pressActivationTask: Task<Void, Never>?

    init(
        state: AcademicAIActivityState,
        allowsCancellation: Bool = false,
        onCancel: (() -> Void)? = nil,
        onPressChanged: ((Bool) -> Void)? = nil
    ) {
        self.state = state
        self.allowsCancellation = allowsCancellation
        self.onCancel = onCancel
        self.onPressChanged = onPressChanged
        _visibleActivityState = State(initialValue: state)
    }

    private var effectiveReduceMotion: Bool {
        accessibilityOverrides.reduceMotion ?? reduceMotion
    }

    private var effectiveReduceTransparency: Bool {
        accessibilityOverrides.reduceTransparency ?? reduceTransparency
    }

    private var usesHighContrastSurface: Bool {
        colorSchemeContrast == .increased
    }

    private var localizedStatusText: String {
        AppLocalization.string(visibleActivityState.localizationKey, locale: locale)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: { }) {
                activitySurface
            }
            .buttonStyle(
                AcademicAIActivityPressStyle { pressing in
                    updatePressActivation(for: pressing)
                }
            )
            // Keep the press surface itself discoverable so assistive
            // technology and XCTest can reach the same visible hit target.
            // It is not a tap action; the hint explains that the useful
            // affordance is press-and-hold expansion.
            .accessibilityLabel(Text(verbatim: localizedStatusText))
            .accessibilityHint(Text(verbatim: AppLocalization.string("Press and hold for details", locale: locale)))
            .accessibilityAction(named: Text(verbatim: isPressing
                ? AppLocalization.string("Hide Details", locale: locale)
                : AppLocalization.string("Show Details", locale: locale))) {
                withAnimation(
                    effectiveReduceMotion
                        ? DesignSystem.Motion.reduced
                        : DesignSystem.Motion.interactive
                ) {
                    isPressing.toggle()
                }
            }
            .accessibilityRemoveTraits(.isButton)
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("academicAIActivityCapsule")

            cancelButton
                .padding(.top, isPressing ? 12 : 8)
                // The visible compact xmark is part of the centered content
                // track below. Keep its transparent 44pt hit target aligned
                // with that slot instead of pinning it to the capsule edge.
                .padding(.trailing, isPressing ? 16 : 2)
        }
        .accessibilityElement(children: .contain)
        .onChange(of: isPressing) { _, pressing in
            updateExpandedContent(for: pressing)
            onPressChanged?(pressing)
        }
        .onAppear {
            guard visibleActivityState != state else { return }
            visibleActivityState = state
        }
        .onChange(of: state) { _, nextState in
            beginActivityTransition(to: nextState)
        }
        .onDisappear {
            activityTransitionTask?.cancel()
            pressActivationTask?.cancel()
        }
        .animation(
            effectiveReduceMotion
                ? DesignSystem.Motion.reduced
                : expansionAnimation,
            value: isPressing
        )
    }

    /// One uninterrupted material surface grows from the compact capsule into
    /// the held detail view. Keeping the glass alive across both states avoids
    /// the white compositing flash produced by cross-fading two glass layers.
    private var activitySurface: some View {
        let shape = RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)

        return ZStack {
            compactActivity
                .opacity(showsExpandedContent ? 0 : 1)
                .scaleEffect(showsExpandedContent ? 0.985 : 1)
                .animation(contentHandoffAnimation, value: showsExpandedContent)
                .accessibilityHidden(isPressing)

            expandedActivity
                .opacity(showsExpandedContent ? 1 : 0)
                .scaleEffect(showsExpandedContent ? 1 : 0.985)
                .animation(contentHandoffAnimation, value: showsExpandedContent)
                .accessibilityHidden(!isPressing)

            if isPressing {
                Color.clear
                    .accessibilityIdentifier("academicAIActivityExpanded")
            }
        }
        .frame(width: surfaceWidth, height: surfaceHeight)
        .foregroundStyle(compactForeground)
        .background {
            surfaceBackground(in: shape)
        }
        .overlay {
            shape.strokeBorder(
                compactForeground.opacity(
                    effectiveReduceTransparency || colorSchemeContrast == .increased ? 0.22 : 0.16
                ),
                lineWidth: 1
            )
        }
        .shadow(
            color: .black.opacity(isPressing ? 0.11 : 0.08),
            radius: isPressing ? 14 : 9,
            y: isPressing ? 5 : 3
        )
        .clipShape(shape)
        .contentShape(shape)
    }

    private var compactActivity: some View {
        ZStack {
            if let outgoingActivityState {
                compactContent(for: outgoingActivityState)
                    .offset(y: effectiveReduceMotion ? 0 : (isRollingActivity ? -compactTransitionDistance : 0))
                    .opacity(isRollingActivity ? 0 : 1)
                    .accessibilityHidden(true)
            }

            compactContent(for: visibleActivityState)
                .offset(
                    y: effectiveReduceMotion
                        ? 0
                        : (outgoingActivityState == nil || isRollingActivity ? 0 : compactTransitionDistance)
                )
                .opacity(outgoingActivityState == nil || isRollingActivity ? 1 : 0)
        }
        .frame(width: compactWidth, height: compactCapsuleHeight)
        .clipped()
        .contentShape(Capsule())
    }

    private var expandedActivity: some View {
        VStack(spacing: DesignSystem.Spacing.small) {
            Color.clear
                .frame(height: 28)

            ThinkingOrb(state: visibleActivityState.orbState, size: .px64, theme: .auto, displaySize: 76)
                .accessibilityHidden(true)

            AcademicAIActivityRollingContent(
                state: visibleActivityState,
                displaySize: 0,
                font: .headline,
                includesOrb: false,
                effectiveReduceMotion: effectiveReduceMotion
            )

            Text(verbatim: AppLocalization.string("AI Activity Detail", locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .frame(width: expandedWidth, height: expandedHeight)
    }

    @ViewBuilder
    private var cancelButton: some View {
        if allowsCancellation, let onCancel {
            Button(action: onCancel) {
                if isPressing {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                } else {
                    // The compact capsule draws the visible close symbol in
                    // each rolling peer. This transparent button keeps the
                    // actual action and its 44-point hit target outside the
                    // press button, avoiding nested interactive controls.
                    Color.clear
                }
            }
            .buttonStyle(.plain)
            // The hit target belongs to the Button itself. Applying the
            // frame only to the image leaves the accessibility element at
            // the symbol's intrinsic size on iOS.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(Text(verbatim: AppLocalization.string("Cancel", locale: locale)))
            .accessibilitySortPriority(0)
        }
    }

    private var rollingAnimation: Animation {
        // A critically damped spring preserves the rolling direction without
        // overshoot. State changes are not momentum gestures, so bounce would
        // read as latency or a compositing glitch rather than physicality.
        .interactiveSpring(response: 0.42, dampingFraction: 1, blendDuration: 0.08)
    }

    private var expansionAnimation: Animation {
        .interactiveSpring(response: 0.36, dampingFraction: 1, blendDuration: 0.08)
    }

    private var contentHandoffAnimation: Animation {
        // The two content arrangements cross-fade on one persistent glass
        // surface. This keeps visual weight continuous and avoids an empty,
        // pale frame while the capsule changes shape.
        effectiveReduceMotion ? DesignSystem.Motion.reduced : .easeInOut(duration: 0.14)
    }

    private var compactWidth: CGFloat {
        // Keep the reference-sized capsule for normal text. At accessibility
        // sizes, give the status enough room to remain a complete phrase
        // instead of reducing it to an ellipsis; the larger footprint is a
        // Dynamic Type adaptation, not a change to the normal product scale.
        if dynamicTypeSize >= .accessibility1 {
            return allowsCancellation ? 350 : 318
        }
        return allowsCancellation ? 232 : 204
    }

    private var compactTextMaxWidth: CGFloat {
        if dynamicTypeSize >= .accessibility1 {
            return 250
        }
        return allowsCancellation ? 132 : 148
    }

    private var compactCancelVisualSlotWidth: CGFloat {
        allowsCancellation ? 24 : 0
    }

    private var compactContentWidth: CGFloat {
        let orbWidth: CGFloat = 36
        let textWidth = compactTextMaxWidth
        let cancelWidth = allowsCancellation ? compactCancelVisualSlotWidth : 0
        let spacingCount = allowsCancellation ? 2 : 1
        return orbWidth + textWidth + cancelWidth + (CGFloat(spacingCount) * DesignSystem.Spacing.small)
    }

    private let compactCapsuleHeight: CGFloat = 60
    private let compactTransitionDistance: CGFloat = 46
    private let expandedHeight: CGFloat = 224

    private var expandedWidth: CGFloat {
        dynamicTypeSize >= .accessibility1 ? 360 : 332
    }

    private var surfaceWidth: CGFloat {
        isPressing ? expandedWidth : compactWidth
    }

    private var surfaceHeight: CGFloat {
        isPressing ? expandedHeight : compactCapsuleHeight
    }

    private var surfaceCornerRadius: CGFloat {
        isPressing ? 38 : compactCapsuleHeight / 2
    }

    @MainActor
    private func beginActivityTransition(to nextState: AcademicAIActivityState) {
        guard nextState != visibleActivityState else {
            pendingActivityState = nil
            return
        }

        // Let the current physical movement finish from its presentation
        // value. Rapid provider updates replace only the pending destination,
        // so the capsule never hard-cuts halfway through a roll.
        if outgoingActivityState != nil {
            pendingActivityState = nextState
            return
        }

        activityTransitionTask?.cancel()
        pendingActivityState = nil

        // Establish the old/new peer surfaces in a transaction without an
        // implicit parent animation, then move both complete capsules in the
        // next transaction. This makes the stacked wheel effect deterministic
        // even when the feature changes its state during an async import task.
        var setupTransaction = Transaction()
        setupTransaction.animation = nil
        withTransaction(setupTransaction) {
            outgoingActivityState = visibleActivityState
            visibleActivityState = nextState
            isRollingActivity = false
        }

        DispatchQueue.main.async {
            guard self.outgoingActivityState != nil else { return }
            withAnimation(self.effectiveReduceMotion ? DesignSystem.Motion.reduced : self.rollingAnimation) {
                self.isRollingActivity = true
            }
        }

        activityTransitionTask = Task { @MainActor in
            try? await Task.sleep(for: effectiveReduceMotion ? .seconds(0.22) : .seconds(0.62))
            guard !Task.isCancelled else { return }
            withAnimation(.none) {
                outgoingActivityState = nil
                isRollingActivity = false
            }

            let queuedState = pendingActivityState
            pendingActivityState = nil
            activityTransitionTask = nil
            if let queuedState, queuedState != visibleActivityState {
                beginActivityTransition(to: queuedState)
            }
        }
    }

    @MainActor
    private func updateExpandedContent(for pressing: Bool) {
        showsExpandedContent = pressing
    }

    @MainActor
    private func updatePressActivation(for touchingSurface: Bool) {
        pressActivationTask?.cancel()

        guard touchingSurface else {
            isPressing = false
            return
        }

        // A quick tap is not an expansion command. Wait for a short native
        // hold threshold before morphing the surface so ordinary taps never
        // create a partial-height glass flash. Once activated, release remains
        // immediate and the spring can reverse from its presentation value.
        pressActivationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.26))
            guard !Task.isCancelled else { return }
            isPressing = true
            pressActivationTask = nil
        }
    }

    private func compactContent(for activityState: AcademicAIActivityState) -> some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            ThinkingOrb(
                state: activityState.orbState,
                size: .px20,
                theme: .auto,
                displaySize: 36
            )
            // Keep the orb's drawing and the layout slot identical for every
            // activity state. This prevents a state transition from changing
            // the visual center of the capsule.
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            Text(verbatim: AppLocalization.string(activityState.localizationKey, locale: locale))
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)
                // The status uses its measured width instead of a fixed,
                // leading-aligned slot. This keeps short and long localized
                // phrases optically centered as one group with the orb and
                // optional xmark.
                .frame(maxWidth: compactTextMaxWidth, alignment: .leading)

            if allowsCancellation {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: compactCancelVisualSlotWidth, height: 44)
                    .accessibilityHidden(true)
            }
        }
        // Let the current state's complete content group keep its intrinsic
        // width, then center that group inside the stable capsule footprint.
        // The optional xmark is therefore part of the same centering math,
        // rather than a trailing decoration pinned to the capsule edge.
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: compactContentWidth, height: compactCapsuleHeight, alignment: .center)
        .frame(width: compactWidth, height: compactCapsuleHeight)
    }

    private var compactForeground: Color {
        colorScheme == .dark ? .white : .primary
    }

    @ViewBuilder
    private func surfaceBackground(in shape: RoundedRectangle) -> some View {
        if effectiveReduceTransparency || usesHighContrastSurface {
            shape
                .fill(Color(.secondarySystemGroupedBackground))
        } else {
            shape
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: shape)
        }
    }
}

/// Replaces one activity row with the next by moving the old row upward while
/// the new row enters from below. Keeping both rows alive for the transition
/// makes the rolling/stacked motion observable instead of relying on a view
/// identity transition that can be coalesced with the parent state update.
private struct AcademicAIActivityRollingContent: View {
    @Environment(\.locale) private var locale

    let state: AcademicAIActivityState
    let displaySize: Double
    let font: Font
    let includesOrb: Bool
    let effectiveReduceMotion: Bool

    @State private var visibleState: AcademicAIActivityState
    @State private var outgoingState: AcademicAIActivityState?
    @State private var isRolling = false
    @State private var transitionTask: Task<Void, Never>?

    init(
        state: AcademicAIActivityState,
        displaySize: Double,
        font: Font,
        includesOrb: Bool,
        effectiveReduceMotion: Bool
    ) {
        self.state = state
        self.displaySize = displaySize
        self.font = font
        self.includesOrb = includesOrb
        self.effectiveReduceMotion = effectiveReduceMotion
        _visibleState = State(initialValue: state)
    }

    private var rowHeight: CGFloat {
        includesOrb ? displaySize + 8 : 28
    }

    private var rollingAnimation: Animation {
        .interactiveSpring(response: 0.42, dampingFraction: 1, blendDuration: 0.08)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if let outgoingState {
                row(for: outgoingState)
                    .offset(y: isRolling ? -rowHeight : 0)
                    .opacity(isRolling ? 0 : 1)
                    .accessibilityHidden(true)
            }

            row(for: visibleState)
                .offset(y: outgoingState == nil || isRolling ? 0 : rowHeight)
                .opacity(outgoingState == nil || isRolling ? 1 : 0)
        }
        .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
        .clipped()
        .onAppear {
            guard visibleState != state else { return }
            visibleState = state
        }
        .onChange(of: state) { _, nextState in
            beginTransition(to: nextState)
        }
        .onDisappear {
            transitionTask?.cancel()
        }
    }

    @MainActor
    private func beginTransition(to nextState: AcademicAIActivityState) {
        guard nextState != visibleState else { return }
        transitionTask?.cancel()

        guard !effectiveReduceMotion else {
            outgoingState = nil
            visibleState = nextState
            isRolling = false
            return
        }

        outgoingState = visibleState
        visibleState = nextState
        isRolling = false

        // The first transaction establishes the stacked rows. The following
        // transaction animates the outgoing/incoming pair together.
        DispatchQueue.main.async {
            guard self.outgoingState != nil else { return }
            withAnimation(self.rollingAnimation) {
                self.isRolling = true
            }
        }

        transitionTask = Task { @MainActor in
            try? await Task.sleep(for: effectiveReduceMotion ? .seconds(0.22) : .seconds(0.62))
            guard !Task.isCancelled else { return }
            withAnimation(.none) {
                outgoingState = nil
                isRolling = false
            }
        }
    }

    @ViewBuilder
    private func row(for state: AcademicAIActivityState) -> some View {
        HStack(spacing: includesOrb ? DesignSystem.Spacing.small : 0) {
            if includesOrb {
                ThinkingOrb(
                    state: state.orbState,
                    size: .px20,
                    theme: .auto,
                    displaySize: displaySize
                )
                .accessibilityHidden(true)
            }

            Text(verbatim: AppLocalization.string(state.localizationKey, locale: locale))
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(includesOrb ? 0.82 : 0.85)
                .accessibilitySortPriority(1)
        }
        .frame(maxWidth: includesOrb ? nil : .infinity, alignment: includesOrb ? .leading : .center)
    }
}

/// Uses SwiftUI's native Button press state instead of attaching a gesture to
/// a conditional view branch. The label can morph while the finger remains
/// down, so the expanded surface stays a transient, interruptible affordance.
private struct AcademicAIActivityPressStyle: ButtonStyle {
    let onPressingChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed, initial: true) { _, pressing in
                onPressingChanged(pressing)
            }
    }
}

/// Shared bottom-centered placement for any genuinely indeterminate AI work.
/// The feature owns only the optional state and cancellation action; this
/// wrapper keeps the capsule's spacing, transient expansion, and reduced-motion
/// behavior consistent across import, Quick Add, and future AI surfaces.
struct AcademicAIActivityOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: AcademicAIActivityState?
    let onCancel: () -> Void
    @Binding var isExpanded: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            if let currentState = state {
                HStack {
                    Spacer(minLength: 0)
                    AcademicAIActivityView(
                        state: currentState,
                        allowsCancellation: true,
                        onCancel: onCancel,
                        onPressChanged: { pressing in
                            // The capsule owns the physical spring. This
                            // binding informs the feature without starting a
                            // second competing layout animation.
                            isExpanded = pressing
                        }
                    )
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.top, DesignSystem.Spacing.small)
                .padding(.bottom, DesignSystem.Spacing.medium)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .offset(y: 12).combined(with: .opacity)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .animation(
            reduceMotion
                ? DesignSystem.Motion.reduced
                : .interactiveSpring(response: 0.34, dampingFraction: 1, blendDuration: 0.08),
            value: state != nil
        )
    }
}

/// Screenshot-only review surface. It is entered only by the existing
/// `--screenshot-*` validation harness and is not part of normal navigation.
struct AcademicAIActivityReviewView: View {
    private let reviewStates: [AcademicAIActivityState] = [
        .preparingModel,
        .searchingSyllabus,
        .reasoningSyllabus,
        .shapingResult
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            CampusBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                    Text("AI Activity")
                        .font(.largeTitle.bold())
                    Text("Compact status capsules used during indeterminate local work.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        ForEach(reviewStates, id: \.rawValue) { state in
                            AcademicAIActivityView(
                                state: state,
                                allowsCancellation: state == .reasoningSyllabus,
                                onCancel: { }
                            )
                                .fixedSize(horizontal: true, vertical: false)
                                .accessibilityIdentifier("aiActivity-\(state.rawValue)")
                        }
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.horizontal, DesignSystem.Spacing.large)
                .padding(.vertical, DesignSystem.Spacing.xLarge)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("AI Activity")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("aiActivityReview")
    }
}
