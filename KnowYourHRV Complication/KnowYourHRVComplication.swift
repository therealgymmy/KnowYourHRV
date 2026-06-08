//
//  KnowYourHRVComplication.swift
//  KnowYourHRV Complication
//
//  Created by OpenAI on 5/23/26.
//

import SwiftUI
import WidgetKit

struct HRVComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> HRVComplicationEntry {
        HRVComplicationEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (HRVComplicationEntry) -> Void) {
        completion(HRVComplicationEntry(date: Date(), snapshot: HRVComplicationSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HRVComplicationEntry>) -> Void) {
        let entry = HRVComplicationEntry(date: Date(), snapshot: HRVComplicationSnapshot.load())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct HRVComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: HRVComplicationSnapshot
}

struct HRVComplicationEntryView: View {
    let entry: HRVComplicationEntry

    var body: some View {
        ZStack {
            Image(systemName: entry.snapshot.stateSymbolName)
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(entry.snapshot.symbolColor)
                .widgetAccentable()
        }
        .frame(width: 28, height: 28)
        .widgetLabel(entry.snapshot.headline)
        .containerBackground(.clear, for: .widget)
    }
}

struct KnowYourHRVComplication: Widget {
    let kind = "KnowYourHRVComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HRVComplicationProvider()) { entry in
            HRVComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("KnowHRV")
        .description("Shows your latest HRV signal.")
        .supportedFamilies([.accessoryCorner])
    }
}

struct ActiveCaloriesComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActiveCaloriesComplicationEntry {
        ActiveCaloriesComplicationEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ActiveCaloriesComplicationEntry) -> Void) {
        completion(ActiveCaloriesComplicationEntry(date: Date(), snapshot: ActiveCaloriesComplicationSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveCaloriesComplicationEntry>) -> Void) {
        let entry = ActiveCaloriesComplicationEntry(date: Date(), snapshot: ActiveCaloriesComplicationSnapshot.load())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct ActiveCaloriesComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: ActiveCaloriesComplicationSnapshot
}

struct ActiveCaloriesComplicationEntryView: View {
    let entry: ActiveCaloriesComplicationEntry

    var body: some View {
        ActiveCaloriesSegmentedArc(progress: entry.snapshot.gaugeValue)
            .frame(width: 28, height: 28)
            .widgetLabel(entry.snapshot.headline)
            .containerBackground(.clear, for: .widget)
    }
}

struct ActiveCaloriesSegmentedArc: View {
    let progress: Double

    private let segmentCount = 13
    private let startAngle = -125.0
    private let endAngle = 125.0

    var body: some View {
        ZStack {
            ForEach(0..<segmentCount, id: \.self) { index in
                let angle = startAngle + (endAngle - startAngle) * Double(index) / Double(segmentCount - 1)
                let isFilled = Double(index) < clampedProgress * Double(segmentCount)

                Capsule()
                    .fill(isFilled ? Color.orange : Color.secondary.opacity(0.26))
                    .frame(width: 2.5, height: 7)
                    .offset(y: -11)
                    .rotationEffect(.degrees(angle))
                    .widgetAccentable(isFilled)
            }

            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.orange)
                .widgetAccentable()
        }
        .accessibilityLabel("Active calories progress")
        .accessibilityValue("\((clampedProgress * 100).formatted(.number.precision(.fractionLength(0)))) percent")
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }
}

struct KnowYourHRVCaloriesComplication: Widget {
    let kind = "KnowYourHRVCaloriesComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveCaloriesComplicationProvider()) { entry in
            ActiveCaloriesComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("KnowHRV Calories")
        .description("Shows active calories toward your Move target.")
        .supportedFamilies([.accessoryCorner])
    }
}

@main
struct KnowYourHRVWidgets: WidgetBundle {
    var body: some Widget {
        KnowYourHRVComplication()
        KnowYourHRVCaloriesComplication()
    }
}

struct HRVComplicationSnapshot: Codable, Equatable {
    let stateTitle: String
    let stateSymbolName: String
    let latestMilliseconds: Double?
    let sampleDate: Date?
    let updatedAt: Date?

    var headline: String {
        guard let latestMilliseconds else {
            return stateTitle
        }

        let value = latestMilliseconds.formatted(.number.precision(.fractionLength(0)))
        return "\(stateTitle) - \(value)ms"
    }

    static let sample = HRVComplicationSnapshot(
        stateTitle: "Steady",
        stateSymbolName: "moon.dust.fill",
        latestMilliseconds: 51,
        sampleDate: Date(),
        updatedAt: Date()
    )

    static let empty = HRVComplicationSnapshot(
        stateTitle: "No HRV",
        stateSymbolName: "questionmark.circle.fill",
        latestMilliseconds: nil,
        sampleDate: nil,
        updatedAt: nil
    )

    static func load() -> HRVComplicationSnapshot {
        guard
            let data = userDefaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(HRVComplicationSnapshot.self, from: data)
        else {
            return .empty
        }

        return snapshot
    }

    private static let appGroupID = "group.realdecaf.KnowYourHRV"
    private static let snapshotKey = "latestHRVSnapshot"

    private static var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    var symbolColor: Color {
        switch stateTitle {
        case "Rested":
            .green
        case "Steady":
            .blue
        case "Strain", "Strained":
            .orange
        case "Wired":
            .red
        default:
            .gray
        }
    }
}

struct ActiveCaloriesComplicationSnapshot: Codable, Equatable {
    let activeKilocalories: Double?
    let goalKilocalories: Double?
    let sampleDate: Date?
    let updatedAt: Date?

    var gaugeValue: Double {
        guard
            let activeKilocalories,
            let goalKilocalories,
            goalKilocalories > 0
        else {
            return 0
        }

        return min(max(activeKilocalories / goalKilocalories, 0), 1)
    }

    var headline: String {
        guard let activeKilocalories else {
            return "No kcal"
        }

        let value = activeKilocalories.formatted(.number.precision(.fractionLength(0)))
        return "\(value) kcal"
    }

    static let sample = ActiveCaloriesComplicationSnapshot(
        activeKilocalories: 420,
        goalKilocalories: 600,
        sampleDate: Date(),
        updatedAt: Date()
    )

    static let empty = ActiveCaloriesComplicationSnapshot(
        activeKilocalories: nil,
        goalKilocalories: nil,
        sampleDate: nil,
        updatedAt: nil
    )

    static func load() -> ActiveCaloriesComplicationSnapshot {
        guard
            let data = userDefaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(ActiveCaloriesComplicationSnapshot.self, from: data)
        else {
            return .empty
        }

        return snapshot
    }

    private static let appGroupID = "group.realdecaf.KnowYourHRV"
    private static let snapshotKey = "latestActiveCaloriesSnapshot"

    private static var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

#Preview(as: .accessoryCorner) {
    KnowYourHRVComplication()
} timeline: {
    HRVComplicationEntry(date: .now, snapshot: .sample)
    HRVComplicationEntry(
        date: .now,
        snapshot: HRVComplicationSnapshot(
            stateTitle: "Wired",
            stateSymbolName: "bolt.badge.clock.fill",
            latestMilliseconds: 31,
            sampleDate: .now,
            updatedAt: .now
        )
    )
}

#Preview("Calories", as: .accessoryCorner) {
    KnowYourHRVCaloriesComplication()
} timeline: {
    ActiveCaloriesComplicationEntry(date: .now, snapshot: .sample)
    ActiveCaloriesComplicationEntry(
        date: .now,
        snapshot: ActiveCaloriesComplicationSnapshot(
            activeKilocalories: 735,
            goalKilocalories: 600,
            sampleDate: .now,
            updatedAt: .now
        )
    )
}
