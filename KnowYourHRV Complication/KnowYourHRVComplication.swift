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
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
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

@main
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
        case "Strained":
            .orange
        case "Wired":
            .red
        default:
            .gray
        }
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
