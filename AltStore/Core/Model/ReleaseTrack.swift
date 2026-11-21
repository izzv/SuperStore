//
//  AppreleaseTrack.swift
//  AltStore
//
//  Created by Magesh K on 19/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
import CoreData

public enum ReleaseTrackType: String, CaseIterable, CustomStringConvertible
{
    case unknown
    case local          
    case alpha
    case nightly = "nightly"
    case stable
    public static var betaTracks: [ReleaseTrackType] {
        ReleaseTrackType.allCases.filter(isBetaTrack)
    }

    public static var nonBetaTracks: [ReleaseTrackType] {
        ReleaseTrackType.allCases.filter { !isBetaTrack($0) }
    }

    private static func isBetaTrack(_ key: ReleaseTrackType) -> Bool {
        key == .alpha || key == .nightly
    }

    public var description: String {
        return self.rawValue
    }

    public static func from(version: String) -> ReleaseTrackType {
        let lowercased = version.lowercased()
        if lowercased.contains("alpha") {
            return .alpha
        } else if lowercased.contains("nightly") || lowercased.contains("beta") {
            return .nightly
        } else if lowercased.contains("local") || lowercased.contains("xcode") {
            #if DEBUG
            return .nightly 
            #else
            return .stable  
            #endif
        } else {
            return .stable
        }
    }
}

@objc(ReleaseTrack)
public class ReleaseTrack: BaseEntity, Decodable
{
    @NSManaged @objc(track) public private(set) var _track: String?
    @NSManaged @objc(appBundleID) public private(set) var _appBundleID: String?
    @NSManaged @objc(sourceID) public private(set) var _sourceID: String?

    @NSManaged @objc(releases) public private(set) var _releases: NSOrderedSet?
    @NSManaged public private(set) var storeApp: StoreApp?
    @NSManaged public private(set) var installedApp: InstalledApp?
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case track
        case releases
    }
    public var type: ReleaseTrackType {
        return ReleaseTrackType(rawValue: _track ?? "") ?? .unknown
    }
    public var releases:[AppVersion]? {
        return _releases?.array as? [AppVersion]
    }
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
    }

    public required init(from decoder: Decoder) throws{
        guard let context = decoder.managedObjectContext else {
            preconditionFailure("Decoder must have non-nil NSManagedObjectContext.")
        }
        super.init(entity: ReleaseTrack.entity(), insertInto: context)
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self._track = try container.decode(String.self, forKey: .track)
            let releases = try container.decode([AppVersion].self, forKey: .releases)
            guard releases.count > 0 else
            {
                throw DecodingError.dataCorruptedError(forKey: .releases, in: container, debugDescription: "At least one version is required in key: releases")
            }
            self._releases = NSOrderedSet(array: releases)
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

public extension ReleaseTrack{
    internal func updateVersions(for storeApp: StoreApp?) {
        guard let storeApp = storeApp else { return }
            releases?.forEach { version in
                guard let context = version.managedObjectContext,
                      !version.isDeleted, !context.deletedObjects.contains(version) else
                {
                    return
                }
                _ = version.mutateForData(channel: type.rawValue, appBundleID: storeApp.bundleIdentifier, sourceID: storeApp.sourceIdentifier)
            }
    }
    override func didChangeValue(forKey key: String) {
        super.didChangeValue(forKey: key)
        if key == NSExpression(forKeyPath: #keyPath(ReleaseTrack.storeApp)).keyPath
        {
            updateVersions(for: storeApp)
            self._appBundleID = storeApp?.bundleIdentifier
            self._sourceID = storeApp?.sourceIdentifier
        }
    }
}
