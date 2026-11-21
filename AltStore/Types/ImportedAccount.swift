//
//  ImportedAccount.swift
//  AltStore
//
//  Created by ny on 9/7/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
import Foundation

public enum CertificateEncryptionType: String, Codable {
    case encrypted
    case unencrypted
}

struct ImportedAccount: Codable {
    public static let currentVersion = "2.0"

    let version: String
    let email: String
    let password: String?
    let certificateData: Data
    let certificatePassword: String?
    let anisetteIdentifier: String
    let anisetteAdiBlob: String

    var certificateType: CertificateEncryptionType {
        certificatePassword != nil ? .encrypted : .unencrypted
    }

    enum CodingKeys: String, CodingKey {
        case version
        case email
        case password
        case certificateData
        case certificateType = "certType"
        case certificatePassword
        case anisetteIdentifier
        case anisetteAdiBlob

        case legacyCert = "cert"
        case legacyCertPass = "certpass"
        case legacyLocalUser = "local_user"
        case legacyAdiPB = "adiPB"
    }

    init(
        version: String = ImportedAccount.currentVersion,
        email: String,
        password: String?,
        certificateData: Data,
        certificatePassword: String,
        anisetteIdentifier: String,
        anisetteAdiBlob: String
    ) {
        self.version = version
        self.email = email
        self.password = password
        self.certificateData = certificateData
        self.certificatePassword = certificatePassword
        self.anisetteIdentifier = anisetteIdentifier
        self.anisetteAdiBlob = anisetteAdiBlob
    }

    init(
        version: String = ImportedAccount.currentVersion,
        email: String,
        password: String?,
        certificateData: Data,
        anisetteIdentifier: String,
        anisetteAdiBlob: String
    ) {
        self.version = version
        self.email = email
        self.password = password
        self.certificateData = certificateData
        self.certificatePassword = nil
        self.anisetteIdentifier = anisetteIdentifier
        self.anisetteAdiBlob = anisetteAdiBlob
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = (try container.decodeIfPresent(String.self, forKey: .version)) ?? "1.0"
        self.email = try container.decode(String.self, forKey: .email)
        self.password = try container.decodeIfPresent(String.self, forKey: .password)

        if let certData = try container.decodeIfPresent(Data.self, forKey: .certificateData) {
            self.certificateData = certData
        } else {
            self.certificateData = try container.decode(Data.self, forKey: .legacyCert)
        }

        if let explicitType = try container.decodeIfPresent(CertificateEncryptionType.self, forKey: .certificateType) {
            switch explicitType {
            case .encrypted:
                self.certificatePassword = try container.decode(String.self, forKey: .certificatePassword)
            case .unencrypted:
                self.certificatePassword = nil
            }
        } else {
            let legacyPass = try container.decode(String.self, forKey: .legacyCertPass)
            if !legacyPass.isEmpty {
                self.certificatePassword = legacyPass
            } else {
                self.certificatePassword = nil
            }
        }

        if let identifier = try container.decodeIfPresent(String.self, forKey: .anisetteIdentifier) {
            self.anisetteIdentifier = identifier
        } else {
            self.anisetteIdentifier = try container.decode(String.self, forKey: .legacyLocalUser)
        }

        if let adiBlob = try container.decodeIfPresent(String.self, forKey: .anisetteAdiBlob) {
            self.anisetteAdiBlob = adiBlob
        } else {
            self.anisetteAdiBlob = try container.decode(String.self, forKey: .legacyAdiPB)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(email, forKey: .email)
        try container.encodeIfPresent(password, forKey: .password)
        try container.encode(certificateData, forKey: .certificateData)
        try container.encode(certificateType, forKey: .certificateType)
        try container.encodeIfPresent(certificatePassword, forKey: .certificatePassword)
        try container.encode(anisetteIdentifier, forKey: .anisetteIdentifier)
        try container.encode(anisetteAdiBlob, forKey: .anisetteAdiBlob)
    }
}
