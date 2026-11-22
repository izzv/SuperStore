//
//  AppBootManager.swift
//  SideStore
//
//  Created by Magesh K on 9/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//
import Foundation
import UIKit
import Minimuxer

public final class AppBootManager {
    public static let shared = AppBootManager()
    private let lock = NSLock()
    private let pairingOperationLock = NSLock()
    private var lastAppliedPairingFingerprint: String?
    private var isPairingOperationRunning = false
    private var cachedNeedsPairingPrompt = false
    public var needsPairingPrompt: Bool {
        get { lock.withLock { cachedNeedsPairingPrompt } }
        set { lock.withLock { cachedNeedsPairingPrompt = newValue } }
    }
    private var cachedNeedsSideJITPrompt = false
    public var needsSideJITPrompt: Bool {
        get { lock.withLock { cachedNeedsSideJITPrompt } }
        set { lock.withLock { cachedNeedsSideJITPrompt = newValue } }
    }
    private init() {}

    public nonisolated func startMinimuxer(pairingFile: String) async throws {
        debugLog("[AppBootManager] startMinimuxer() entered")
        defer { debugLog("[AppBootManager] startMinimuxer() exited") }
        if UserDefaults.standard.enableEMPforWireguard {
            debugLog("[AppBootManager] Starting EMProxy before minimuxer...")
            try await startEMProxy()
        }

        let preferred = PairingFileManager.shared.preferredProtocol
        try await minimuxerStart(pairingFile, preferred: preferred)
        self.appliedPairingFingerprint = Self.fingerprint(of: pairingFile)
        do {
            debugLog("[AppBootManager] startMinimuxer(): Minimuxer fetchUDID() based connection starting...")
            let deviceUDID = try await fetchUDID(forceLive: true)
            debugLog("[AppBootManager] startMinimuxer(): Minimuxer fetchUDID() based connection test SUCCEEDED. UDID: \(deviceUDID)")
            self.needsPairingPrompt = false
        } catch {
            if case MinimuxerError.invalidPairing = error {
                debugLog("[AppBootManager] startMinimuxer(): Minimuxer fetchUDID() based connection test FAILED. \(error)")
                self.needsPairingPrompt = true
                throw error
            } else {
                debugLog("[AppBootManager] startMinimuxer(): Minimuxer fetchUDID() based connection test FAILED but PAIRING FILE IS VALID. \(error)")
            }
        }
    }
    @MainActor
    public func promptForPairing(on vc: UIViewController) async {
        var isRetry = false
        while true {
            guard let selectedURL = await withCheckedContinuation({ (continuation: CheckedContinuation<URL?, Never>) in
                PairingViewController.shared.presentPairingFileAlert(on: vc, isRetry: isRetry) { selectedURL in
                    debugLog("[AppBootManager] promptForPairing: alert completed with selectedURL: \(selectedURL?.path ?? "nil")")
                    continuation.resume(returning: selectedURL)
                }
            }) else {
                debugLog("[AppBootManager] promptForPairing: user skipped or cancelled pairing prompt")
                break
            }
            debugLog("[AppBootManager] promptForPairing: fetching pairing file at selectedURL: \(selectedURL.path)")
            guard let pairingString = PairingFileManager.shared.fetchPairingFile() else {
                debugLog("[AppBootManager] promptForPairing: failed to read saved pairing file from disk")
                isRetry = true
                continue
            }
            do {
                try await self.startMinimuxer(pairingFile: pairingString)
                self.needsPairingPrompt = false
                break
            } catch {
                debugLog("[AppBootManager] startMinimuxer failed with pairing file: \(error)")
                let didSwitch = await PairingViewController.shared.handlePotentialProtocolMismatch(
                    on: vc,
                    pairingContent: pairingString
                )
                if didSwitch {
                    do {
                        try await self.startMinimuxer(pairingFile: pairingString)
                        self.needsPairingPrompt = false
                        break
                    } catch {
                        debugLog("[AppBootManager] startMinimuxer retry after protocol switch failed: \(error)")
                    }
                }
                isRetry = true
            }
        }
    }
    public nonisolated func performBootSequence() async {
        debugLog("[AppBootManager] performBootSequence() entered")
        defer { debugLog("[AppBootManager] performBootSequence() exited") }
        async let jitCheck: Void = {
            debugLog("[AppBootManager] performBootSequence(): JIT check starting")
            defer { debugLog("[AppBootManager] performBootSequence(): JIT check completed") }
            if #available(iOS 17, *), !UserDefaults.standard.isSideJITServerEnabled {
                do {
                    try await SideJITManager.shared.isSideJITServerDetected()
                    self.needsSideJITPrompt = true
                } catch {
                    debugLog("[AppBootManager] Cannot find sideJITServer")
                }
            }
            if #available(iOS 17, *), UserDefaults.standard.isSideJITServerEnabled {
                await SideJITManager.shared.askForNetwork()
                debugLog("[AppBootManager] SideJITServer Enabled")
            }
        }()
        async let minimuxerCheck: Void = {
            debugLog("[AppBootManager] performBootSequence(): Minimuxer check starting")
            let holdsPairingOperation = self.beginPairingOperation()
            defer {
                if holdsPairingOperation {
                    self.endPairingOperation()
                }
                debugLog("[AppBootManager] performBootSequence(): Minimuxer check completed")
            }
            PairingFileManager.shared.adoptPairingFileFromDisk()
            guard let pf = PairingFileManager.shared.fetchPairingFile() else {
                #if !targetEnvironment(simulator)
                self.needsPairingPrompt = true
                #endif
                return
            }

            do {
                try await self.startMinimuxer(pairingFile: pf)
            } catch {
                debugLog("[AppBootManager] Failed to start minimuxer: \(error)")
            }
        }()
        _ = await (jitCheck, minimuxerCheck)
    }
    public nonisolated func refreshPairingFromDisk() async {
        guard beginPairingOperation() else {
            debugLog("[AppBootManager] refreshPairingFromDisk(): a pairing update is already running, skipping this pass")
            return
        }
        defer { endPairingOperation() }

        let adopted = PairingFileManager.shared.adoptPairingFileFromDisk()
        guard let pairingFile = PairingFileManager.shared.fetchPairingFile() else {
            debugLog("[AppBootManager] refreshPairingFromDisk(): no pairing file in Documents, nothing to refresh")
            return
        }

        let fingerprint = Self.fingerprint(of: pairingFile)
        guard fingerprint != appliedPairingFingerprint else {
            debugLog("[AppBootManager] refreshPairingFromDisk(): pairing file unchanged since last check (adopted new file: \(adopted))")
            return
        }

        debugLog("[AppBootManager] refreshPairingFromDisk(): pairing file changed (adopted new file: \(adopted)), restarting minimuxer")
        do {
            try await startMinimuxer(pairingFile: pairingFile)
            debugLog("[AppBootManager] refreshPairingFromDisk(): minimuxer restarted with the new pairing file")
        } catch {
            debugLog("[AppBootManager] refreshPairingFromDisk(): minimuxer failed to start with the new pairing file: \(error)")
        }
    }
    private var appliedPairingFingerprint: String? {
        get { lock.withLock { lastAppliedPairingFingerprint } }
        set { lock.withLock { lastAppliedPairingFingerprint = newValue } }
    }

    private func beginPairingOperation() -> Bool {
        pairingOperationLock.lock()
        defer { pairingOperationLock.unlock() }
        guard !isPairingOperationRunning else { return false }
        isPairingOperationRunning = true
        return true
    }

    private func endPairingOperation() {
        pairingOperationLock.lock()
        isPairingOperationRunning = false
        pairingOperationLock.unlock()
    }

    private static func fingerprint(of contents: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in contents.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
