//
//  MaintenanceManager.swift
//  SideStore
//
//  Created by Magesh K on 22/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//
import Foundation
import CoreData
import SideSign

public final class MaintenanceManager {
    public static let shared = MaintenanceManager()

    public static let currentMaintenanceCounter = 10

    public static let maintenanceCounterFileName = ".maintenance_counter"

    private var maintenanceCounterFileURL: URL? {
        FileManager.default.altstoreSharedDirectory?.appendingPathComponent(Self.maintenanceCounterFileName)
    }

    private var completedCounter: Int {
        get {
            guard let url = maintenanceCounterFileURL,
                  let str = try? String(contentsOf: url, encoding: .utf8),
                  let val = Int(str.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
            return val
        }
        set {
            guard let url = maintenanceCounterFileURL else { return }
            try? "\(newValue)".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private init() {}

    public func performDatabaseMigrationIfNeeded() async {
        let current = completedCounter
        guard current < Self.currentMaintenanceCounter else { return }

        for pass in (current + 1)...Self.currentMaintenanceCounter {
            switch pass {
            case 4:
                await migrateDatabaseFiles()
            case 8:
                await importSideStoreDatabaseIfNeeded()
            default:
                break
            }
        }
    }

    public func performMaintenanceIfNeeded() async {
        let current = completedCounter
        guard current < Self.currentMaintenanceCounter else { return }

        for pass in (current + 1)...Self.currentMaintenanceCounter {
            debugLog("[MaintenanceManager] Running maintenance pass \(pass)...")
            switch pass {
            case 1:
                Keychain.shared.clearAll()
                await AuthManager.shared.signOut(keepCertificate: false, keepAnisetteData: false)
            case 2:
                AnisetteDataManager.shared.clearCache()
                await AuthManager.shared.signOut(keepCertificate: true, keepAnisetteData: false)
            case 3:
                UserDefaults.standard.tunnelOverridePeerIp = nil
            case 4:
                await migrateLegacyCachedAppBundles()
            case 5:
                await migrateLegacyCachedSigningCertificates()
            case 6:
                AnisetteConfigManager.shared.resetToDefaults()
                SideSignConfigManager.shared.resetToDefaults()
            case 7:
                await migratePairingFiles()
            case 9:
                await removeSideStoreSources()
            case 10:
                await repairAnisetteServers()
            default:
                break
            }
        }

        completedCounter = Self.currentMaintenanceCounter
        debugLog("[MaintenanceManager] Maintenance up to counter \(Self.currentMaintenanceCounter) complete.")
    }

}

private extension MaintenanceManager {
    func migrateDatabaseFiles() async {
        let fileManager = FileManager.default
        let dbDir = PersistentContainer.defaultDirectoryURL()

        let extensions = ["", "-wal", "-shm"]
        let legacyName = AppConstants.Database.legacyFileName
        let targetName = AppConstants.Database.fileName

        let legacyTargetURL = dbDir.appendingPathComponent(legacyName)
        let newTargetURL = dbDir.appendingPathComponent(targetName)

        if fileManager.fileExists(atPath: legacyTargetURL.path) && !fileManager.fileExists(atPath: newTargetURL.path) {
            for ext in extensions {
                let src = dbDir.appendingPathComponent("\(legacyName)\(ext)")
                let dst = dbDir.appendingPathComponent("\(targetName)\(ext)")
                if fileManager.fileExists(atPath: src.path) {
                    do {
                        try fileManager.moveItem(at: src, to: dst)
                        debugLog("[MaintenanceManager] Migrated database file '\(src.lastPathComponent)' -> '\(dst.lastPathComponent)'")
                    } catch {
                        debugLog("[MaintenanceManager] Failed to move database file '\(src.lastPathComponent)': \(error)")
                    }
                }
            }
        }
    }

    func importSideStoreDatabaseIfNeeded() async {
        let fileManager = FileManager.default
        let databaseDirectory = PersistentContainer.defaultDirectoryURL()
        let documentsDirectory = fileManager.documentsDirectory

        let markerURL = databaseDirectory.appendingPathComponent(".importedFromSideStore")
        guard !fileManager.fileExists(atPath: markerURL.path) else { return }

        let targetURL = databaseDirectory.appendingPathComponent(AppConstants.Database.fileName)
        guard !fileManager.fileExists(atPath: targetURL.path) else { return }

        let sourceURL = documentsDirectory.appendingPathComponent(AppConstants.Database.sideStoreFileName)
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }

        let stagingDirectory = databaseDirectory.appendingPathComponent(".import-from-sidestore")
        try? fileManager.removeItem(at: stagingDirectory)

        do {
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true, attributes: nil)

            var staged: [(suffix: String, url: URL)] = []
            for suffix in ["", "-wal", "-shm"] {
                let source = documentsDirectory.appendingPathComponent(AppConstants.Database.sideStoreFileName + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }

                let stagedURL = stagingDirectory.appendingPathComponent(AppConstants.Database.fileName + suffix)
                try fileManager.copyItem(at: source, to: stagedURL)

                let expectedSize = try fileManager.attributesOfItem(atPath: source.path)[.size] as? Int64 ?? 0
                let copiedSize = try fileManager.attributesOfItem(atPath: stagedURL.path)[.size] as? Int64 ?? 0
                guard expectedSize == copiedSize else {
                    throw NSError(domain: "SuperStore.DatabaseImport", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Incomplete copy of \(source.lastPathComponent)"
                    ])
                }
                staged.append((suffix, stagedURL))
            }

            staged.sort { $0.suffix.count > $1.suffix.count }
            for entry in staged {
                let destination = databaseDirectory.appendingPathComponent(AppConstants.Database.fileName + entry.suffix)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: entry.url, to: destination)
                debugLog("[MaintenanceManager] Moved '\(destination.lastPathComponent)' into place from SideStore import.")
            }

            for suffix in ["", "-wal", "-shm"] {
                let source = documentsDirectory.appendingPathComponent(AppConstants.Database.sideStoreFileName + suffix)
                try? fileManager.removeItem(at: source)
            }
            try? fileManager.removeItem(at: stagingDirectory)

            try? Data().write(to: markerURL)
            debugLog("[MaintenanceManager] SideStore database import finished.")
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            debugLog("[MaintenanceManager] Failed to import SideStore database: \(error)")
        }
    }

    func removeSideStoreSources() async {
        let context = DatabaseManager.shared.viewContext
        await context.perform {
            let fetchRequest: NSFetchRequest<Source> = Source.fetchRequest()
            let sources = (try? context.fetch(fetchRequest)) ?? []

            let brandedSources = sources.filter { source in
                guard let host = source.sourceURL.host?.lowercased() else { return false }
                return host == "sidestore.io" || host.hasSuffix(".sidestore.io")
            }
            guard !brandedSources.isEmpty else { return }

            var hidden = UserDefaults.standard.hiddenSourceIdentifiers ?? []
            var removed = 0
            for source in brandedSources {
                for newsItem in source.newsItems {
                    context.delete(newsItem)
                }

                let hasInstalledApps = source.apps.contains { $0.installedApp != nil }
                if hasInstalledApps {
                    if !hidden.contains(source.identifier) {
                        hidden.append(source.identifier)
                    }
                } else {
                    context.delete(source)
                    removed += 1
                    hidden.removeAll { $0 == source.identifier }
                }
            }
            UserDefaults.standard.hiddenSourceIdentifiers = hidden

            do {
                try context.save()
                debugLog("[MaintenanceManager] Cleared the news of \(brandedSources.count) SideStore source(s), removed \(removed) and hid \(brandedSources.count - removed).")
            } catch {
                debugLog("[MaintenanceManager] Failed to clear the SideStore sources: \(error)")
            }
        }
    }

    func migrateLegacyCachedAppBundles() async {
        let context = DatabaseManager.shared.viewContext
        await context.perform {
            let fetchRequest: NSFetchRequest<InstalledApp> = InstalledApp.fetchRequest()
            let installedApps = (try? context.fetch(fetchRequest)) ?? []
            let appsByBundleID = Dictionary(installedApps.map { ($0.resignedBundleIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

            var didMutate = false
            let appsDir = InstalledApp.appsDirectoryURL
            guard let subdirectories = try? FileManager.default.contentsOfDirectory(
                at: appsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return
            }

            for directory in subdirectories {
                guard directory.lastPathComponent != "Payloads" else { continue }
                let legacyAppURL = directory.appendingPathComponent("App.app")
                guard FileManager.default.fileExists(atPath: legacyAppURL.path) else { continue }

                guard let signature = AppBundleFingerprint.compute(for: legacyAppURL) else {
                    debugLog("[MaintenanceManager] Failed to compute fingerprint for legacy app at '\(legacyAppURL.path)'")
                    continue
                }

                let targetFileURL = InstalledApp.payloadURL(forSignature: signature)
                let targetParentDir = targetFileURL.deletingLastPathComponent()

                do {
                    if !FileManager.default.fileExists(atPath: targetFileURL.path) {
                        try FileManager.default.createDirectory(at: targetParentDir, withIntermediateDirectories: true, attributes: nil)
                        try FileManager.default.moveItem(at: legacyAppURL, to: targetFileURL)
                    } else {
                        try FileManager.default.removeItem(at: legacyAppURL)
                    }

                    let bundleID = directory.lastPathComponent
                    if let app = appsByBundleID[bundleID] {
                        app.appBundleFingerprint = signature
                        didMutate = true
                    }
                    debugLog("[MaintenanceManager] Migrated legacy app bundle '\(bundleID)' to payload '\(signature)'.")
                } catch {
                    debugLog("[MaintenanceManager] Failed to move legacy app bundle at '\(legacyAppURL.path)': \(error)")
                }
            }

            if didMutate {
                try? context.save()
            }
        }
    }

    func migrateLegacyCachedSigningCertificates() async {
        let context = DatabaseManager.shared.viewContext
        await context.perform {
            let fetchRequest: NSFetchRequest<InstalledApp> = InstalledApp.fetchRequest()
            guard let installedApps = try? context.fetch(fetchRequest) else { return }
            let fileManager = FileManager.default
            let appsDir = InstalledApp.appsDirectoryURL

            for app in installedApps {
                guard app.bundleIdentifier != app.resignedBundleIdentifier else { continue }

                let legacyCertURL = appsDir.appendingPathComponent(app.bundleIdentifier).appendingPathComponent("signing_certificate.der")
                let targetCertURL = app.signingCertificateURL

                guard fileManager.fileExists(atPath: legacyCertURL.path) else { continue }

                do {
                    if !fileManager.fileExists(atPath: targetCertURL.path) {
                        let targetDir = targetCertURL.deletingLastPathComponent()
                        try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)
                        try fileManager.moveItem(at: legacyCertURL, to: targetCertURL)
                    } else {
                        try fileManager.removeItem(at: legacyCertURL)
                    }
                    debugLog("[MaintenanceManager] Migrated signing cert for '\(app.bundleIdentifier)' -> '\(app.resignedBundleIdentifier)'")
                } catch {
                    debugLog("[MaintenanceManager] Failed to migrate signing cert from '\(legacyCertURL.path)': \(error)")
                }
            }
        }
    }

    static let retiredAnisetteServers = [
        "https://ani.sidestore.io",
        "https://ani.sidestore.app",
        "https://win.ani.sidestore.io",
        "http://5.249.163.88:6969",
    ]

    func repairAnisetteServers() async {
        let retired = Set(Self.retiredAnisetteServers)
        if UserDefaults.standard.menuAnisetteList == "https://servers.sidestore.io/servers.json"
        {
            UserDefaults.standard.menuAnisetteList = AppConstants.Anisette.Servers.defaultSource
        }

        let stored = await AnisetteServersManager.shared.loadLocalServers()
        let alive = stored.filter { !retired.contains($0.address) }
        if alive.count != stored.count
        {
            await AnisetteServersManager.shared.saveLocalServers(alive)
            debugLog("[MaintenanceManager] Dropped \(stored.count - alive.count) Anisette server(s) that no longer answer.")
        }

        let current = UserDefaults.standard.menuAnisetteURL
        if retired.contains(current) || !alive.contains(where: { $0.address == current })
        {
            let replacement = alive.first(where: { !$0.isHidden })?.address ?? AppConstants.Anisette.Servers.defaultServerURL
            UserDefaults.standard.menuAnisetteURL = replacement
            debugLog("[MaintenanceManager] Pointed the Anisette server at '\(replacement)'.")
        }

        AnisetteDataManager.shared.clearCache()
        AnisetteConfigManager.shared.anisetteAdiBlob = nil
        debugLog("[MaintenanceManager] Cleared cached Anisette data and the stored ADI provisioning session.")
    }

    func migratePairingFiles() async {
        let fileManager = FileManager.default
        let lockdownURL = fileManager.documentsDirectory.appendingPathComponent(AppConstants.Pairing.lockdownPairingFileName)
        let remoteURL = fileManager.documentsDirectory.appendingPathComponent(AppConstants.Pairing.remotePairingFileName)

        let legacyURL = fileManager.documentsDirectory.appendingPathComponent(AppConstants.Pairing.legacyPairingFileName)
        guard fileManager.fileExists(atPath: legacyURL.path),
              let content = try? String(contentsOf: legacyURL), !content.isEmpty else 
        { 
            return 
        }

        let remoteRP = try? PairingFileManager.shared.parse(content: content, preferred: .rppairing)
        let lockdown = try? PairingFileManager.shared.parse(content: content, preferred: .lockdown)
        if remoteRP != nil && !fileManager.fileExists(atPath: remoteURL.path) {
            try? content.write(to: remoteURL, atomically: true, encoding: .utf8)
            debugLog("[MaintenanceManager] Migrated remote pairing file to '\(remoteURL.path)'.")
        }
        if lockdown != nil && !fileManager.fileExists(atPath: lockdownURL.path) {
            try? content.write(to: lockdownURL, atomically: true, encoding: .utf8)
            debugLog("[MaintenanceManager] Migrated lockdown pairing file to '\(lockdownURL.path)'.")
        }

        try? fileManager.removeItem(at: legacyURL)
        debugLog("[MaintenanceManager] Removed legacy pairing file '\(legacyURL.path)'.")
    }
}
