//
//  CoreDataHelper.swift
//  SideStore
//
//  Created by Magesh K on 02/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
import Foundation
import CoreData
import System

class CoreDataHelper{
    private static let STORE_XCMODELD_NAME = "AltStore"
    private static let COREDATA_BUNDLE_ID = "\(Bundle.Info.appbundleIdentifier).AltStoreCore"
    private static let datastoreQueue = DispatchQueue(label: "sidestore-database-queue")
    public static func exportCoreDataStore() async throws -> URL {

        guard let bundle = Bundle(identifier: COREDATA_BUNDLE_ID) else {
            let errorDescription = "AltStoreCore bundle not found"
            throw getCoreDataError(code: 1, localizedDescription: errorDescription)
        }
        guard let modelURL = bundle.url(forResource: STORE_XCMODELD_NAME, withExtension: "momd"),
              let _ = NSManagedObjectModel(contentsOf: modelURL) else {
            let errorDescription = "Failed to load model \(STORE_XCMODELD_NAME) from AltStoreCore bundle"
            throw getCoreDataError(code: 2, localizedDescription: errorDescription)
        }
        let container = DatabaseManager.shared.persistentContainer

                    return try backupCoreDataStore(container: container)
    }
    private static func lockSQLiteFile(at url: URL) -> FileDescriptor? {
        let fileDescriptor = open(url.path, O_RDWR)
        guard fileDescriptor >= 0 else {
            debugLog("Failed to open SQLite file for locking.")
            return nil
        }

        let lockResult = flock(fileDescriptor, LOCK_EX)
        guard lockResult == 0 else {
            debugLog("Failed to lock SQLite file.")
            close(fileDescriptor)
            return nil
        }

        return FileDescriptor(rawValue: fileDescriptor)
    }

    private static func unlockSQLiteFile(fileDescriptor: FileDescriptor) {
        let fileDescriptor = fileDescriptor.rawValue
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
    private static func getCoreDataError(code: Int, localizedDescription: String) -> Error {
        return NSError(domain: "CoreDataExport", code: code, userInfo: [NSLocalizedDescriptionKey: localizedDescription])
    }
    private static func backupCoreDataStore(container: NSPersistentContainer, loadError: Error? = nil) throws -> URL
    {
        if let error = loadError {
            let errorDescription = "Failed to load persistent store: \(error.localizedDescription)"
            throw getCoreDataError(code: 3, localizedDescription: errorDescription)
        }
        guard let storeURL = container.persistentStoreCoordinator.persistentStores.first?.url else {
            let errorDescription = "Persistent store URL not found"
            throw getCoreDataError(code: 4, localizedDescription: errorDescription)
        }

        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let exportedDir = documentsURL.appendingPathComponent("ExportedCoreDataStores", isDirectory: true)
        let currentDateTime = Date()
        let currentTimeStamp = DateTimeUtil.getDateInTimeStamp(date: currentDateTime)
        func getFileName(extn fileExtension: String) -> String {
            let fileNamePrefix = storeURL.deletingPathExtension().lastPathComponent
            let fileName = DateTimeUtil.getTimeStampSuffixedFileName(
                fileName: fileNamePrefix,
                timestamp: currentTimeStamp,
                extn: "." + fileExtension
            )
            return fileName
        }
        let fileName = getFileName(extn: storeURL.pathExtension)
        let destinationURL = exportedDir.appendingPathComponent(fileName)
        let directoryURL = storeURL.deletingLastPathComponent()
        if let files = try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path) {
            debugLog("Files in Database Dir: \(directoryURL), \(files)")
        } else {
            debugLog("Failed to list directory contents.")
        }
        let parentDirectory = destinationURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentDirectory,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            try fileManager.copyItem(at: storeURL, to: destinationURL)
            debugLog("Core Data store exported to: \(destinationURL.path)")

            let additionalFiles = ["-shm", "-wal"].compactMap {
                storeURL.deletingPathExtension().appendingPathExtension(destinationURL.pathExtension + $0)
            }
            for file in additionalFiles where fileManager.fileExists(atPath: file.path) {
                let destination = destinationURL.deletingPathExtension() .appendingPathExtension(file.pathExtension)
                try fileManager.copyItem(at: file, to: destination)
                debugLog("Core Data store exported to: \(destination.path)")
            }
            return destinationURL
        } catch {
            let errorDescription = "Failed to copy Core Data files: \(error.localizedDescription)"
            throw getCoreDataError(code: 6, localizedDescription: errorDescription)
        }
    }
}
