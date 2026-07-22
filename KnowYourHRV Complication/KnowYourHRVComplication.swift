//
//  KnowYourHRVComplication.swift
//  KnowYourHRV Complication
//
//  Created by OpenAI on 5/23/26.
//

import HealthKit
import SwiftUI
import WidgetKit

struct HRVComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> HRVComplicationEntry {
        HRVComplicationEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (HRVComplicationEntry) -> Void) {
        guard !context.isPreview else {
            completion(HRVComplicationEntry(date: Date(), snapshot: .sample))
            return
        }

        ComplicationHealthDataLoader.loadHRV { snapshot in
            completion(HRVComplicationEntry(date: Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HRVComplicationEntry>) -> Void) {
        ComplicationHealthDataLoader.loadHRV { snapshot in
            let now = Date()
            let entry = HRVComplicationEntry(date: now, snapshot: snapshot)
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
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
        guard !context.isPreview else {
            completion(ActiveCaloriesComplicationEntry(date: Date(), snapshot: .sample))
            return
        }

        ComplicationHealthDataLoader.loadActiveCalories { snapshot in
            completion(ActiveCaloriesComplicationEntry(date: Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveCaloriesComplicationEntry>) -> Void) {
        ComplicationHealthDataLoader.loadActiveCalories { snapshot in
            let now = Date()
            let entry = ActiveCaloriesComplicationEntry(date: now, snapshot: snapshot)
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}

private enum ComplicationHealthDataLoader {
    private static let healthStore = HKHealthStore()

    static func loadHRV(completion: @escaping (HRVComplicationSnapshot) -> Void) {
        guard
            HKHealthStore.isHealthDataAvailable(),
            let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        else {
            completion(HRVComplicationSnapshot.load())
            return
        }

        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        let predicate = startDate.map {
            HKQuery.predicateForSamples(withStart: $0, end: nil, options: .strictStartDate)
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: hrvType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, error in
            guard error == nil else {
                completion(HRVComplicationSnapshot.load())
                return
            }

            let readings = samples?
                .compactMap { $0 as? HKQuantitySample }
                .compactMap { sample -> (milliseconds: Double, date: Date)? in
                    let milliseconds = sample.quantity.doubleValue(for: .secondUnit(with: .milli))
                    guard milliseconds.isFinite, milliseconds > 0 else {
                        return nil
                    }

                    return (milliseconds, sample.endDate)
                }
                .sorted { $0.date > $1.date } ?? []

            guard let latest = readings.first else {
                completion(HRVComplicationSnapshot.load())
                return
            }

            let baselineValues = readings.dropFirst().map(\.milliseconds).sorted()
            let trimmedValues: ArraySlice<Double>

            if baselineValues.count >= 7 {
                trimmedValues = baselineValues.dropFirst().dropLast()
            } else {
                trimmedValues = baselineValues[...]
            }

            let baseline = trimmedValues.count >= 3
                ? trimmedValues.reduce(0, +) / Double(trimmedValues.count)
                : nil
            let percentFromBaseline = baseline.map { (latest.milliseconds - $0) / $0 }
            let presentation = hrvPresentation(percentFromBaseline: percentFromBaseline)

            completion(
                HRVComplicationSnapshot(
                    stateTitle: presentation.title,
                    stateSymbolName: presentation.symbolName,
                    latestMilliseconds: latest.milliseconds,
                    sampleDate: latest.date,
                    updatedAt: Date()
                )
            )
        }

        healthStore.execute(query)
    }

    static func loadActiveCalories(completion: @escaping (ActiveCaloriesComplicationSnapshot) -> Void) {
        guard
            HKHealthStore.isHealthDataAvailable(),
            let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        else {
            completion(ActiveCaloriesComplicationSnapshot.load())
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let query = HKStatisticsQuery(
            quantityType: activeEnergyType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, statistics, error in
            guard error == nil else {
                completion(ActiveCaloriesComplicationSnapshot.load())
                return
            }

            let activeKilocalories = statistics?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie()) ?? 0
            loadMoveGoal(for: now) { goalKilocalories in
                completion(
                    ActiveCaloriesComplicationSnapshot(
                        activeKilocalories: activeKilocalories,
                        goalKilocalories: goalKilocalories,
                        sampleDate: now,
                        updatedAt: Date()
                    )
                )
            }
        }

        healthStore.execute(query)
    }

    private static func loadMoveGoal(for date: Date, completion: @escaping (Double?) -> Void) {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.calendar, .era, .year, .month, .day], from: date)
        components.calendar = calendar

        let predicate = HKQuery.predicateForActivitySummary(with: components)
        let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
            let goalKilocalories = summaries?
                .first?
                .activeEnergyBurnedGoal
                .doubleValue(for: .kilocalorie())
            completion(goalKilocalories)
        }

        healthStore.execute(query)
    }

    private static func hrvPresentation(percentFromBaseline: Double?) -> (title: String, symbolName: String) {
        guard let percentFromBaseline else {
            return ("HRV", "questionmark.circle.fill")
        }

        if percentFromBaseline >= 0.15 {
            return ("Rested", "sun.dust.fill")
        } else if percentFromBaseline >= -0.10 {
            return ("Steady", "moon.dust.fill")
        } else if percentFromBaseline >= -0.25 {
            return ("Strain", "waveform.circle.fill")
        } else {
            return ("Wired", "bolt.badge.clock.fill")
        }
    }
}

struct ActiveCaloriesComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: ActiveCaloriesComplicationSnapshot
}

struct ActiveCaloriesComplicationEntryView: View {
    let entry: ActiveCaloriesComplicationEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            Gauge(value: entry.snapshot.gaugeValue, in: 0...1) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.orange)
            .widgetAccentable()
        }
        .widgetLabel(entry.snapshot.headline)
        .containerBackground(.clear, for: .widget)
        .accessibilityLabel("Active calories progress")
        .accessibilityValue(entry.snapshot.accessibilityProgressText)
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
        if let snapshot = loadFromFile(), snapshot.isValid {
            return snapshot
        }

        if let snapshot = loadFromDefaults(), snapshot.isValid {
            return snapshot
        }

        return .empty
    }

    private static let appGroupID = "group.realdecaf.KnowYourHRV"
    private static let snapshotKey = "latestHRVSnapshot"
    private static let snapshotFileName = "latestHRVSnapshot.json"

    private static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private static func loadFromDefaults() -> HRVComplicationSnapshot? {
        guard let data = userDefaults?.data(forKey: snapshotKey) else {
            return nil
        }

        return try? JSONDecoder().decode(HRVComplicationSnapshot.self, from: data)
    }

    private static func loadFromFile() -> HRVComplicationSnapshot? {
        guard
            let directoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID),
            let data = try? Data(
                contentsOf: directoryURL
                    .appendingPathComponent("Snapshots", isDirectory: true)
                    .appendingPathComponent(snapshotFileName)
            )
        else {
            return nil
        }

        return try? JSONDecoder().decode(HRVComplicationSnapshot.self, from: data)
    }

    private var isValid: Bool {
        guard let latestMilliseconds else {
            return false
        }

        return latestMilliseconds.isFinite && latestMilliseconds > 0
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

    var shortValue: String {
        guard let activeKilocalories else {
            return "--"
        }

        return activeKilocalories.formatted(.number.precision(.fractionLength(0)))
    }

    var accessibilityProgressText: String {
        guard let goalKilocalories, goalKilocalories > 0 else {
            return "Move goal unavailable"
        }

        let percent = (gaugeValue * 100).formatted(.number.precision(.fractionLength(0)))
        return "\(percent) percent"
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
        if let snapshot = loadFromFile(), snapshot.isValid {
            return snapshot
        }

        if let snapshot = loadFromDefaults(), snapshot.isValid {
            return snapshot
        }

        return .empty
    }

    private static let appGroupID = "group.realdecaf.KnowYourHRV"
    private static let snapshotKey = "latestActiveCaloriesSnapshot"
    private static let snapshotFileName = "latestActiveCaloriesSnapshot.json"

    private static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private static func loadFromDefaults() -> ActiveCaloriesComplicationSnapshot? {
        guard let data = userDefaults?.data(forKey: snapshotKey) else {
            return nil
        }

        return try? JSONDecoder().decode(ActiveCaloriesComplicationSnapshot.self, from: data)
    }

    private static func loadFromFile() -> ActiveCaloriesComplicationSnapshot? {
        guard
            let directoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID),
            let data = try? Data(
                contentsOf: directoryURL
                    .appendingPathComponent("Snapshots", isDirectory: true)
                    .appendingPathComponent(snapshotFileName)
            )
        else {
            return nil
        }

        return try? JSONDecoder().decode(ActiveCaloriesComplicationSnapshot.self, from: data)
    }

    private var isValid: Bool {
        guard
            let activeKilocalories,
            let sampleDate,
            activeKilocalories.isFinite,
            activeKilocalories > 0
        else {
            return false
        }

        return Calendar.current.isDate(sampleDate, inSameDayAs: Date())
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
