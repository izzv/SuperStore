//
//  PaginationIntent.swift
//  AltStore
//
//  Created by Magesh K on 08/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
import AppIntents
import Intents
import WidgetKit

public struct NavigationEvent {
    let direction: Direction?
    var consumed: Bool = false
    var dataHolder: PaginationDataHolder?
}

@available(iOS 17, *)
class PaginationIntent: AppIntent, @unchecked Sendable {
    static var title: LocalizedStringResource = "Page Navigation Intent"
    static var isDiscoverable: Bool = false
    @Parameter(title: "widgetID")
    var widgetID: Int

    @Parameter(title: "Direction")
    var direction: String

    @Parameter(title: "widgetKind")
    var widgetKind: String

    required init(){}
    init(_ widgetID: Int?, _ direction: Direction,  _ widgetKind: String){
        self.widgetID = widgetID ?? WidgetUpdateIntent.COMMON_WIDGET_ID
        self.direction = direction.rawValue
        self.widgetKind = widgetKind
        debugLog("[PaginationIntent] Initialized with widgetID: \(self.widgetID), direction: \(self.direction), widgetKind: \(self.widgetKind)")
    }
    func perform() async throws -> some IntentResult {
        debugLog("[PaginationIntent] Performing pagination intent: widgetKind=\(widgetKind), widgetID=\(widgetID), direction=\(direction)")
        DispatchQueue(label: String(widgetID)).sync {
            self.postThisNavigationEvent()
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }
        return .result()
    }
    private func postThisNavigationEvent(){
        let navEvent = PageInfoManager.shared.getPageInfo(forWidgetKind: widgetKind, forWidgetID: widgetID)
        let navigationEvent = NavigationEvent(
            direction: Direction(rawValue: direction),
            consumed: false,    
            dataHolder: navEvent?.dataHolder ?? nil
        )
        PageInfoManager.shared.setPageInfo(forWidgetKind: widgetKind, forWidgetID: widgetID, value: navigationEvent)
    }
}
