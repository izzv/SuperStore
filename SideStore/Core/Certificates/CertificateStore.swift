//
//  CertificateStore.swift
//  SideStore
//
//  Created by Magesh K on 3/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//
import Foundation
import SideSign

public enum CertificateStore {
    public static func load(_ data: Data, password: String?) throws -> ALTCertificate {
        if let password = password {
            return try ALTCertificate(p12Data: data, password: password)
        } else {
            return try ALTCertificate(p12Data: data)
        }
    }

    public static func export(_ cert: ALTCertificate, password: String?) throws -> Data {
        if let password = password {
            return try cert.encryptedP12Data(password: password)
        } else {
            return try cert.unencryptedP12Data()
        }
    }
}
