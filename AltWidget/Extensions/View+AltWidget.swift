//
//  View+AltWidget.swift
//  AltStore
//
//  Created by Riley Testut on 8/18/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//
import SwiftUI
import WidgetKit

extension View
{
    @ViewBuilder
    func widgetBackground(_ backgroundView: some View) -> some View
    {
        if #available(iOSApplicationExtension 17, *)
        {
            containerBackground(for: .widget) {
                backgroundView
            }
        }
        else
        {
            background(backgroundView)
        }
    }
    @ViewBuilder
    func invalidatableContentIfAvailable() -> some View
    {
        if #available(iOSApplicationExtension 17, *)
        {
            self.invalidatableContent()
        }
        else
        {
            self
        }
    }
    @ViewBuilder
    func activatesRefreshAllAppsIntent() -> some View
    {
        if #available(iOSApplicationExtension 17, *)
        {
            Button(intent: RefreshAllAppsWidgetIntent()) {
                self
            }
            .buttonStyle(.plain)
        }
        else
        {
            self
        }
    }

    @ViewBuilder
    func pageUpButton(_ widgetID: Int?, _ widgetKind: String) -> some View {
        if #available(iOSApplicationExtension 17, *) {
            Button(intent: PaginationIntent(widgetID, .up, widgetKind)){
                self
            }
            .buttonStyle(.plain)
        } else {
            self
        }
    }

    @ViewBuilder
    func pageDownButton(_ widgetID: Int?, _ widgetKind: String) -> some View {
        if #available(iOSApplicationExtension 17, *) {
            Button(intent: PaginationIntent(widgetID, .down, widgetKind)){
                self
            }
            .buttonStyle(.plain)
        } else {
            self
        }
    }

    @ViewBuilder
    func widgetAccentableIfAvailable() -> some View
    {
        if #available(iOSApplicationExtension 16, *)
        {
            self.widgetAccentable()
        }
        else
        {
            self
        }
    }

    @ViewBuilder
    func luminanceToAlphaInAccentedMode() -> some View
    {
        if #available(iOSApplicationExtension 16, *)
        {
            LuminanceToAlphaWrapper(content: self)
        }
        else
        {
            self
        }
    }

}

@available(iOSApplicationExtension 16, *)
private struct LuminanceToAlphaWrapper<Content: View>: View
{
    let content: Content
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .accented
        {
            content.luminanceToAlpha()
        }
        else
        {
            content
        }
    }
}
