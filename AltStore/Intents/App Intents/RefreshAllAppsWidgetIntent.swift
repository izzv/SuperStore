//
//  RefreshAllAppsWidgetIntent.swift
//  AltStore
//
//  Created by Riley Testut on 8/18/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//
import AppIntents

@available(iOS 17, tvOS 17, *)
struct RefreshAllAppsWidgetIntent: AppIntent, ProgressReportingIntent
{
    static var title: LocalizedStringResource { "Refresh Apps via Widget" }
    static var isDiscoverable: Bool { false } 
    #if !WIDGET_EXTENSION
    private let intent = RefreshAllAppsIntent(presentsNotifications: true)
    #endif
    func perform() async throws -> some IntentResult
    {
    #if !WIDGET_EXTENSION
        do
        {
            _ = try await self.intent.perform()
        }
        catch
        {
            debugLog("Failed to refresh apps via widget. \(error)")
        }
    #endif
        return .result()
    }
}

@available(iOS, unavailable)
@available(tvOS, unavailable)
extension RefreshAllAppsWidgetIntent: ForegroundContinuableIntent {}
