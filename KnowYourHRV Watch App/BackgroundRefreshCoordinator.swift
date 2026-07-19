//
//  BackgroundRefreshCoordinator.swift
//  KnowYourHRV Watch App
//
//  Created by OpenAI on 7/10/26.
//

import Foundation
import OSLog
import WatchKit

@MainActor
final class BackgroundRefreshCoordinator {
    static let shared = BackgroundRefreshCoordinator()

    private let logger = Logger(subsystem: "realdecaf.KnowYourHRV", category: "BackgroundRefresh")
    private let hrvStore = HRVStore.shared
    private let activeEnergyStore = ActiveEnergyStore.shared
    private let refreshInterval: TimeInterval = 15 * 60

    private var hasStarted = false
    private var isRefreshing = false
    private var pendingCompletions: [() -> Void] = []

    private init() {}

    func start() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        hrvStore.prepareForBackgroundDelivery()
        activeEnergyStore.prepareForBackgroundDelivery()
        refreshIfNeeded()
        scheduleNextBackgroundRefresh()
    }

    func refreshIfNeeded() {
        hrvStore.refreshIfNeeded()
        activeEnergyStore.refreshIfNeeded()
    }

    func refreshSnapshots(completion: @escaping () -> Void) {
        guard !isRefreshing else {
            pendingCompletions.append(completion)
            return
        }

        isRefreshing = true
        var remainingRefreshes = 2

        func finishRefresh() {
            remainingRefreshes -= 1

            guard remainingRefreshes == 0 else {
                return
            }

            isRefreshing = false
            scheduleNextBackgroundRefresh()

            let completions = [completion] + pendingCompletions
            pendingCompletions.removeAll()
            completions.forEach { $0() }
        }

        hrvStore.refreshInBackground {
            Task { @MainActor in
                finishRefresh()
            }
        }

        activeEnergyStore.refreshInBackground {
            Task { @MainActor in
                finishRefresh()
            }
        }
    }

    func scheduleNextBackgroundRefresh() {
        let preferredDate = Date(timeIntervalSinceNow: refreshInterval)

        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: preferredDate,
            userInfo: nil
        ) { [logger] error in
            if let error {
                logger.error("Unable to schedule background refresh: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.debug("Scheduled background refresh for \(preferredDate, privacy: .public)")
            }
        }
    }
}

final class BackgroundRefreshDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        BackgroundRefreshCoordinator.shared.start()
    }

    func applicationDidBecomeActive() {
        BackgroundRefreshCoordinator.shared.refreshIfNeeded()
    }

    func applicationDidEnterBackground() {
        BackgroundRefreshCoordinator.shared.scheduleNextBackgroundRefresh()
    }

    @objc(handleBackgroundTasks:)
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            handle(task)
        }
    }

    private func handle(_ task: WKRefreshBackgroundTask) {
        if let snapshotTask = task as? WKSnapshotRefreshBackgroundTask {
            BackgroundRefreshCoordinator.shared.refreshIfNeeded()
            snapshotTask.setTaskCompleted(
                restoredDefaultState: true,
                estimatedSnapshotExpiration: Date(timeIntervalSinceNow: 15 * 60),
                userInfo: nil
            )
            return
        }

        guard task is WKApplicationRefreshBackgroundTask else {
            task.setTaskCompletedWithSnapshot(false)
            return
        }

        let completion = BackgroundTaskCompletion(task: task)
        task.expirationHandler = {
            Task { @MainActor in
                completion.complete(refreshSnapshot: false)
            }
        }

        BackgroundRefreshCoordinator.shared.refreshSnapshots {
            completion.complete(refreshSnapshot: true)
        }
    }
}

@MainActor
private final class BackgroundTaskCompletion {
    private let task: WKRefreshBackgroundTask
    private var didComplete = false

    init(task: WKRefreshBackgroundTask) {
        self.task = task
    }

    func complete(refreshSnapshot: Bool) {
        guard !didComplete else {
            return
        }

        didComplete = true
        task.expirationHandler = nil
        task.setTaskCompletedWithSnapshot(refreshSnapshot)
    }
}
