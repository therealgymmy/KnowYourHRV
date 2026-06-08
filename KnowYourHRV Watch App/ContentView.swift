//
//  ContentView.swift
//  KnowYourHRV Watch App
//
//  Created by Jimmy Lu on 5/19/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var hrvStore = HRVStore()
    @StateObject private var activeEnergyStore = ActiveEnergyStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .task {
            hrvStore.refreshIfNeeded()
            activeEnergyStore.refreshIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                hrvStore.refreshIfNeeded()
                activeEnergyStore.refreshIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch hrvStore.state {
        case .idle, .loading:
            VStack(alignment: .leading, spacing: 12) {
                HeaderView()

                Spacer(minLength: 6)

                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                Text("Reading HRV")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 6)
            }

        case .unavailable(let message), .failed(let message):
            StatusMessageView(
                title: "No Signal",
                message: message,
                actionTitle: "Retry",
                action: hrvStore.refreshIfNeeded
            )

        case .noData:
            StatusMessageView(
                title: "No HRV Yet",
                message: "Wear your watch to sleep or use Mindfulness to record HRV.",
                actionTitle: "Retry",
                action: hrvStore.refreshIfNeeded
            )

        case .loaded(let dashboard):
            HRVDashboardView(
                dashboard: dashboard,
                activeEnergyState: activeEnergyStore.state
            )
        }
    }
}

private struct HRVDashboardView: View {
    let dashboard: HRVStore.HRVDashboard
    let activeEnergyState: ActiveEnergyStore.State

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HeaderView()

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(dashboard.latest.milliseconds, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())

                    Text("ms HRV")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 62, alignment: .leading)

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: dashboard.stressState.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(dashboard.stressState.symbolColor)
                            .frame(width: 15, height: 15)

                        Text(dashboard.stressState.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Text(comparisonText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Stress Signal")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                StressGauge(value: dashboard.stressState.gaugeValue)
                    .frame(height: 9)
            }

            ActiveEnergySummaryView(state: activeEnergyState)

            FooterView(dashboard: dashboard)
        }
    }

    private var comparisonText: String {
        guard let percentFromBaseline = dashboard.percentFromBaseline else {
            return "Building your usual"
        }

        let percent = abs(percentFromBaseline * 100).rounded()

        if percentFromBaseline >= 0.15 {
            return "\(percent.formatted(.number.precision(.fractionLength(0))))% above usual"
        } else if percentFromBaseline <= -0.10 {
            return "\(percent.formatted(.number.precision(.fractionLength(0))))% below usual"
        } else {
            return "Near your usual"
        }
    }
}

private struct ActiveEnergySummaryView: View {
    let state: ActiveEnergyStore.State

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 14, height: 14)

                Text("Move")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text(valueText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            MoveProgressBar(progress: progress)
                .frame(height: 7)

            Text(detailText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.top, 2)
    }

    private var dashboard: ActiveEnergyStore.ActiveEnergyDashboard? {
        if case .loaded(let dashboard) = state {
            return dashboard
        }

        return nil
    }

    private var valueText: String {
        guard let dashboard else {
            return "-- kcal"
        }

        let activeCalories = dashboard.activeKilocalories.formatted(.number.precision(.fractionLength(0)))
        return "\(activeCalories) kcal"
    }

    private var detailText: String {
        switch state {
        case .idle, .loading:
            return "Reading active calories"
        case .unavailable, .failed:
            return "Active calories unavailable"
        case .loaded(let dashboard):
            guard let goalKilocalories = dashboard.goalKilocalories else {
                return "Today so far"
            }

            let goal = goalKilocalories.formatted(.number.precision(.fractionLength(0)))
            let percent = ((dashboard.percentComplete ?? 0) * 100).formatted(.number.precision(.fractionLength(0)))
            return "\(percent)% of \(goal) kcal"
        }
    }

    private var progress: Double? {
        dashboard?.progress
    }
}

private struct MoveProgressBar: View {
    let progress: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * min(max(progress ?? 0, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.20))

                Capsule()
                    .fill(.orange)
                    .frame(width: width)
            }
        }
        .accessibilityLabel("Move progress")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let progress else {
            return "Unavailable"
        }

        return "\((progress * 100).formatted(.number.precision(.fractionLength(0)))) percent"
    }
}

private extension HRVStore.StressState {
    var symbolColor: Color {
        switch self {
        case .rested:
            .green
        case .steady:
            .blue
        case .strained:
            .orange
        case .wired:
            .red
        case .noBaseline:
            .gray
        }
    }
}

private struct HeaderView: View {
    var body: some View {
        HStack {
            Text("KnowHRV")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

private struct StressGauge: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            let clampedValue = min(max(value, 0), 1)
            let width = geometry.size.width * clampedValue

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.24))

                Capsule()
                    .fill(gaugeGradient)
                    .frame(width: width)
            }
        }
        .accessibilityLabel("Stress gauge")
        .accessibilityValue("\((value * 100).formatted(.number.precision(.fractionLength(0)))) percent")
    }

    private var gaugeGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct FooterView: View {
    let dashboard: HRVStore.HRVDashboard

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(baselineText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Text(freshnessText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var baselineText: String {
        guard let baselineMilliseconds = dashboard.baselineMilliseconds else {
            return "Usual pending"
        }

        let baseline = baselineMilliseconds.formatted(.number.precision(.fractionLength(0)))
        return "Usual \(baseline) ms"
    }

    private var freshnessText: String {
        let seconds = max(0, Int(Date().timeIntervalSince(dashboard.latest.date)))

        if seconds < 60 {
            return "now"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }

        let days = hours / 24
        return "\(days)d ago"
    }
}

private struct StatusMessageView: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(actionTitle, action: action)
                .font(.caption)
        }
    }
}

#Preview {
    ContentView()
}
