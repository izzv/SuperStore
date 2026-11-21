//
//  AppPermissionsCard.swift
//  AltStore
//
//  Created by Riley Testut on 5/4/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//
import SwiftUI

@available(iOS 16, tvOS 16, *)
extension AppPermissionsCard
{
    private struct TransitionKey: Hashable
    {
        static func name(_ permission: Permission) -> TransitionKey {
            TransitionKey(key: "name", permission: permission)
        }
        static func icon(_ permission: Permission) -> TransitionKey {
            TransitionKey(key: "icon", permission: permission)
        }
        let key: String
        let permission: Permission
        private init(key: String, permission: Permission)
        {
            self.key = key
            self.permission = permission
        }
    }
}

@available(iOS 16, tvOS 16, *)
struct AppPermissionsCard<Permission: AppPermissionProtocol>: View
{
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let tintColor: Color
    let permissions: [Permission]
    @State
    private var selectedPermission: Permission?
    @Namespace
    private var animation
    private var isTitleVisible: Bool {
        if selectedPermission == nil
        {
            return true
        }
        let isTitleVisible = permissions.count > 2
        return isTitleVisible
    }
    var body: some View {
        let title = Text(title)
            .font(.title3)
            .bold()
            .minimumScaleFactor(0.1) 
        VStack(spacing: 8) {
            if isTitleVisible
            {
                title
            }
            let content = VStack(spacing: 8) {
                if !isTitleVisible
                {
                    title
                }
                VStack(spacing: 20) {
                    Text(description)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Grid(verticalSpacing: 15) {
                        ForEach(permissions, id: \.self) { permission in
                            permissionRow(for: permission)
                        }
                    }
                    Text("Tap a permission to learn more.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let selectedPermission
            {
                content.hidden().overlay {
                    permissionDetailView(for: selectedPermission)
                }
            }
            else
            {
                content
            }
        }
        .overlay(alignment: .topTrailing) {
            if selectedPermission != nil
            {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.medium)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(20)
        .overlay {
            if selectedPermission != nil
            {
                SwiftUI.Button(action: hidePermission) {
                    VStack {}
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .foregroundColor(.secondary) 
        .background(.regularMaterial) 
        .background(tintColor, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
    @ViewBuilder
    private func permissionRow(for permission: Permission) -> some View
    {
        GridRow {
            SwiftUI.Button(action: { show(permission) }) {
                HStack {
                    let text = Text(permission.localizedDisplayName)
                        .font(.body)
                        .bold()
                        .minimumScaleFactor(0.33)
                        .lineLimit(.max) 
                    let image = Image(systemName: permission.effectiveSymbolName)
                        .gridColumnAlignment(.center)
                    if selectedPermission != nil
                    {
                        Label(title: { text }, icon: { image })
                            .hidden()
                    }
                    else
                    {
                        Label {
                            text.matchedGeometryEffect(id: TransitionKey.name(permission), in: animation)
                        } icon: {
                            image.matchedGeometryEffect(id: TransitionKey.icon(permission), in: animation)
                        }
                    }

                    Spacer()

                    Image(systemName: "info.circle")
                        .imageScale(.large)
                }
                .contentShape(Rectangle()) 
            }
        }
        .frame(minHeight: 30) 
    }
    @ViewBuilder
    private func permissionDetailView(for permission: Permission) -> some View
    {
        VStack(spacing: 15) {
            Image(systemName: permission.effectiveSymbolName)
                .font(.largeTitle)
                .fixedSize(horizontal: false, vertical: true)
                .matchedGeometryEffect(id: TransitionKey.icon(permission), in: animation)
            Text(permission.localizedDisplayName)
                .font(.title2)
                .bold()
                .minimumScaleFactor(0.1) 
                .matchedGeometryEffect(id: TransitionKey.name(permission), in: animation)
            if let usageDescription = permission.usageDescription
            {
                Text(usageDescription)
                    .font(.subheadline)
                    .minimumScaleFactor(0.75)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    init(title: LocalizedStringKey, description: LocalizedStringKey, tintColor: Color, permissions: [Permission])
    {
        self.init(title: title, description: description, tintColor: tintColor, permissions: permissions, selectedPermission: nil)
    }
    fileprivate init(title: LocalizedStringKey, description: LocalizedStringKey, tintColor: Color, permissions: [Permission], selectedPermission: Permission? = nil)
    {
        self.title = title
        self.description = description
        self.tintColor = tintColor
        self.permissions = permissions
        self._selectedPermission = State(initialValue: selectedPermission)
    }
}

@available(iOS 16, tvOS 16, *)
private extension AppPermissionsCard
{
    func show(_ permission: Permission)
    {
        withAnimation {
            self.selectedPermission = permission
        }
    }
    func hidePermission()
    {
        withAnimation {
            self.selectedPermission = nil
        }
    }
}

@available(iOS 16, tvOS 16, *)
struct AppPermissionsCard_Previews: PreviewProvider
{
    static var previews: some View {
        let appPermissions = [
            PreviewAppPermission(permission: ALTAppPrivacyPermission.localNetwork),
            PreviewAppPermission(permission: ALTAppPrivacyPermission.microphone),
            PreviewAppPermission(permission: ALTAppPrivacyPermission.photos),
            PreviewAppPermission(permission: ALTAppPrivacyPermission.camera),
            PreviewAppPermission(permission: ALTAppPrivacyPermission.faceID),
            PreviewAppPermission(permission: ALTAppPrivacyPermission.appleMusic),
            PreviewAppPermission(permission: ALTAppPrivacyPermission.bluetooth),
            PreviewAppPermission(permission: ALTAppPrivacyPermission.calendars),
        ]
        let tintColor = Color(uiColor: .deltaPrimary!)
        return ForEach(1...8, id: \.self) { index in
                AppPermissionsCard(title: "Privacy",
                                   description: "Delta may request access to the following:",
                                   tintColor: tintColor,
                                   permissions: Array(appPermissions.prefix(index)))
                    .frame(width: 350)
                    .previewLayout(.sizeThatFits)

                AppPermissionsCard(title: "Privacy",
                                   description: "Delta may request access to the following:",
                                   tintColor: tintColor,
                                   permissions: Array(appPermissions.prefix(index)),
                                   selectedPermission: appPermissions.first)
                    .frame(width: 350)
                    .previewLayout(.sizeThatFits)
            }
    }
}
