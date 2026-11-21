//
//  CodeSignValidator.swift
//  SideStore
//
//  Created by Magesh K on 6/28/26.
//  Copyright © 2026 SideStore. All rights reserved.
//
import Foundation
import SideSign

public enum CodeSignValidationReason: Error {
    case expired
    case revoked
    case freeAccountLimitRevoked
    case differentTeam
    case differentAccount
    case privateKeyLost
    case externalSigner
    case missingProfile
    case missingCertificate
}

public struct CodeSignValidator {
    public static func validate(
        runningProfile: ALTProvisioningProfile?,
        portalCertificates: [ALTX509Certificate]?,
        signerCertificate: ALTX509Certificate,
        signerTeam: ALTTeam
    ) -> Result<Void, CodeSignValidationReason> {
        guard let runningProfile = runningProfile else {
            debugLog("[CodeSignValidator] Validation failed: missingProfile (runningProfile is nil)")
            return .failure(.missingProfile)
        }
        let runningCert = CertificateManager.shared.getSigningCertificate(at: Bundle.Info.activeBundleURL)
        guard let runningCert = runningCert else {
            debugLog("[CodeSignValidator] Validation failed: missingCertificate (failed to parse runningCert from binary)")
            return .failure(.missingCertificate)
        }
        if runningProfile.expirationDate <= Date() {
            debugLog("[CodeSignValidator] Validation failed: expired (running profile is expired: \(runningProfile.expirationDate))")
            return .failure(.expired)
        } else if runningCert.expiryDate <= Date() {
            debugLog("[CodeSignValidator] Validation failed: expired (running certificate is expired: \(runningCert.expiryDate))")
            return .failure(.expired)
        }
        let runningTeamID = runningProfile.teamIdentifier
        if runningTeamID != signerTeam.identifier {
            if let requesterEmail = runningCert.requesterEmail, !requesterEmail.isEmpty,
                let activeAppleID = signerTeam.account?.appleID,
                requesterEmail.lowercased() != activeAppleID.lowercased() 
            {
                debugLog("[CodeSignValidator] Validation failed: differentAccount (running profile email '\(requesterEmail)' != active account Apple ID '\(activeAppleID)')")
                return .failure(.differentAccount)
            } else {
                debugLog("[CodeSignValidator] Validation failed: differentTeam (running profile team '\(runningTeamID)' != active team '\(signerTeam.identifier)')")
                return .failure(.differentTeam)
            }
        }
        if let portalCertificates = portalCertificates {
            let isRunningCertActive = portalCertificates.contains { $0.serialNumber == runningCert.serialNumber }
            if !isRunningCertActive {
                if signerTeam.type == .free {
                    debugLog("[CodeSignValidator] Validation failed: freeAccountLimitRevoked (certificate is no longer active on portal for free account)")
                    return .failure(.freeAccountLimitRevoked)
                } else {
                    debugLog("[CodeSignValidator] Validation failed: revoked (certificate is no longer active on portal)")
                    return .failure(.revoked)
                }
            }
        }
        let hasCurrentSignerCert = runningProfile.certificates.contains { $0.serialNumber == signerCertificate.serialNumber }
        if !hasCurrentSignerCert {
            if let machineName = runningCert.machineName, (machineName.starts(with: "SuperStore") || machineName.starts(with: "AltStore")) {
                debugLog("[CodeSignValidator] Validation failed: privateKeyLost (running profile cert mismatch, cert created by SuperStore/AltStore: \(machineName))")
                return .failure(.privateKeyLost)
            } else {
                debugLog("[CodeSignValidator] Validation failed: externalSigner (running profile cert mismatch, cert not created by SuperStore/AltStore: \(runningCert.machineName ?? "N/A"))")
                return .failure(.externalSigner)
            }
        }
        debugLog("[CodeSignValidator] Validation succeeded!")
        return .success(())
    }
}
