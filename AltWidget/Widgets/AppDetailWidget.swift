//
//  AppDetailWidget.swift
//  AltWidgetExtension
//
//  Created by Riley Testut on 9/14/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//
import WidgetKit
import SwiftUI

struct AppDetailWidget: Widget
{
    private let kind: String = "AppDetail"
    init() {
        debugLog("[AppDetailWidget] Initialized widget kind: AppDetail")
    }
    public var body: some WidgetConfiguration {
        if #available(iOSApplicationExtension 17, *)
        {
            return AppIntentConfiguration(
                kind: kind,
                intent: SelectAppIntent.self,
                provider: SelectAppTimelineProvider()
            ) { entry in
                AppDetailWidgetView(apps: entry.apps, date: entry.date, isPlaceholder: entry.isPlaceholder)
            }
            .supportedFamilies([.systemSmall])
            .configurationDisplayName("App Status")
            .description("View remaining days until your sideloaded apps expire. Tap the countdown timer to refresh them in the background.")
            .contentMarginsDisabled()
        }
        else
        {
            return IntentConfiguration(
                kind: kind,
                intent: ViewAppIntent.self,
                provider: AppsTimelineProvider()
            ) { entry in
                AppDetailWidgetView(apps: entry.apps, date: entry.date, isPlaceholder: entry.isPlaceholder)
            }
            .supportedFamilies([.systemSmall])
            .configurationDisplayName("App Status")
            .description("View remaining days until your sideloaded apps expire. Tap the countdown timer to refresh them in the background.")
        }
    }
}

private struct AppDetailWidgetView: View
{
    let apps: [AppSnapshot]
    let date: Date
    let isPlaceholder: Bool
    var body: some View {
        Group {
            if let app = apps.first
            {
                let daysRemaining = app.expirationDate.numberOfCalendarDays(since: date)
                GeometryReader { (geometry) in
                    Group {
                        VStack(alignment: .leading) {
                            VStack(alignment: .leading, spacing: 5) {
                                let imageHeight = geometry.size.height * 0.4
                                AppIconView(icon: app.icon, imageHeight: imageHeight)
                                Text(app.name.uppercased())
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .widgetAccentableIfAvailable()
                            Spacer(minLength: 0)
                            HStack(alignment: .center) {
                                let expirationText: Text = {
                                    switch daysRemaining
                                    {
                                    case ..<0: return Text("Expired")
                                    case 1: return Text("1 day")
                                    default: return Text("\(daysRemaining) days")
                                    }
                                }()
                                (
                                    Text("Expires in\n")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.white.opacity(0.45)) +
                                    expirationText
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                )
                                .lineLimit(2)
                                .lineSpacing(1.0)
                                .minimumScaleFactor(0.5)
                                Spacer()
                                if daysRemaining >= 0
                                {
                                    Countdown(startDate: app.refreshedDate,
                                              endDate: app.expirationDate,
                                              currentDate: date)
                                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.white)
                                        .opacity(0.8)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .offset(x: 5)
                                        .invalidatableContentIfAvailable()
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .activatesRefreshAllAppsIntent()
                            .widgetAccentableIfAvailable()
                        }
                        .padding()
                    }
                }
            }
            else
            {
                VStack(spacing: 4) {
                    Text("Open SuperStore")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(Color.white.opacity(0.8))
                    Text("Launch app to update widget")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .padding()
                .unredacted()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .widgetBackground(
            backgroundView(
                icon: apps.first?.icon,
                tintColor: apps.first?.tintColor
            )
        )
        .onAppear {
            debugLog("[AppDetailWidgetView] onAppear: isPlaceholder=\(isPlaceholder), appsCount=\(apps.count), firstApp=\(apps.first?.name ?? "none"), date=\(date)")
        }
    }

    func backgroundView(icon: UIImage? = nil, tintColor: UIColor? = nil) -> some View
    {
        let defaultIcon = UIImage(named: "SideStore") ?? UIImage(systemName: "app.fill")!
        let icon = icon ?? defaultIcon
        let tintColor = tintColor ?? .gray
        let imageHeight = 60 as CGFloat
        let saturation = 1.8
        let blurRadius = 5 as CGFloat
        let tintOpacity = 0.45
        let scalingFactor = 0.97
        let resizedSize = CGSize(
            width:  icon.size.width * scalingFactor,
            height: icon.size.height * scalingFactor
        )
        let resizedIcon = icon.resizing(to: resizedSize) ?? icon
        return ZStack(alignment: .topTrailing) {
            GeometryReader { geometry in
                ZStack {
                    Image(uiImage: resizedIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: imageHeight, height: imageHeight, alignment: .center)
                        .saturation(saturation)
                        .blur(radius: blurRadius, opaque: true)
                        .scaleEffect(geometry.size.width / imageHeight, anchor: .center)
                    Color(tintColor)
                        .opacity(tintOpacity)
                }
            }
            Image("Badge")
                .resizable()
                .frame(width: 26, height: 26)
                .padding()
        }
    }
}

private struct AppIconView: View
{
    let icon: UIImage?
    let imageHeight: CGFloat

    var body: some View {
        let image = icon ?? UIImage(named: "SideStore") ?? UIImage(systemName: "app.fill")!
        Image(uiImage: image)
            .resizable()
            .aspectRatio(CGSize(width: 1, height: 1), contentMode: .fit)
            .frame(height: imageHeight)
            .luminanceToAlphaInAccentedMode()
            .mask(RoundedRectangle(cornerRadius: imageHeight / 5.0, style: .continuous))
            .widgetAccentableIfAvailable()
    }
}

@available(iOS 17, *)
#Preview(as: .systemSmall) {
    AppDetailWidget()
} timeline: {
    let expiredDate = Date().addingTimeInterval(1 * 60 * 60 * 24 * 7)
    let (altstore, _, _, longAltStore, _, _) = AppSnapshot.makePreviewSnapshots()
    AppsEntry<Void>(date: Date(), apps: [altstore])
    AppsEntry<Void>(date: Date(), apps: [longAltStore])
    AppsEntry<Void>(date: expiredDate, apps: [altstore])
    AppsEntry<Void>(date: Date(), apps: [])
    AppsEntry<Void>(date: Date(), apps: [], isPlaceholder: true)
}
