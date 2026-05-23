//
//  HRVSampleData.swift
//  KnowYourHRV Watch App
//
//  Created by OpenAI on 5/23/26.
//

import Foundation

#if targetEnvironment(simulator)
enum HRVSampleData {
    static func monthOfReadings(now: Date = Date(), calendar: Calendar = .current) -> [HRVStore.HRVReading] {
        let startOfToday = calendar.startOfDay(for: now)
        let baseline = 52.0

        var readings: [HRVStore.HRVReading] = []

        for daysAgo in stride(from: 29, through: 1, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday) else {
                continue
            }

            let samplesForDay = 4 + stableHash(daysAgo) % 3
            let dayAdjustment = dayAdjustment(daysAgo: daysAgo)

            for sampleIndex in 0..<samplesForDay {
                guard let date = sampleDate(for: day, sampleIndex: sampleIndex, calendar: calendar) else {
                    continue
                }

                let wave = sin(Double(daysAgo) * 0.55) * 4.8
                let noise = stableNoise(day: daysAgo, sample: sampleIndex) * 4.5
                let sampleAdjustment = sampleAdjustment(sampleIndex: sampleIndex)
                let milliseconds = clamp(
                    baseline + wave + noise + dayAdjustment + sampleAdjustment,
                    min: 24,
                    max: 82
                )

                readings.append(
                    HRVStore.HRVReading(milliseconds: milliseconds, date: date)
                )
            }
        }

        readings.append(contentsOf: todayReadings(from: startOfToday, calendar: calendar))

        return readings.sorted { $0.date > $1.date }
    }

    private static func todayReadings(from startOfToday: Date, calendar: Calendar) -> [HRVStore.HRVReading] {
        [
            HRVStore.HRVReading(
                milliseconds: 54,
                date: calendar.date(byAdding: .hour, value: 7, to: startOfToday) ?? startOfToday
            ),
            HRVStore.HRVReading(
                milliseconds: 49,
                date: calendar.date(byAdding: .hour, value: 12, to: startOfToday) ?? startOfToday
            ),
            HRVStore.HRVReading(
                milliseconds: 48,
                date: Date()
            )
        ]
    }

    private static func sampleDate(for day: Date, sampleIndex: Int, calendar: Calendar) -> Date? {
        let hour: Int
        let minuteSeed: Int

        switch sampleIndex {
        case 0:
            hour = 6
            minuteSeed = 25
        case 1:
            hour = 9
            minuteSeed = 50
        case 2:
            hour = 14
            minuteSeed = 15
        case 3:
            hour = 20
            minuteSeed = 35
        case 4:
            hour = 23
            minuteSeed = 10
        default:
            hour = 2
            minuteSeed = 45
        }

        let minute = (minuteSeed + sampleIndex * 7) % 60
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    private static func dayAdjustment(daysAgo: Int) -> Double {
        switch daysAgo {
        case 22:
            -24
        case 18:
            26
        case 7...9:
            -12
        case 3...4:
            7
        default:
            0
        }
    }

    private static func sampleAdjustment(sampleIndex: Int) -> Double {
        switch sampleIndex {
        case 0:
            3
        case 3:
            -2
        case 4:
            -4
        default:
            0
        }
    }

    private static func stableNoise(day: Int, sample: Int) -> Double {
        let value = stableHash(day * 31 + sample * 17)
        return (Double(value % 100) / 100.0) * 2.0 - 1.0
    }

    private static func stableHash(_ value: Int) -> Int {
        var hash = value &* 1_103_515_245 &+ 12_345
        hash = abs(hash / 65_536)
        return hash
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }
}
#endif
