//
//  SceneDelegate.swift
//  AltStore
//
//  Created by Riley Testut on 7/6/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//
@preconcurrency import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate
{
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions)
    {
        debugLog("[SceneDelegate] scene(willConnectTo:) invoked")
        guard let _ = (scene as? UIWindowScene) else { return }
        if let context = connectionOptions.urlContexts.first
        {
            URLHandler.shared.handle(context.url)
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene)
    {
        guard DatabaseManager.shared.isStarted else { return }
        Task {
            await AppManager.shared.reconcileInstalledApps()
            await WidgetDataManager.publishCurrentInstalledAppsIfNeeded(in: DatabaseManager.shared.viewContext)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene)
    {
        debugLog("[SceneDelegate] sceneDidBecomeActive() invoked")
        defer {
            Task.detached { await AppDelegate.dumpSideBackupLogsIfNeeded() }
        }
        if DatabaseManager.shared.isStarted {
            Task {
                await WidgetDataManager.publishCurrentInstalledAppsIfNeeded(in: DatabaseManager.shared.viewContext)
            }
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene)
    {
        guard UIApplication.shared.applicationState == .background else { return }

        guard let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) else { return }
        let midnightOneMonthAgo = Calendar.current.startOfDay(for: oneMonthAgo)
        Task.detached(priority: .background) {
            do
            {
                try await DatabaseManager.shared.purgeLoggedErrors(before: midnightOneMonthAgo)
            }
            catch
            {
                debugLog("[SuperStore] Failed to purge logged errors before \(midnightOneMonthAgo). \(error)")
            }
        }
    }
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>)
    {
        guard let context = URLContexts.first else { return }
        debugLog("[SceneDelegate] scene(_:openURLContexts:) called with URL: \(context.url)")
        URLHandler.shared.handle(context.url)
    }
}
