//
//  StoreApp.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//
import Foundation
import CoreData

import SideSign
@preconcurrency import UIKit

import SemanticVersion

public extension StoreApp
{
    static var altstoreAppID: String {
        Bundle.Info.appbundleIdentifier
    }
    static let dolphinAppID = "me.oatmealdome.dolphinios-njb"
}

@objc
public enum Platform: UInt, Codable {
    case ios
    case tvos
    case macos
}

@objc
public final class PlatformURL: NSManagedObject, Decodable {
    @NSManaged public private(set) var platform: Platform
    @NSManaged public private(set) var downloadURL: URL
    private enum CodingKeys: String, CodingKey
    {
        case platform
        case downloadURL
    }
    public init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        super.init(entity: PlatformURL.entity(), insertInto: context)
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.platform = try container.decode(Platform.self, forKey: .platform)
            self.downloadURL = try container.decode(URL.self, forKey: .downloadURL)
        }
        catch
        {
            if let context = self.managedObjectContext
            {
                context.delete(self)
            }
            throw error
        }
    }
}

extension PlatformURL: Comparable {
    public static func < (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        return lhs.platform.rawValue < rhs.platform.rawValue
    }
    public static func > (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        return lhs.platform.rawValue > rhs.platform.rawValue
    }
    public static func <= (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        return lhs.platform.rawValue <= rhs.platform.rawValue
    }
    public static func >= (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        return lhs.platform.rawValue >= rhs.platform.rawValue
    }
}

public typealias PlatformURLs = [PlatformURL]

extension StoreApp {
    @NSManaged @objc(releaseTracks) public private(set) var _releaseTracks: NSOrderedSet?
    private var releaseTracks: [ReleaseTrack]?{
        return _releaseTracks?.array as? [ReleaseTrack]
    }
    private func releaseTrackFor(track: String) -> ReleaseTrack? {
        return releaseTracks?.first(where: { $0.type.rawValue == track })
    }
    private var stableTrack: ReleaseTrack? {
        releaseTrackFor(track: ReleaseTrackType.stable.description)
    }
    private var betaReleases: [AppVersion]? {
        if UserDefaults.standard.isBetaUpdatesEnabled,
           let betaTrack = UserDefaults.standard.betaUdpatesTrack {
            let betaReleases = releaseTrackFor(track: betaTrack)?.releases?.compactMap { $0 }

            if let latestBeta = betaReleases?.first(where: { $0.isSupported }),
               let latestStable = stableTrack?.releases?.first(where: { $0.isSupported }),
               let stableSemVer = SemanticVersion(latestStable.version),
               let betaSemVer = SemanticVersion(latestBeta.version),
               betaSemVer >= stableSemVer
            {
                return betaReleases
            }
        }
        return nil
    }
    private func getReleases(default releases: ReleaseTrack?) -> [AppVersion]?
    {
        return betaReleases ?? releases?.releases?.compactMap { $0 }
    }
}

@objc(StoreApp)
public class StoreApp: BaseEntity, Decodable
{
    @NSManaged public private(set) var name: String
    @NSManaged public private(set) var bundleIdentifier: String
    @NSManaged public private(set) var subtitle: String?
    @NSManaged public private(set) var developerName: String
    @NSManaged public private(set) var localizedDescription: String
    @NSManaged @objc(size) internal var _size: Int64
    @nonobjc public var category: StoreCategory? {
        guard let _category else { return nil }
        let category = StoreCategory(rawValue: _category)
        return category
    }
    @NSManaged @objc(category) public private(set) var _category: String?
    @NSManaged public private(set) var iconURL: URL
    @NSManaged public private(set) var screenshotURLs: [URL]
    @NSManaged public private(set) var downloadURL: URL?
    @NSManaged public private(set) var platformURLs: PlatformURLs?

    @NSManaged public private(set) var tintColor: UIColor?

    @NSManaged public private(set) var marketplaceID: String?

    @NSManaged public var isPledged: Bool
    @NSManaged public private(set) var isPledgeRequired: Bool
    @NSManaged public private(set) var isHiddenWithoutPledge: Bool
    @NSManaged public private(set) var pledgeCurrency: String?
    @NSManaged public private(set) var prefersCustomPledge: Bool
    @NSManaged @objc(pledgeAmount) private var _pledgeAmount: NSDecimalNumber?
    @NSManaged public var sortIndex: Int32
    @NSManaged public var featuredSortID: String?
    @objc public internal(set) var sourceIdentifier: String? {
        get {
            self.willAccessValue(forKey: #keyPath(sourceIdentifier))
            defer { self.didAccessValue(forKey: #keyPath(sourceIdentifier)) }
            let sourceIdentifier = self.primitiveSourceIdentifier
            return sourceIdentifier
        }
        set {
            self.willChangeValue(forKey: #keyPath(sourceIdentifier))
            self.primitiveSourceIdentifier = newValue
            self.didChangeValue(forKey: #keyPath(sourceIdentifier))
            for version in self.versions
            {
                version.sourceID = newValue
            }
            for permission in self.permissions
            {
                permission.sourceID = self.sourceIdentifier ?? ""
            }
            for screenshot in self.allScreenshots
            {
                screenshot.sourceID = self.sourceIdentifier ?? ""
            }
        }
    }
    @NSManaged private var primitiveSourceIdentifier: String?
    @NSManaged public private(set) var version: String?
    @NSManaged public private(set) var versionDate: Date?
    @NSManaged public private(set) var versionDescription: String?
    @NSManaged public var installedApp: InstalledApp?
    @NSManaged public var newsItems: Set<NewsItem>
    @NSManaged @objc(source) public var _source: Source?
    @NSManaged public internal(set) var featuringSource: Source?
    @NSManaged @objc(latestVersion) public private(set) var latestSupportedVersion: AppVersion?
    @NSManaged @objc(versions) public private(set) var _versions: NSOrderedSet
    @NSManaged public private(set) var loggedErrors: NSSet  
    @nonobjc public var source: Source? {
        set {
            self._source = newValue
            self.sourceIdentifier = newValue?.identifier
        }
        get {
            return self._source
        }
    }

    @nonobjc public var permissions: Set<AppPermission> {
        return self._permissions as! Set<AppPermission>
    }
    @NSManaged @objc(permissions) internal private(set) var _permissions: NSSet 
    @nonobjc public var versions: [AppVersion] {
        return self._versions.array as! [AppVersion]
    }
    @nonobjc public var allScreenshots: [AppScreenshot] {
        return self._screenshots.array as! [AppScreenshot]
    }
    @NSManaged @objc(screenshots) private(set) var _screenshots: NSOrderedSet

    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    private enum CodingKeys: String, CodingKey
    {
        case name
        case bundleIdentifier
        case marketplaceID
        case developerName
        case localizedDescription
        case iconURL
        case platformURLs
        case screenshots
        case tintColor
        case subtitle
        case permissions = "appPermissions"
        case size
        case isBeta = "beta"    
        case versions
        case category
        case version
        case versionDescription
        case versionDate
        case downloadURL
        case screenshotURLs

        case releaseTracks = "releaseChannels"
    }
    public required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }

        super.init(entity: StoreApp.entity(), insertInto: context)

        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            self.bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
            self.developerName = try container.decode(String.self, forKey: .developerName)
            self.localizedDescription = try container.decode(String.self, forKey: .localizedDescription)
            do {
                self.iconURL = try container.decode(URL.self, forKey: .iconURL)
            } catch {
                if let rawURLString = try? container.decode(String.self, forKey: .iconURL),
                   let placeholderURL = URL(string: "about:blank") {
                    self.iconURL = placeholderURL
                    debugLog("[StoreApp]: Warning: Failed to decode iconURL '\(rawURLString)' for app \(self.bundleIdentifier). Using placeholder.")
                } else {
                    throw error
                }
            }
            self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
            self.marketplaceID = try container.decodeIfPresent(String.self, forKey: .marketplaceID)

            if let tintColorHex = try container.decodeIfPresent(String.self, forKey: .tintColor)
            {
                guard let tintColor = UIColor(hexString: tintColorHex) else {
                    throw DecodingError.dataCorruptedError(forKey: .tintColor, in: container, debugDescription: "Hex code is invalid.")
                }
                self.tintColor = tintColor
            }
            if let rawCategory = try container.decodeIfPresent(String.self, forKey: .category)
            {
                self._category = rawCategory.lowercased() 
            }
            let appScreenshots: [AppScreenshot]
            if let screenshots = try container.decodeIfPresent(AppScreenshots.self, forKey: .screenshots)
            {
                appScreenshots = screenshots.screenshots
            }
            else if let screenshotURLs = try container.decodeIfPresent([URL].self, forKey: .screenshotURLs)
            {
                let legacyAspectRatio = CGSize(width: 750, height: 1334)
                appScreenshots = screenshotURLs.map { imageURL in
                    let screenshot = AppScreenshot(imageURL: imageURL, size: legacyAspectRatio, deviceType: .iphone, context: context)
                    return screenshot
                }

            }
            else
            {
                appScreenshots = []
            }
            for screenshot in appScreenshots
            {
                screenshot.appBundleID = self.bundleIdentifier
            }
            self.setScreenshots(appScreenshots)
            if let appPermissions = try container.decodeIfPresent(AppPermissions.self, forKey: .permissions)
            {
                let allPermissions = appPermissions.entitlements + appPermissions.privacy
                for permission in allPermissions
                {
                    permission.appBundleID = self.bundleIdentifier
                }
                self._permissions = NSSet(array: allPermissions)
            }
            else
            {
                self._permissions = NSSet()
            }

            try self.decodeVersions(from: decoder)  
            let platformURLs = try container.decodeIfPresent(PlatformURLs.self.self, forKey: .platformURLs)
            if let platformURLs = platformURLs {
                self.platformURLs = platformURLs
                if let first = platformURLs.sorted().first {
                    self.downloadURL = first.downloadURL
                } else {
                    throw DecodingError.dataCorruptedError(forKey: .platformURLs, in: container, debugDescription: "platformURLs has no entries")

                }
            } else if let downloadURL = try container.decodeIfPresent(URL.self, forKey: .downloadURL) {
                self.downloadURL = downloadURL
            } else {
                guard let _ = self.downloadURL else
                {
                    let error = DecodingError.dataCorruptedError(forKey: .downloadURL, in: container, debugDescription: "E downloadURL:String or downloadURLs:[[Platform:URL]] key required.")
                    throw error
                }
            }

            self.isPledged = false
            self.prefersCustomPledge = false
            self.isPledgeRequired = false
            self.isHiddenWithoutPledge = false
            self._pledgeAmount = nil
            self.pledgeCurrency = nil
        }
        catch
        {
            if let context = self.managedObjectContext
            {
                context.delete(self)
            }
            throw error
        }
    }
    private func decodeVersions(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let releaseTracks = try container.decodeIfPresent([ReleaseTrack].self, forKey: .releaseTracks){
            self._releaseTracks = NSOrderedSet(array: releaseTracks)
        }
        var channel = ReleaseTrackType.stable.description

        var versions = getReleases(default: stableTrack) ?? []
        if versions.isEmpty {
            if let appVersions = try container.decodeIfPresent([AppVersion].self, forKey: .versions)
            {
                versions = appVersions
            }
            else
            {
                if try container.decodeIfPresent(Bool.self, forKey: .isBeta) ?? false
                {
                    channel = ReleaseTrackType.nightly.description
                }
                let newRelease = try createNewAppVersion(decoder: decoder)
                                        .mutateForData(
                                            channel: channel,
                                            appBundleID: self.bundleIdentifier
                                        )

                versions = [newRelease]
            }
        }
        for (index, version) in zip(0..., versions)
        {
            version.appBundleID = self.bundleIdentifier
            if version.channel == .unknown {
                _ = version.mutateForData(channel: channel)
            }

            if self.marketplaceID != nil
            {
                struct IndexCodingKey: CodingKey
                {
                    var stringValue: String { self.intValue?.description ?? "" }
                    var intValue: Int?

                    init?(stringValue: String)
                    {
                        fatalError()
                    }

                    init(intValue: Int)
                    {
                        self.intValue = intValue
                    }
                }

                guard version.buildVersion != nil else {
                    let codingPath = container.codingPath + [CodingKeys.versions as CodingKey] + [IndexCodingKey(intValue: index) as CodingKey]
                    let context = DecodingError.Context(codingPath: codingPath, debugDescription: "Notarized apps must provide a build version.")
                    throw DecodingError.keyNotFound(AppVersion.CodingKeys.buildVersion, context)
                }
            }

        }
        try self.setVersions(versions)
    }

    func createNewAppVersion(decoder: Decoder) throws -> AppVersion {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .version)
        let versionDate = try container.decode(Date.self, forKey: .versionDate)
        let versionDescription = try container.decodeIfPresent(String.self, forKey: .versionDescription)
        let downloadURL = try container.decode(URL.self, forKey: .downloadURL)
        let size = try container.decode(Int32.self, forKey: .size)
        return AppVersion.makeAppVersion(version: version,
                                        buildVersion: nil,
                                        date: versionDate,
                                        localizedDescription: versionDescription,
                                        downloadURL: downloadURL,
                                        size: Int64(size),
                                        appBundleID: self.bundleIdentifier,
                                        in: context)
    }
    public override func awakeFromInsert()
    {
        super.awakeFromInsert()
        self.featuredSortID = UUID().uuidString
    }
}

internal extension StoreApp
{
    func setVersions(_ versions: [AppVersion]) throws 
    {        
        guard let latestVersion = versions.first else {
            throw MergeError.noVersions(for: self)
        }

        self._versions = NSOrderedSet(array: versions)

        let latestSupportedVersion = versions.first(where: { $0.isSupported })
        self.latestSupportedVersion = latestSupportedVersion
        for case let version as AppVersion in self._versions
        {
            if version == latestSupportedVersion
            {
                version.latestSupportedVersionApp = self
            }
            else
            {
                version.latestSupportedVersionApp = nil
            }
        }

        self.version = latestVersion.version
        self.versionDate = latestVersion.date
        self.versionDescription = latestVersion.localizedDescription
        self.downloadURL = latestVersion.downloadURL
        self._size = latestVersion.size
    }
    func setPermissions(_ permissions: Set<AppPermission>)
    {
        for case let permission as AppPermission in self._permissions
        {
            if permissions.contains(permission)
            {
                permission.app = self
            }
            else
            {
                permission.app = nil
            }
        }
        self._permissions = permissions as NSSet
    }
    func setScreenshots(_ screenshots: [AppScreenshot])
    {
        for case let screenshot as AppScreenshot in self._screenshots
        {
            if screenshots.contains(screenshot)
            {
                screenshot.app = self
            }
            else
            {
                screenshot.app = nil
            }
        }
        self._screenshots = NSOrderedSet(array: screenshots)
        self.screenshotURLs = screenshots.map { $0.imageURL }
    }
}

public extension StoreApp
{
    func screenshots(for deviceType: ALTDeviceType) -> [AppScreenshot]
    {
        let filteredScreenshots = self.allScreenshots.filter { $0.deviceType == deviceType }
        return filteredScreenshots
    }
    func preferredScreenshots() -> [AppScreenshot]
    {
        let deviceType: ALTDeviceType
        if UIDevice.current.model.contains("iPad")
        {
            deviceType = .ipad
        }
        else
        {
            deviceType = .iphone
        }
        let preferredScreenshots = self.screenshots(for: deviceType)
        guard !preferredScreenshots.isEmpty else {
            return self.allScreenshots
        }
        return preferredScreenshots
    }
}

public extension StoreApp
{
    var latestAvailableVersion: AppVersion? {
        return self._versions.firstObject as? AppVersion
    }
    var globallyUniqueID: String? {
        guard let sourceIdentifier = self.sourceIdentifier else { return nil }
        let globallyUniqueID = self.bundleIdentifier + "|" + sourceIdentifier
        return globallyUniqueID
    }
}

public extension StoreApp
{
    class var visibleAppsPredicate: NSPredicate {
        let predicate = NSPredicate(format: "(%K != %@) AND ((%K == NO) OR (%K == NO) OR (%K == YES))",
                                    #keyPath(StoreApp.bundleIdentifier), StoreApp.altstoreAppID,
                                    #keyPath(StoreApp.isPledgeRequired),
                                    #keyPath(StoreApp.isHiddenWithoutPledge),
                                    #keyPath(StoreApp.isPledged))
        return predicate
    }
    class var otherCategoryPredicate: NSPredicate {
        let knownCategories = StoreCategory.allCases.lazy.filter { $0 != .other }.map { $0.rawValue }
        let predicate = NSPredicate(format: "%K == nil OR NOT (%K IN %@)", #keyPath(StoreApp._category), #keyPath(StoreApp._category), Array(knownCategories))
        return predicate
    }
    @nonobjc class func fetchRequest() -> NSFetchRequest<StoreApp>
    {
        return NSFetchRequest<StoreApp>(entityName: "StoreApp")
    }
    private static var sideStoreAppIconURL: URL {
        let iconNames = [
            "AppIcon76x76@2x~ipad",
            "AppIcon60x60@2x",
            "AppIcon"
        ]
        for iconName in iconNames {
            if let path = Bundle.main.path(forResource: iconName, ofType: "png") {
                return URL(fileURLWithPath: path)
            }
        }
        return AppConstants.Sources.sideStoreFallbackIconURL
    }
    class func makeAltStoreApp(version: String, buildVersion: String?, in context: NSManagedObjectContext) -> StoreApp
    {
        let placeholderBundleId = StoreApp.altstoreAppID
        let placeholderDownloadURL = AppConstants.Sources.sideStoreWebsite
        let placeholderSourceID = Source.altStoreIdentifier
        let placeholderVersion = "0.0.0"
        let placeholderDate = Date.distantPast
        let placeholderChannel = ReleaseTrackType.stable.description
        let app = StoreApp(context: context)
        app.name = "SuperStore"
        app.bundleIdentifier = placeholderBundleId
        app.developerName = "Side Team"
        app.localizedDescription = "SuperStore is an alternative App Store."
        app.iconURL = sideStoreAppIconURL        
        app.screenshotURLs = []
        app.sourceIdentifier = placeholderSourceID
        let appVersion = AppVersion.makeAppVersion(version: placeholderVersion,
                                                   buildVersion: buildVersion,
                                                   channel: placeholderChannel,
                                                   date: placeholderDate,
                                                   downloadURL: placeholderDownloadURL,
                                                   size: app._size,
                                                   appBundleID: app.bundleIdentifier,
                                                   sourceID: app.sourceIdentifier,
                                                   in: context)
        try? app.setVersions([appVersion])

        return app
    }
}
