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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .task {
            hrvStore.refreshIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                hrvStore.refreshIfNeeded()
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
            HRVDashboardView(dashboard: dashboard)
        }
    }
}

private struct HRVDashboardView: View {
    let dashboard: HRVStore.HRVDashboard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderView()

            VStack(alignment: .leading, spacing: 5) {
                Text("Stress Signal")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                StressGauge(value: dashboard.stressState.gaugeValue)
                    .frame(height: 12)
            }

            VStack(spacing: 0) {
                Text(dashboard.latest.milliseconds, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())

                Text("ms")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: dashboard.stressState.symbolName)
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(dashboard.stressState.symbolColor)
                        .frame(width: 18, height: 18)

                    Text(dashboard.stressState.title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Text(comparisonText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

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
