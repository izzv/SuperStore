//
//  AnisetteProvider.swift
//  SideStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//
import Foundation
import SideSign

enum AnisetteProvider {
    static func fetch(handler: AnisetteServerHandler? = nil) async throws -> ALTAnisetteData {
        if UserDefaults.standard.useOnDeviceAnisette {
            debugLog("[AnisetteProvider] Fetching anisette via On-Device Anisette (ODA)...")
            return try await OnDeviceAnisetteManager.shared.fetchAnisetteData()
        } else {
            debugLog("[AnisetteProvider] Fetching anisette via remote server...")
            return try await fetchRemote(handler: handler)
        }
    }

    private static let serverPasses = 2

    private static func fetchRemote(handler: AnisetteServerHandler? = nil) async throws -> ALTAnisetteData {
        let provider = SideSign.AnisetteDataManager.shared
        let existingBlob = AnisetteConfigManager.shared.anisetteAdiBlob.flatMap { Data(base64Encoded: $0) }
        let identifier = await AnisetteConfigManager.shared.resolveDeviceIdentifier()
        let headers = await AnisetteConfigManager.shared.makeRequestHeaders()
        let rotationDisabled = UserDefaults.standard.disableAnisetteRotation

        var attempted = 0
        var lastStatusCode: Int?
        var lastError: Error?

        for pass in 0..<serverPasses {
            if pass > 0 {
                debugLog("[AnisetteProvider] Every known server failed; refreshing the server list and retrying.")
                await handler?.anisetteStatus(NSLocalizedString("No Anisette server answered. Refreshing the server list and trying again…", comment: ""))
                await AnisetteServersManager.shared.syncOnFailureIfNeeded()
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }

            let serverUrlStrings = await AnisetteServersManager.shared.getActiveServerURLs()
            let servers = serverUrlStrings.compactMap { URL(string: $0) }
            guard !servers.isEmpty else {
                lastError = AnisetteError.noServersConfigured
                continue
            }

            let lastServer = UserDefaults.standard.menuAnisetteURL
            let startIndex = servers.firstIndex(where: { $0.absoluteString == lastServer }) ?? 0
            let order: [Int] = rotationDisabled
                ? [startIndex]
                : Array(0..<servers.count).map { (startIndex + $0) % servers.count }

            for index in order {
                let server = servers[index]
                attempted += 1
                debugLog("[AnisetteProvider] Attempting server [\(attempted)]: \(server.absoluteString)")

                if attempted > 1 {
                    let status = String(
                        format: NSLocalizedString("Anisette server did not answer. Trying another (%d)…", comment: ""),
                        attempted
                    )
                    await handler?.anisetteStatus(status)
                }

                do {
                    let (anisetteData, newBlob) = try await provider.fetchAnisetteData(
                        mode: .remote(server: server),
                        identifier: identifier,
                        existingAdiBlob: existingBlob,
                        headers: headers,
                        onError: { error in
                            if let anisetteError = error as? SideSign.AnisetteError,
                               case .outdatedV1Server(let serverURL, _) = anisetteError {
                                if UserDefaults.standard.defaultServerURL == serverURL.absoluteString {
                                    return true
                                }
                                if let handler = handler {
                                    let shouldContinue = try await handler.warnOutdatedAnisetteServer()
                                    if shouldContinue {
                                        UserDefaults.standard.defaultServerURL = serverURL.absoluteString
                                    }
                                    return shouldContinue
                                }
                            }
                            return false
                        }
                    )

                    if let freshBlob = newBlob {
                        AnisetteConfigManager.shared.anisetteAdiBlob = freshBlob.base64EncodedString()
                    }

                    UserDefaults.standard.menuAnisetteURL = server.absoluteString
                    debugLog("[AnisetteProvider] Successfully fetched Anisette data from \(server.absoluteString)")
                    return anisetteData
                } catch {
                    lastError = error
                    lastStatusCode = SignInFailure.classify(error)?.statusCode ?? lastStatusCode
                    debugLog("[AnisetteProvider] Server '\(server.absoluteString)' failed: \(SignInFailure.logSummary(for: error))")

                    guard SignInFailure.shouldRetryOnAnotherServer(error) else {
                        throw error
                    }
                }
            }
        }

        if await OnDeviceAnisetteManager.shared.isReady() {
            debugLog("[AnisetteProvider] Every remote server failed; falling back to On-Device Anisette.")
            await handler?.anisetteStatus(NSLocalizedString("Anisette servers are down. Falling back to On-Device Anisette…", comment: ""))
            do {
                let anisetteData = try await OnDeviceAnisetteManager.shared.fetchAnisetteData()
                debugLog("[AnisetteProvider] On-Device Anisette fallback succeeded")
                return anisetteData
            } catch {
                lastError = error
                debugLog("[AnisetteProvider] On-Device Anisette fallback failed: \(SignInFailure.logSummary(for: error))")
            }
        }

        debugLog("[AnisetteProvider] All \(attempted) server attempt(s) failed. Last status: \(lastStatusCode.map { String($0) } ?? "n/a")")

        if let lastError = lastError, !SignInFailure.shouldRetryOnAnotherServer(lastError) {
            throw lastError
        }

        throw OperationError.anisetteServerUnavailable(attempted: attempted, lastStatusCode: lastStatusCode)
    }
}
