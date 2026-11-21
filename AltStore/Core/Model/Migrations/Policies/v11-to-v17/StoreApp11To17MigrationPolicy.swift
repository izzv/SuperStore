//
//  StoreApp11To17MigrationPolicy.swift
//  AltStore
//
//  Created by Magesh K on 25/02/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
import CoreData

@objc(StoreApp11To17MigrationPolicy)
class StoreApp11To17MigrationPolicy: NSEntityMigrationPolicy {
    let defaultChannel = "stable"

    private func findEntityMappingName(for entityName: String, in manager: NSMigrationManager) -> String {
        let mappingModel = manager.mappingModel
        for entityMapping in mappingModel.entityMappings {
            if entityMapping.sourceEntityName == entityName {
                return entityMapping.name
            }
        }
        debugLog("Warning: Could not find mapping for entity: \(entityName)")
        return "\(entityName)To\(entityName)"
    }
    override func createRelationships(
        forDestination dInstance: NSManagedObject,
        in mapping: NSEntityMapping,
        manager: NSMigrationManager
    ) throws {
        let sourceInstances = manager.sourceInstances(forEntityMappingName: mapping.name, destinationInstances: [dInstance])
        guard let sInstance = sourceInstances.first else {
            debugLog("No source instance found for destination: \(dInstance)")
            return
        }
        guard let sourceVersions = sInstance.value(forKey: #keyPath(StoreApp._versions)) as? NSOrderedSet else {
            debugLog("Source store app has no versions")
            return
        }
        let context = dInstance.managedObjectContext!
        let releaseTrack = NSEntityDescription.insertNewObject(forEntityName: ReleaseTrack.entity().name ?? ReleaseTrack.description(), into: context)
        releaseTrack.setValue(defaultChannel, forKey: #keyPath(ReleaseTrack._track))

        releaseTrack.setValue(dInstance, forKey: #keyPath(ReleaseTrack.storeApp))

        let appVersionMappingName = findEntityMappingName(for: AppVersion.entity().name ?? AppVersion.description(), in: manager)
        let destinationVersionsSet = NSMutableOrderedSet()
        for sourceVersion in sourceVersions.array {
            guard let sourceVersion = sourceVersion as? NSManagedObject else { continue }
            let destVersions = manager.destinationInstances(forEntityMappingName: appVersionMappingName, sourceInstances: [sourceVersion])
            if let destVersion = destVersions.first {
                destinationVersionsSet.add(destVersion)
                destVersion.setValue(releaseTrack, forKey: #keyPath(AppVersion.releaseTrack))
                destVersion.setValue(defaultChannel, forKey: #keyPath(AppVersion._channel))
                destVersion.setValue("", forKey: #keyPath(AppVersion._buildVersion))
            } else {
                debugLog("Destination AppVersion not found for source version: \(sourceVersion)")
            }
        }
        releaseTrack.setValue(destinationVersionsSet, forKey: #keyPath(ReleaseTrack._releases))

        dInstance.setValue(nil, forKey: #keyPath(StoreApp._versions))
    }
}
