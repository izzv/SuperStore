//
//  ProcessInfo+SideStore.swift
//  SideStore
//
//  Created by ny on 10/23/24.
//  Copyright © 2024 SideStore. All rights reserved.
//
import Foundation

fileprivate struct BuildVersion: Comparable {
    let prefix: String
    let numericPart: Int
    let suffix: Character?
    init?(_ buildString: String) {
        var index = buildString.startIndex
        while index < buildString.endIndex, !buildString[index].isNumber {
            index = buildString.index(after: index)
        }
        guard index > buildString.startIndex else { return nil }
        self.prefix = String(buildString[buildString.startIndex..<index])
        let startOfNumeric = index
        while index < buildString.endIndex, buildString[index].isNumber {
            index = buildString.index(after: index)
        }
        guard let numericValue = Int(buildString[startOfNumeric..<index]) else { return nil }
        self.numericPart = numericValue
        if index < buildString.endIndex {
            self.suffix = buildString[index]
        } else {
            self.suffix = nil
        }
    }
    static func < (lhs: BuildVersion, rhs: BuildVersion) -> Bool {
        if lhs.prefix != rhs.prefix {
            return lhs.prefix < rhs.prefix
        }
        if lhs.numericPart != rhs.numericPart {
            return lhs.numericPart < rhs.numericPart
        }
        switch (lhs.suffix, rhs.suffix) {
        case let (l?, r?):
            return l < r
        case (nil, _?):
            return true 
        case (_?, nil):
            return false
        default:
            return false 
        }
    }
    static func == (lhs: BuildVersion, rhs: BuildVersion) -> Bool {
        return lhs.prefix == rhs.prefix &&
        lhs.numericPart == rhs.numericPart &&
        lhs.suffix == rhs.suffix
    }
}

extension ProcessInfo {
    public var shortVersion: String {
        operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "")
            .replacingOccurrences(of: "Build ", with: "")
    }
    public var operatingSystemBuild: String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        if size > 0 {
            var osversion = [CChar](repeating: 0, count: size)
            if sysctlbyname("kern.osversion", &osversion, &size, nil, 0) == 0 {
                return String(cString: osversion)
            }
        }
        if let start = shortVersion.range(of: "(")?.upperBound,
           let end = shortVersion.range(of: ")")?.lowerBound {
            return String(shortVersion[start..<end].replacingOccurrences(of: "Build ", with: ""))
        } else {
            return "???"
        }
    }
    public var sparseRestorePatched: Bool {
        if (OperatingSystemVersion(majorVersion: 18, minorVersion: 7, patchVersion: 2) <= operatingSystemVersion && operatingSystemVersion.majorVersion == 18) || operatingSystemVersion >= OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 2) { true }
        else if operatingSystemVersion < OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 2) { false }
        else if operatingSystemVersion < OperatingSystemVersion(majorVersion: 18, minorVersion: 7, patchVersion: 2) { false }
        else { true }
    }
}
