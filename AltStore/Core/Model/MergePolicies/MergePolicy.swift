//
//  MergePolicy.swift
//  AltStore
//
//  Created by Riley Testut on 7/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//
import CoreData

import SideSign

extension MergeError
{
    public enum Code: Int, ALTErrorCode
    {
        public typealias Error = MergeError
        case noVersions
        case incorrectVersionOrder
        case incorrectPermissions
    }
    static func noVersions(for app: StoreApp) -> MergeError { .init(code: .noVersions, appName: app.name, appBundleID: app.bundleIdentifier, sourceID: app.sourceIdentifier) }
    static func incorrectVersionOrder(for app: StoreApp) -> MergeError { .init(code: .incorrectVersionOrder, appName: app.name, appBundleID: app.bundleIdentifier, sourceID: app.sourceIdentifier) }
    static func incorrectPermissions(for app: StoreApp) -> MergeError { .init(code: .incorrectPermissions, appName: app.name, appBundleID: app.bundleIdentifier, sourceID: app.sourceIdentifier) }
}

public struct MergeError: ALTLocalizedError
{
    public static var errorDomain: String { "AltStore.MergeError" }
    public let code: Code
    public var errorTitle: String?
    public var errorFailure: String?
    public var appName: String?
    public var appBundleID: String?
    public var sourceID: String?
    public var errorFailureReason: String {
        switch self.code
        {
        case .noVersions:
            var appName = NSLocalizedString("At least one app", comment: "")
            if let name = self.appName, let bundleID = self.appBundleID
            {
                appName = name + " (\(bundleID))"
            }
            return String(format: NSLocalizedString("%@ does not have any app versions.", comment: ""), appName)
        case .incorrectVersionOrder:
            var appName = NSLocalizedString("one or more apps", comment: "")
            if let name = self.appName, let bundleID = self.appBundleID
            {
                appName = name + " (\(bundleID))"
            }
            return String(format: NSLocalizedString("The cached versions for %@ do not match the source.", comment: ""), appName)
        case .incorrectPermissions:
            var appName = NSLocalizedString("one or more apps", comment: "")
            if let name = self.appName, let bundleID = self.appBundleID
            {
                appName = name + " (\(bundleID))"
            }
            return String(format: NSLocalizedString("The cached permissions for %@ do not match the source.", comment: ""), appName)
        }
    }
    public var recoverySuggestion: String? {
        switch self.code
        {
        case .incorrectVersionOrder: return NSLocalizedString("Please try again later.", comment: "")
        default: return nil
        }
    }
}

extension MergeError: _ObjectiveCBridgeableError
{
    public var errorUserInfo: [String : Any] {
        var userInfo: [String: Any?] = [
            NSLocalizedFailureErrorKey: self.errorFailure,
            ALTLocalizedTitleErrorKey: self.errorTitle,
            ALTSourceFileErrorKey: self.sourceFile,
            ALTSourceLineErrorKey: self.sourceLine,
        ]
        userInfo["appName"] = self.appName
        userInfo["appBundleID"] = self.appBundleID
        userInfo["sourceID"] = self.sourceID
        return userInfo.compactMapValues { $0 }
    }
    public init?(_bridgedNSError error: NSError)
    {
        guard error.domain == MergeError.errorDomain, let code = Code(rawValue: error.code) else { return nil }
        self.code = code
        self.errorTitle = error.localizedTitle
        self.errorFailure = error.localizedFailure
        self.appName = error.userInfo["appName"] as? String
        self.appBundleID = error.userInfo["appBundleID"] as? String
        self.sourceID = error.userInfo["sourceID"] as? String
    }
}

private extension Error
{
    func serialized(withFailure failure: String) -> NSError
    {
        let serializedError = (self as NSError).withLocalizedFailure(failure).sanitizedForSerialization()
        var userInfo = serializedError.userInfo
        userInfo[NSLocalizedDescriptionKey] = nil 
        let error = NSError(domain: serializedError.domain, code: serializedError.code, userInfo: userInfo)
        return error
    }
}

open class MergePolicy: RelationshipPreservingMergePolicy
{
    private let mergeLock = NSLock()

    var permissionsByGlobalAppID = [String: Set<AnyHashable>]()
    var sortedVersionIDsByGlobalAppID = [String: NSOrderedSet]()
    var sortedScreenshotIDsByGlobalAppID = [String: NSOrderedSet]()
    var featuredAppIDsBySourceID = [String: [String]]()

    open override func resolve(constraintConflicts conflicts: [NSConstraintConflict]) throws
    {
        mergeLock.lock()
        defer { mergeLock.unlock() }

        guard conflicts.allSatisfy({ $0.databaseObject != nil }) else {
            try self.resolveWhenDatabaseObjectUnavailable(conflicts)
            try super.resolve(constraintConflicts: conflicts)
            return
        }
        permissionsByGlobalAppID.removeAll()
        sortedVersionIDsByGlobalAppID.removeAll()
        sortedScreenshotIDsByGlobalAppID.removeAll()
        featuredAppIDsBySourceID.removeAll()
        try self.resolveWhenDatabaseObjectAvailable(conflicts)
        try super.resolve(constraintConflicts: conflicts)
        try self.performPostMergeValidationAndCorrections(for: conflicts)
    }
}

extension MergePolicy{
    private func resolveWhenDatabaseObjectUnavailable(_ conflicts: [NSConstraintConflict]) throws{
        for conflict in conflicts
        {
            switch conflict.conflictingObjects.first
            {
            case is StoreApp where conflict.conflictingObjects.count == 2:
                if let previousApp = conflict.conflictingObjects.first(where: { !$0.isInserted }) as? StoreApp
                {
                    for case let permission as AppPermission in previousApp._permissions where permission.app == nil
                    {
                        permission.managedObjectContext?.delete(permission)
                    }
                    for case let appVersion as AppVersion in previousApp._versions where appVersion.app == nil
                    {
                        appVersion.managedObjectContext?.delete(appVersion)
                    }

                    for case let appScreenshot as AppScreenshot in previousApp._screenshots where appScreenshot.app == nil
                    {
                        appScreenshot.managedObjectContext?.delete(appScreenshot)
                    }
                }
            case is AppVersion where conflict.conflictingObjects.count == 2:
                let conflictingAppVersions = conflict.conflictingObjects.lazy.compactMap { $0 as? AppVersion }
                if let primaryAppVersion = conflictingAppVersions.first(where: { $0.latestSupportedVersionApp?.latestSupportedVersion == $0 }),
                   let secondaryAppVersion = conflictingAppVersions.first(where: { $0 != primaryAppVersion })
                {
                    secondaryAppVersion.managedObjectContext?.delete(secondaryAppVersion)
                    debugLog("[SuperStore] Resolving AppVersion context-level conflict. Most likely due to migrating from pre-AppVersion model version. \(primaryAppVersion)")
                }
            default:
                let entityName = conflict.conflictingObjects.first?.entity.name ?? "Unknown"
                assertionFailure("Context Conflict Detected for table '\(entityName)': is there ambiguous data?\nConflict:\(conflict)")
            }
        }
    }
    private func resolveWhenDatabaseObjectAvailable(_ conflicts: [NSConstraintConflict]) throws {
        for conflict in conflicts
        {
            switch conflict.databaseObject
            {
            case let databaseObject as StoreApp:
                guard let contextApp = conflict.conflictingObjects.first as? StoreApp else { break }

                let contextPermissions = Set(contextApp._permissions.lazy.compactMap { $0 as? AppPermission }.map { AnyHashable($0.permission) })
                for case let databasePermission as AppPermission in databaseObject._permissions  
                {
                    if !contextPermissions.contains(AnyHashable(databasePermission.permission))
                    {
                        databasePermission.managedObjectContext?.delete(databasePermission)
                    }
                }
                let contextVersionIDs = NSOrderedSet(array: contextApp._versions.lazy.compactMap { $0 as? AppVersion }.map { $0.versionID })
                for case let databaseVersion as AppVersion in databaseObject._versions where !contextVersionIDs.contains(databaseVersion.versionID)
                {
                    databaseVersion.managedObjectContext?.delete(databaseVersion)
                }
                let contextScreenshotIDs = NSOrderedSet(array: contextApp._screenshots.lazy.compactMap { $0 as? AppScreenshot }.map { $0.screenshotID })
                for case let databaseScreenshot as AppScreenshot in databaseObject._screenshots where !contextScreenshotIDs.contains(databaseScreenshot.screenshotID)
                {
                    databaseScreenshot.managedObjectContext?.delete(databaseScreenshot)
                }
                if let globallyUniqueID = contextApp.globallyUniqueID
                {
                    permissionsByGlobalAppID[globallyUniqueID] = contextPermissions
                    sortedVersionIDsByGlobalAppID[globallyUniqueID] = contextVersionIDs
                    sortedScreenshotIDsByGlobalAppID[globallyUniqueID] = contextScreenshotIDs
                }
                if let featuredSortID = databaseObject.featuredSortID
                {
                    contextApp.featuredSortID = featuredSortID
                }
            case let databaseObject as Source:
                guard let conflictedObject = conflict.conflictingObjects.first as? Source else { break }
                let bundleIdentifiers = Set(conflictedObject.apps.map { $0.bundleIdentifier })
                let newsItemIdentifiers = Set(conflictedObject.newsItems.map { $0.identifier })
                for app in databaseObject.apps
                {
                    if !bundleIdentifiers.contains(app.bundleIdentifier)
                    {
                        app.managedObjectContext?.delete(app)
                    }
                }
                for newsItem in databaseObject.newsItems
                {
                    if !newsItemIdentifiers.contains(newsItem.identifier)
                    {
                        newsItem.managedObjectContext?.delete(newsItem)
                    }
                }
                if let contextSource = conflict.conflictingObjects.first as? Source
                {
                    featuredAppIDsBySourceID[databaseObject.identifier] = contextSource.featuredApps?.map { $0.bundleIdentifier }
                }
                if let featuredSortID = databaseObject.featuredSortID
                {
                    conflictedObject.featuredSortID = featuredSortID
                }
            default: break
            }
        }
    }
}

extension MergePolicy{

    func performPostMergeValidationAndCorrections(for conflicts: [NSConstraintConflict]) throws{
        for conflict in conflicts
        {
            switch conflict.databaseObject
            {
            case let databaseObject as StoreApp:
                do
                {
                    var appVersions = databaseObject.versions
                    if let globallyUniqueID = databaseObject.globallyUniqueID
                    {
                        if let appPermissions = permissionsByGlobalAppID[globallyUniqueID],
                            case let databasePermissions = Set(databaseObject.permissions.map({ AnyHashable($0.permission) })),
                            databasePermissions != appPermissions
                        {
                            throw MergeError.incorrectPermissions(for: databaseObject)
                        }
                        if let sortedAppVersionIDs = sortedVersionIDsByGlobalAppID[globallyUniqueID],
                            let sortedAppVersionsIDsArray = sortedAppVersionIDs.array as? [String],
                        case let databaseVersionIDs = databaseObject.versions.map({ $0.versionID }),
                            databaseVersionIDs != sortedAppVersionsIDsArray
                        {
                        let fixedAppVersions = databaseObject.versions.sorted { (versionA, versionB) in
                                let indexA = sortedAppVersionIDs.index(of: versionA.versionID)
                                let indexB = sortedAppVersionIDs.index(of: versionB.versionID)
                                return indexA < indexB
                            }
                            let appVersionIDs = fixedAppVersions.map { $0.versionID }
                            guard appVersionIDs == sortedAppVersionsIDsArray else {
                                throw MergeError.incorrectVersionOrder(for: databaseObject)
                            }
                            appVersions = fixedAppVersions
                            try databaseObject.setVersions(appVersions)
                        }
                        if let sortedScreenshotIDs = sortedScreenshotIDsByGlobalAppID[globallyUniqueID],
                            let sortedScreenshotIDsArray = sortedScreenshotIDs.array as? [String],
                        case let databaseScreenshotIDs = databaseObject.allScreenshots.map({ $0.screenshotID }),
                            databaseScreenshotIDs != sortedScreenshotIDsArray
                        {
                        let fixedScreenshots = databaseObject.allScreenshots.sorted { (screenshotA, screenshotB) in
                                let indexA = sortedScreenshotIDs.index(of: screenshotA.screenshotID)
                                let indexB = sortedScreenshotIDs.index(of: screenshotB.screenshotID)
                                return indexA < indexB
                            }
                            let appScreenshotIDs = fixedScreenshots.map { $0.screenshotID }
                            if appScreenshotIDs == sortedScreenshotIDsArray
                            {
                                databaseObject.setScreenshots(fixedScreenshots)
                            }
                            else
                            {
                                debugLog("Failed to re-sort screenshots into correct order. Expected: \(sortedScreenshotIDsArray)")
                            }
                        }
                    }
                }
                catch
                {
                    let nsError = error.serialized(withFailure: NSLocalizedString("SuperStore's database could not be saved.", comment: ""))
                    throw nsError
                }
            case let databaseObject as Source:
                guard let featuredAppIDs = featuredAppIDsBySourceID[databaseObject.identifier] else {
                    databaseObject.setFeaturedApps(nil)
                    break
                }
                let featuredApps: [StoreApp]?
                let databaseFeaturedAppIDs = databaseObject.featuredApps?.map { $0.bundleIdentifier }
                if databaseFeaturedAppIDs != featuredAppIDs
                {
                    let fixedFeaturedApps = databaseObject.apps.lazy.filter { featuredAppIDs.contains($0.bundleIdentifier) }.sorted { (appA, appB) in
                        let indexA = featuredAppIDs.firstIndex(of: appA.bundleIdentifier)!
                        let indexB = featuredAppIDs.firstIndex(of: appB.bundleIdentifier)!
                        return indexA < indexB
                    }
                    featuredApps = fixedFeaturedApps
                }
                else
                {
                    featuredApps = databaseObject.featuredApps
                }
                databaseObject.setFeaturedApps(featuredApps)
            default: break
            }
        }
    }
}

extension MergePolicy{
    class func getHeader(_ obj: AnyObject) -> String {
        return obj.debugDescription.components(separatedBy: "; data:").first ?? ""
    }
}
