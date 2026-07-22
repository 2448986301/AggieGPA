import SwiftUI

struct PlannerView: View {
    let preferences: UserPreferences

    var body: some View {
        NavigationStack {
            List {
                Section("Your GPA") {
                    NavigationLink { WhatIfView(preferences: preferences) } label: {
                        PlannerRow(icon: "chart.line.uptrend.xyaxis", title: "Projected GPA", subtitle: "See how your current course grades affect this term")
                    }
                    NavigationLink { TargetGPAView(preferences: preferences) } label: {
                        PlannerRow(icon: "target", title: "Target GPA", subtitle: "Find the future average you need")
                    }
                }
                Section("Explore") {
                    NavigationLink { FinalGradeCalculatorView() } label: {
                        PlannerRow(icon: "percent", title: "Course grade calculator", subtitle: "Try a course calculation without changing your records")
                    }
                    NavigationLink { ScenarioListView(preferences: preferences) } label: {
                        PlannerRow(icon: "square.3.layers.3d", title: "Assumed grades", subtitle: "Compare saved grade plans")
                    }
                    NavigationLink { FutureQuarterPlannerView(preferences: preferences) } label: {
                        PlannerRow(icon: "calendar.badge.clock", title: "Future terms", subtitle: "Keep planned courses separate")
                    }
                }
                Section { DisclaimerBanner() }
            }
            .navigationTitle("GPA")
        }
    }
}

private struct PlannerRow: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(DesignSystem.ColorToken.gold)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
