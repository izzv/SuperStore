//
//  OSLog+SideStore.swift
//  SideStore
//
//  Created by Joseph Mattiello on 11/16/22.
//  Copyright © 2022 SideStore. All rights reserved.
//
import Foundation
import OSLog

public let customLog = OSLog(subsystem: "org.sidestore.sidestore",
                      category: "ios")

public extension OSLog {
    @inlinable
    static func error(_ message: StaticString, _ args: CVarArg...) {
        os_log(message, log: customLog, type: .error, args)
    }
    @inlinable
    static func info(_ message: StaticString, _ args: CVarArg...) {
        os_log(message, log: customLog, type: .info, args)
    }
    @inlinable
    static func debug(_ message: StaticString, _ args: CVarArg...) {
        os_log(message, log: customLog, type: .debug, args)
    }
}

@inlinable
public func ELOG(_ message: StaticString, file: StaticString = #file, function: StaticString = #function, line: UInt = #line, _ args: CVarArg...) {
    OSLog.error(message, args)
}

@inlinable
public func ILOG(_ message: StaticString, file: StaticString = #file, function: StaticString = #function, line: UInt = #line, _ args: CVarArg...) {
    OSLog.info(message, args)
}

@inlinable
public func DLOG(_ message: StaticString, file: StaticString = #file, function: StaticString = #function, line: UInt = #line, _ args: CVarArg...) {
    OSLog.debug(message, args)
}
