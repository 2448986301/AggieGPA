import SwiftUI

struct PlannerView: View {
    let preferences: UserPreferences

    var body: some View {
        NavigationStack {
            List {
                Section("GPA Planning") {
                    NavigationLink { WhatIfView(preferences: preferences) } label: {
                        PlannerRow(icon: "wand.and.stars", title: "What-If GPA", subtitle: "Try grades without changing records")
                    }
                    NavigationLink { TargetGPAView(preferences: preferences) } label: {
                        PlannerRow(icon: "target", title: "Target GPA Calculator", subtitle: "Find the future average you need")
                    }
                }
                Section("Course Planning") {
                    NavigationLink { FinalGradeCalculatorView() } label: {
                        PlannerRow(icon: "percent", title: "Final Grade Calculator", subtitle: "Model weighted categories and finals")
                    }
                    NavigationLink { ScenarioListView(preferences: preferences) } label: {
                        PlannerRow(icon: "square.3.layers.3d", title: "Scenario Comparison", subtitle: "Compare saved grade plans")
                    }
                    NavigationLink { FutureQuarterPlannerView(preferences: preferences) } label: {
                        PlannerRow(icon: "calendar.badge.clock", title: "Future Quarter Planner", subtitle: "Keep planned courses separate")
                    }
                }
                Section { DisclaimerBanner() }
            }
            .navigationTitle("Planner")
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
