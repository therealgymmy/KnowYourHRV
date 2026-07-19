//
//  HRVSnapshotStore.swift
//  KnowYourHRV Watch App
//
//  Created by OpenAI on 5/23/26.
//

import Foundation
import WidgetKit

enum HRVSnapshotStore {
    static let appGroupID = "group.realdecaf.KnowYourHRV"
    static let snapshotKey = "latestHRVSnapshot"
    private static let snapshotFileName = "latestHRVSnapshot.json"

    static func save(_ dashboard: HRVStore.HRVDashboard, updatedAt: Date = Date()) {
        let snapshot = HRVSnapshot(
            stateTitle: dashboard.stressState.complicationTitle,
            stateSymbolName: dashboard.stressState.symbolName,
            latestMilliseconds: dashboard.latest.milliseconds,
            sampleDate: dashboard.latest.date,
            updatedAt: updatedAt
        )

        guard snapshot.isValid else {
            return
        }

        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        userDefaults?.set(data, forKey: snapshotKey)
        write(data, fileName: snapshotFileName)
        WidgetCenter.shared.reloadTimelines(ofKind: "KnowYourHRVComplication")
    }

    private static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private static func write(_ data: Data, fileName: String) {
        guard let directoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return
        }

        let snapshotsURL = directoryURL.appendingPathComponent("Snapshots", isDirectory: true)
        let fileURL = snapshotsURL.appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}

struct HRVSnapshot: Codable, Equatable {
    let stateTitle: String
    let stateSymbolName: String
    let latestMilliseconds: Double
    let sampleDate: Date
    let updatedAt: Date

    var isValid: Bool {
        latestMilliseconds.isFinite && latestMilliseconds > 0
    }
}

enum ActiveCaloriesSnapshotStore {
    static let appGroupID = "group.realdecaf.KnowYourHRV"
    static let snapshotKey = "latestActiveCaloriesSnapshot"
    private static let snapshotFileName = "latestActiveCaloriesSnapshot.json"

    static func save(activeKilocalories: Double, goalKilocalories: Double?, sampleDate: Date, updatedAt: Date = Date()) {
        let snapshot = ActiveCaloriesSnapshot(
            activeKilocalories: activeKilocalories,
            goalKilocalories: goalKilocalories,
            sampleDate: sampleDate,
            updatedAt: updatedAt
        )

        guard snapshot.isValid else {
            return
        }

        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        userDefaults?.set(data, forKey: snapshotKey)
        write(data, fileName: snapshotFileName)
        WidgetCenter.shared.reloadTimelines(ofKind: "KnowYourHRVCaloriesComplication")
    }

    private static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private static func write(_ data: Data, fileName: String) {
        guard let directoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return
        }

        let snapshotsURL = directoryURL.appendingPathComponent("Snapshots", isDirectory: true)
        let fileURL = snapshotsURL.appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}

struct ActiveCaloriesSnapshot: Codable, Equatable {
    let activeKilocalories: Double
    let goalKilocalories: Double?
    let sampleDate: Date
    let updatedAt: Date

    var isValid: Bool {
        activeKilocalories.isFinite && activeKilocalories > 0
    }
}

private extension HRVStore.StressState {
    var complicationTitle: String {
        switch self {
        case .rested:
            "Rested"
        case .steady:
            "Steady"
        case .strained:
            "Strain"
        case .wired:
            "Wired"
        case .noBaseline:
            "HRV"
        }
    }
}
