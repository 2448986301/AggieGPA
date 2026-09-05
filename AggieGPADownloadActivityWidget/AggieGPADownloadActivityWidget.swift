import ActivityKit
import SwiftUI
import ThinkingOrbsKit
import WidgetKit

// This type mirrors the app target's ActivityKit contract. Widget extensions
// are separate bundles, so the Codable shape must remain identical.
nonisolated struct ModelDownloadActivityAttributes: ActivityAttributes, Hashable, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable {
            case downloading
            case paused
            case finishing
            case failed
        }

        var receivedBytes: Int64
        var expectedBytes: Int64
        var phase: Phase

        var fraction: Double {
            guard expectedBytes > 0 else { return 0 }
            return min(1, max(0, Double(receivedBytes) / Double(expectedBytes)))
        }
    }

    let downloadID: String
    let title: String
    let modelName: String
    let languageCode: String
}

struct AggieGPADownloadActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ModelDownloadActivityAttributes.self) { context in
            DownloadActivityLockScreen(
                title: context.attributes.title,
                modelName: context.attributes.modelName,
                state: context.state
            )
            .activityBackgroundTint(Color(red: 0.07, green: 0.075, blue: 0.09))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DownloadActivityOrb(size: 54, phase: context.state.phase)
                        .padding(.leading, 16)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.attributes.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.attributes.modelName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 170, maxHeight: 52, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(percentage(context.state))%")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .padding(.trailing, 18)
                        .offset(y: 3)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.fraction)
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 5)
                        .clipShape(Capsule())
                        // The bottom expanded region follows the island's
                        // rounded clipping path. This inset keeps the track
                        // visually inside the lower corners.
                        .padding(.horizontal, 20)
                        .padding(.bottom, 5)
                }
            } compactLeading: {
                DownloadActivityOrb(size: 22, phase: context.state.phase)
            } compactTrailing: {
                Text("\(percentage(context.state))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
            } minimal: {
                DownloadActivityOrb(size: 22, phase: context.state.phase)
            }
        }
    }
}

private struct DownloadActivityLockScreen: View {
    let title: String
    let modelName: String
    let state: ModelDownloadActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DownloadActivityOrb(size: 30, phase: state.phase)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(modelName)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("\(percentage)%")
                    .font(.headline.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
            }

            ProgressView(value: state.fraction)
                .tint(.white)
                .frame(height: 4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(percentage)%")
    }

    private var percentage: Int {
        Int((state.fraction * 100).rounded())
    }
}

private struct DownloadActivityOrb: View {
    let size: Double
    let phase: ModelDownloadActivityAttributes.ContentState.Phase

    var body: some View {
        ThinkingOrb(
            state: .working,
            size: .px20,
            theme: .light,
            speed: 0.45,
            paused: phase != .downloading,
            displaySize: size
        )
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private func percentage(_ state: ModelDownloadActivityAttributes.ContentState) -> Int {
    Int((state.fraction * 100).rounded())
}

@main
struct AggieGPADownloadActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        AggieGPADownloadActivityWidget()
    }
}
