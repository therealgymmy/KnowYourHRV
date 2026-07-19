//
//  HRVStore.swift
//  KnowYourHRV Watch App
//
//  Created by Jimmy Lu on 5/20/26.
//

import Foundation
import Combine
import HealthKit
import OSLog

@MainActor
final class HRVStore: ObservableObject {
    static let shared = HRVStore()

    private let logger = Logger(subsystem: "realdecaf.KnowYourHRV", category: "HRVStore")

    enum State: Equatable {
        case idle
        case loading
        case unavailable(String)
        case noData
        case loaded(HRVDashboard)
        case failed(String)
    }

    struct HRVReading: Equatable {
        let milliseconds: Double
        let date: Date
    }

    struct HRVDashboard: Equatable {
        let latest: HRVReading
        let baselineMilliseconds: Double?
        let percentFromBaseline: Double?
        let stressState: StressState
    }

    enum StressState: Equatable {
        case rested
        case steady
        case strained
        case wired
        case noBaseline

        var title: String {
            switch self {
            case .rested:
                "Rested"
            case .steady:
                "Steady"
            case .strained:
                "Strained"
            case .wired:
                "Wired"
            case .noBaseline:
                "Learning"
            }
        }

        var symbolName: String {
            switch self {
            case .rested:
                "sun.dust.fill"
            case .steady:
                "moon.dust.fill"
            case .strained:
                "waveform.circle.fill"
            case .wired:
                "bolt.badge.clock.fill"
            case .noBaseline:
                "questionmark.circle.fill"
            }
        }

        var gaugeValue: Double {
            switch self {
            case .rested:
                0.18
            case .steady:
                0.38
            case .strained:
                0.68
            case .wired:
                0.92
            case .noBaseline:
                0.30
            }
        }
    }

    @Published private(set) var state: State = .idle

    private let healthStore = HKHealthStore()
    private var hrvType: HKQuantityType?
    private var hrvObserverQuery: HKObserverQuery?
    private var lastRefreshDate: Date?
    private let minimumRefreshInterval: TimeInterval = 60

    private init() {}

    func prepareForBackgroundDelivery() {
        guard
            HKHealthStore.isHealthDataAvailable(),
            let hrvType = hrvType ?? HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        else {
            return
        }

        self.hrvType = hrvType
        startBackgroundUpdates(for: hrvType)
    }

    func refreshIfNeeded() {
        guard shouldRefresh else {
            return
        }

        refresh()
    }

    func refreshInBackground(completion: @escaping () -> Void) {
        refresh(force: true, completion: completion)
    }

    private func refresh(force: Bool = false, completion: (() -> Void)? = nil) {
        if !force, case .loading = state {
            completion?()
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable("Health data is not available on this device.")
            completion?()
            return
        }

        guard let hrvType = hrvType ?? HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            state = .unavailable("HRV is not available on this version of watchOS.")
            completion?()
            return
        }

        guard force || shouldRefresh else {
            completion?()
            return
        }

        state = .loading
        self.hrvType = hrvType

        healthStore.requestAuthorization(toShare: [], read: [hrvType]) { [weak self] success, error in
            guard let self else {
                completion?()
                return
            }

            Task { @MainActor [self] in
                if let error {
                    self.state = .failed(error.localizedDescription)
                    completion?()
                    return
                }

                guard success else {
                    self.state = .failed("Health access was not granted.")
                    completion?()
                    return
                }

                self.startBackgroundUpdates(for: hrvType)
                self.loadLatestHRV(from: hrvType, completion: completion)
            }
        }
    }

    private var shouldRefresh: Bool {
        guard let lastRefreshDate else {
            return true
        }

        return Date().timeIntervalSince(lastRefreshDate) >= minimumRefreshInterval
    }

    private func startBackgroundUpdates(for hrvType: HKQuantityType) {
        guard hrvObserverQuery == nil else {
            return
        }

        let query = HKObserverQuery(sampleType: hrvType, predicate: nil) { [weak self] _, completionHandler, error in
            guard let self, error == nil else {
                completionHandler()
                return
            }

            Task { @MainActor [self] in
                self.loadLatestHRV(from: hrvType, completion: completionHandler)
            }
        }

        hrvObserverQuery = query
        healthStore.execute(query)
        healthStore.enableBackgroundDelivery(for: hrvType, frequency: .immediate) { [logger] success, error in
            if let error {
                logger.error("Unable to enable HRV background delivery: \(error.localizedDescription, privacy: .public)")
            } else if !success {
                logger.error("HealthKit did not enable HRV background delivery")
            } else {
                logger.debug("Enabled HRV background delivery")
            }
        }
    }

    private func loadLatestHRV(from hrvType: HKQuantityType, completion: (() -> Void)? = nil) {
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
        ) { [weak self] _, samples, error in
            guard let self else { return }

            Task { @MainActor [self] in
                defer {
                    completion?()
                }

                self.lastRefreshDate = Date()

                if let error {
                    self.state = .failed(error.localizedDescription)
                    return
                }

                var readings = samples?
                    .compactMap { $0 as? HKQuantitySample }
                    .compactMap { sample -> HRVReading? in
                        let milliseconds = sample.quantity.doubleValue(for: .secondUnit(with: .milli))
                        guard milliseconds.isFinite, milliseconds > 0 else {
                            return nil
                        }

                        return HRVReading(milliseconds: milliseconds, date: sample.endDate)
                    } ?? []

                #if targetEnvironment(simulator)
                if readings.isEmpty {
                    readings = HRVSampleData.monthOfReadings()
                }
                #endif

                guard let dashboard = self.makeDashboard(from: readings) else {
                    self.state = .noData
                    return
                }

                HRVSnapshotStore.save(dashboard)
                self.state = .loaded(dashboard)
            }
        }

        healthStore.execute(query)
    }

    private func makeDashboard(from readings: [HRVReading]) -> HRVDashboard? {
        let sortedReadings = readings.sorted { $0.date > $1.date }

        guard let latest = sortedReadings.first else {
            return nil
        }

        let baseline = calculateBaseline(from: sortedReadings, excluding: latest)
        let percentFromBaseline = baseline.map { (latest.milliseconds - $0) / $0 }
        let stressState = calculateStressState(percentFromBaseline: percentFromBaseline)

        return HRVDashboard(
            latest: latest,
            baselineMilliseconds: baseline,
            percentFromBaseline: percentFromBaseline,
            stressState: stressState
        )
    }

    private func calculateBaseline(from readings: [HRVReading], excluding latest: HRVReading) -> Double? {
        let baselineValues = readings
            .filter { $0 != latest }
            .map(\.milliseconds)
            .filter { $0 > 0 }

        guard baselineValues.count >= 3 else {
            return nil
        }

        let sortedValues = baselineValues.sorted()
        let trimmedValues: [Double]

        if sortedValues.count >= 7 {
            trimmedValues = Array(sortedValues.dropFirst().dropLast())
        } else {
            trimmedValues = sortedValues
        }

        guard !trimmedValues.isEmpty else {
            return nil
        }

        return trimmedValues.reduce(0, +) / Double(trimmedValues.count)
    }

    private func calculateStressState(percentFromBaseline: Double?) -> StressState {
        guard let percentFromBaseline else {
            return .noBaseline
        }

        if percentFromBaseline >= 0.15 {
            return .rested
        } else if percentFromBaseline >= -0.10 {
            return .steady
        } else if percentFromBaseline >= -0.25 {
            return .strained
        } else {
            return .wired
        }
    }
}

@MainActor
final class ActiveEnergyStore: ObservableObject {
    static let shared = ActiveEnergyStore()

    private let logger = Logger(subsystem: "realdecaf.KnowYourHRV", category: "ActiveEnergyStore")

    enum State: Equatable {
        case idle
        case loading
        case unavailable
        case loaded(ActiveEnergyDashboard)
        case failed
    }

    struct ActiveEnergyDashboard: Equatable {
        let activeKilocalories: Double
        let goalKilocalories: Double?
        let sampleDate: Date

        var progress: Double? {
            guard let goalKilocalories, goalKilocalories > 0 else {
                return nil
            }

            return min(max(activeKilocalories / goalKilocalories, 0), 1)
        }

        var percentComplete: Double? {
            guard let goalKilocalories, goalKilocalories > 0 else {
                return nil
            }

            return activeKilocalories / goalKilocalories
        }
    }

    @Published private(set) var state: State = .idle

    private let healthStore = HKHealthStore()
    private var activeEnergyType: HKQuantityType?
    private var activeEnergyObserverQuery: HKObserverQuery?
    private var lastRefreshDate: Date?
    private let minimumRefreshInterval: TimeInterval = 60

    private init() {}

    func prepareForBackgroundDelivery() {
        guard
            HKHealthStore.isHealthDataAvailable(),
            let activeEnergyType = activeEnergyType ?? HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        else {
            return
        }

        self.activeEnergyType = activeEnergyType
        startBackgroundUpdates(for: activeEnergyType)
    }

    func refreshIfNeeded() {
        refresh()
    }

    func refreshInBackground(completion: @escaping () -> Void) {
        refresh(force: true, completion: completion)
    }

    private func refresh(force: Bool = false, completion: (() -> Void)? = nil) {
        if !force, case .loading = state {
            completion?()
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            completion?()
            return
        }

        guard let activeEnergyType = activeEnergyType ?? HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            state = .unavailable
            completion?()
            return
        }

        guard force || shouldRefresh else {
            completion?()
            return
        }

        state = .loading
        self.activeEnergyType = activeEnergyType

        let readTypes: Set<HKObjectType> = [
            activeEnergyType,
            HKObjectType.activitySummaryType()
        ]

        healthStore.requestAuthorization(toShare: [], read: readTypes) { [weak self] success, _ in
            guard let self else {
                completion?()
                return
            }

            guard success else {
                Task { @MainActor [self] in
                    self.state = .failed
                    completion?()
                }
                return
            }

            Task { @MainActor [self] in
                self.startBackgroundUpdates(for: activeEnergyType)
                self.loadTodayActiveEnergy(from: activeEnergyType, completion: completion)
            }
        }
    }

    private var shouldRefresh: Bool {
        guard let lastRefreshDate else {
            return true
        }

        return Date().timeIntervalSince(lastRefreshDate) >= minimumRefreshInterval
    }

    private func startBackgroundUpdates(for activeEnergyType: HKQuantityType) {
        guard activeEnergyObserverQuery == nil else {
            return
        }

        let query = HKObserverQuery(sampleType: activeEnergyType, predicate: nil) { [weak self] _, completionHandler, error in
            guard let self, error == nil else {
                completionHandler()
                return
            }

            Task { @MainActor [self] in
                self.loadTodayActiveEnergy(from: activeEnergyType, completion: completionHandler)
            }
        }

        activeEnergyObserverQuery = query
        healthStore.execute(query)
        healthStore.enableBackgroundDelivery(for: activeEnergyType, frequency: .immediate) { [logger] success, error in
            if let error {
                logger.error("Unable to enable active-energy background delivery: \(error.localizedDescription, privacy: .public)")
            } else if !success {
                logger.error("HealthKit did not enable active-energy background delivery")
            } else {
                logger.debug("Enabled active-energy background delivery")
            }
        }
    }

    private func loadTodayActiveEnergy(from activeEnergyType: HKQuantityType, completion: (() -> Void)? = nil) {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let query = HKStatisticsQuery(
            quantityType: activeEnergyType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, statistics, error in
            guard let self else { return }

            Task { @MainActor [self] in
                if error != nil {
                    self.lastRefreshDate = Date()
                    self.state = .failed
                    completion?()
                    return
                }

                guard let activeEnergyQuantity = statistics?.sumQuantity() else {
                    self.lastRefreshDate = Date()
                    self.state = .loaded(
                        ActiveEnergyDashboard(
                            activeKilocalories: 0,
                            goalKilocalories: nil,
                            sampleDate: now
                        )
                    )
                    completion?()
                    return
                }

                let kilocalories = activeEnergyQuantity.doubleValue(for: .kilocalorie())
                self.loadMoveGoal(
                    activeKilocalories: kilocalories,
                    date: now,
                    saveSnapshot: true,
                    completion: completion
                )
            }
        }

        healthStore.execute(query)
    }

    private func loadMoveGoal(activeKilocalories: Double, date: Date, saveSnapshot: Bool, completion: (() -> Void)? = nil) {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.calendar, .era, .year, .month, .day], from: date)
        components.calendar = calendar

        let predicate = HKQuery.predicateForActivitySummary(with: components)
        let query = HKActivitySummaryQuery(predicate: predicate) { [weak self] _, summaries, _ in
            guard let self else { return }

            let goalKilocalories = summaries?
                .first?
                .activeEnergyBurnedGoal
                .doubleValue(for: .kilocalorie())

            Task { @MainActor [self] in
                defer {
                    completion?()
                }

                self.lastRefreshDate = Date()
                let dashboard = ActiveEnergyDashboard(
                    activeKilocalories: activeKilocalories,
                    goalKilocalories: goalKilocalories,
                    sampleDate: date
                )

                if saveSnapshot {
                    ActiveCaloriesSnapshotStore.save(
                        activeKilocalories: activeKilocalories,
                        goalKilocalories: goalKilocalories,
                        sampleDate: date
                    )
                }

                self.state = .loaded(dashboard)
            }
        }

        healthStore.execute(query)
    }
}
