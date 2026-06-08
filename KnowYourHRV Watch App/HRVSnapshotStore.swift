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

    static func save(_ dashboard: HRVStore.HRVDashboard, updatedAt: Date = Date()) {
        let snapshot = HRVSnapshot(
            stateTitle: dashboard.stressState.complicationTitle,
            stateSymbolName: dashboard.stressState.symbolName,
            latestMilliseconds: dashboard.latest.milliseconds,
            sampleDate: dashboard.latest.date,
            updatedAt: updatedAt
        )

        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        userDefaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "KnowYourHRVComplication")
    }

    private static var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

struct HRVSnapshot: Codable, Equatable {
    let stateTitle: String
    let stateSymbolName: String
    let latestMilliseconds: Double
    let sampleDate: Date
    let updatedAt: Date
}

enum ActiveCaloriesSnapshotStore {
    static let appGroupID = "group.realdecaf.KnowYourHRV"
    static let snapshotKey = "latestActiveCaloriesSnapshot"

    static func save(activeKilocalories: Double, goalKilocalories: Double?, sampleDate: Date, updatedAt: Date = Date()) {
        let snapshot = ActiveCaloriesSnapshot(
            activeKilocalories: activeKilocalories,
            goalKilocalories: goalKilocalories,
            sampleDate: sampleDate,
            updatedAt: updatedAt
        )

        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }

        userDefaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "KnowYourHRVCaloriesComplication")
    }

    private static var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

struct ActiveCaloriesSnapshot: Codable, Equatable {
    let activeKilocalories: Double
    let goalKilocalories: Double?
    let sampleDate: Date
    let updatedAt: Date
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
