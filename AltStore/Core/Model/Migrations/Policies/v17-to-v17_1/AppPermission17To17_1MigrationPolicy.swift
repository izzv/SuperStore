//
//  AppPermission17to17_1MigrationPolicy.swift
//  AltStore
//
//  Created by Magesh K on 15/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
import CoreData

@objc(AppPermission17To17_1MigrationPolicy)
class AppPermission17To17_1MigrationPolicy: NSEntityMigrationPolicy {
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        try super.createDestinationInstances(forSource: sInstance, in: mapping, manager: manager)
        guard let destinationPermission = manager.destinationInstances(forEntityMappingName: mapping.name, sourceInstances: [sInstance]).first else {
            debugLog("Failed to locate destination AppPermission instance")
            return
        }
        if let type = sInstance.value(forKey: #keyPath(AppPermission._type)) as? String {
            if let permission = self.derivePermissionFromType(type) {
                destinationPermission.setValue(permission, forKey: #keyPath(AppPermission._permission))
                destinationPermission.setValue("privacy", forKey: #keyPath(AppPermission._type))
            }
        }
        if let storeApp = sInstance.value(forKey: #keyPath(AppPermission.app)) as? NSManagedObject{
            if let appBundle = storeApp.value(forKey: #keyPath(StoreApp.bundleIdentifier)) as? String{
                destinationPermission.setValue(appBundle, forKey: #keyPath(AppPermission.appBundleID))
            }

            if let sourceID = storeApp.value(forKey: #keyPath(StoreApp.sourceIdentifier)) as? String {
                destinationPermission.setValue(sourceID, forKey: #keyPath(AppPermission.sourceID))
            }
        }
    }
    override func createRelationships(
        forDestination dInstance: NSManagedObject,
        in mapping: NSEntityMapping,
        manager: NSMigrationManager
    ) throws {

        try super.createRelationships(forDestination: dInstance, in: mapping, manager: manager)
        guard let storeApp = dInstance.value(forKey: #keyPath(AppPermission.app)) as? NSManagedObject else {
            debugLog("Destination \(AppPermission.description()) has no storeApp")
            return
        }
        if let appBundle = storeApp.value(forKey: #keyPath(StoreApp.bundleIdentifier)) as? String{
            dInstance.setValue(appBundle, forKey: #keyPath(AppPermission.appBundleID))
        }

        if let sourceID = storeApp.value(forKey: #keyPath(StoreApp.sourceIdentifier)) as? String {
            dInstance.setValue(sourceID, forKey: #keyPath(AppPermission.sourceID))
        }
    }
    private func derivePermissionFromType(_ type: String) -> String? {
        switch type {
        case "photos": return "NSPhotosUsageDescription"
        case "camera": return "NSCameraUsageDescription"
        case "location": return "NSLocationUsageDescription"
        case "contacts": return "NSContactsUsageDescription"
        case "reminders": return "NSRemindersUsageDescription"
        case "music": return "NSAppleMusicUsageDescription"
        case "microphone": return "NSMicrophoneUsageDescription"
        case "speech-recognition": return "NSSpeechRecognitionUsageDescription"
        case "background-audio": return "NSBackgroundAudioUsageDescription"
        case "background-fetch": return "NSBackgroundFetchUsageDescription"
        case "bluetooth": return "NSBluetoothUsageDescription"
        case "network": return "NSNetworkUsageDescription"
        case "calendars": return "NSCalendarsUsageDescription"
        case "touchID": return "NSTouchIDUsageDescription"
        case "faceID": return "NSFaceIDUsageDescription"
        case "siri": return "NSSiriUsageDescription"
        case "motion": return "NSMotionUsageDescription"
        default: return nil 
        }
    }
}
