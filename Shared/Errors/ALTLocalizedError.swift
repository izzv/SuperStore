//
//  ALTLocalizedError.swift
//  AltStore
//
//  Created by Riley Testut on 10/14/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//
import Foundation

public let ALTLocalizedTitleErrorKey = "ALTLocalizedTitle"
public let ALTLocalizedDescriptionKey = "ALTLocalizedDescription"
public let ALTSourceFileErrorKey = "ALTSourceFile"
public let ALTSourceLineErrorKey = "ALTSourceLine"

public protocol ALTLocalizedError<Code>: LocalizedError, CustomNSError, CustomStringConvertible
{
    associatedtype Code: ALTErrorCode

    var code: Code { get }
    var errorFailureReason: String { get }

    var errorTitle: String? { get set }
    var errorFailure: String? { get set }

    var sourceFile: String? { get set }
    var sourceLine: UInt? { get set }
}

public extension ALTLocalizedError
{
    var sourceFile: String? {
        get { nil }
        set {}
    }
    var sourceLine: UInt? {
        get { nil }
        set {}
    }
}

public protocol ALTErrorCode: Sendable, RawRepresentable where RawValue == Int
{
    associatedtype Error: ALTLocalizedError where Error.Code == Self
    static var errorDomain: String { get } 
}

public protocol ALTErrorEnum: ALTErrorCode
{
    associatedtype Error = DefaultLocalizedError<Self>
    var errorFailureReason: String { get }
}

public extension ALTLocalizedError
{
    var errorCode: Int { self.code.rawValue }
    var errorDescription: String? {
        return self.errorFailure ?? self.failureReason
    }

    var failureReason: String? {
        return self.errorFailureReason
    }

    var errorUserInfo: [String : Any] {
        var userInfo: [String: Any?] = [
            NSLocalizedDescriptionKey       : self.errorDescription,
            NSLocalizedFailureReasonErrorKey: self.failureReason,
            NSLocalizedFailureErrorKey      : self.errorFailure,
            ALTLocalizedTitleErrorKey       : self.errorTitle,
            ALTSourceFileErrorKey as String : self.sourceFile,
            ALTSourceLineErrorKey as String : self.sourceLine,
        ]

        for (key, value) in self.userInfoValues
        {
            userInfo[key] = value
        }

        return userInfo.compactMapValues { $0 }
    }

    var description: String {
        let description = "\(self.errorCode) “\(self.localizedDescription)”"
        return description
    }
}

public extension ALTLocalizedError where Code: ALTErrorEnum
{
    static var errorDomain: String {
        return Code.errorDomain
    }
    var errorFailureReason: String {
        return self.code.errorFailureReason
    }
}

public extension ALTErrorCode
{
    static var errorDomain: String {
        let typeName = String(reflecting: Self.self) 
        let errorDomain = typeName.replacingOccurrences(of: "ErrorCode", with: "Error")
        return errorDomain
    }
}

public extension ALTLocalizedError
{
    init(_ error: Self, localizedTitle: String? = nil, localizedFailure: String? = nil)
    {
        self = error
        if let localizedTitle
        {
            self.errorTitle = localizedTitle
        }
        if let localizedFailure
        {
            self.errorFailure = localizedFailure
        }
    }
}

private extension ALTLocalizedError
{
    var userInfoValues: [(String, Any)] {
        let userInfoValues = Mirror(reflecting: self).children.compactMap { (label, value) -> (String, Any)? in
            guard let userInfoValue = value as? any UserInfoValueProtocol,
                  let key: any StringProtocol = userInfoValue.key ?? label?.dropFirst() 
            else { return nil }

            return (String(key), userInfoValue.wrappedValue)
        }
        return userInfoValues
    }
}

public struct DefaultLocalizedError<Code: ALTErrorEnum>: ALTLocalizedError
{
    public let code: Code

    public var errorTitle: String?
    public var errorFailure: String?
    public var sourceFile: String?
    public var sourceLine: UInt?

    public init(_ code: Code, localizedTitle: String? = nil, localizedFailure: String? = nil, sourceFile: String? = #fileID, sourceLine: UInt? = #line)
    {
        self.code = code
        self.errorTitle = localizedTitle
        self.errorFailure = localizedFailure
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
    }
}

prefix operator ~
public prefix func ~<Code: ALTErrorCode>(expression: Code) -> NSError
{
    let nsError = NSError(domain: Code.errorDomain, code: expression.rawValue)
    return nsError
}

public func ~=(pattern: any Swift.Error, value: any Swift.Error) -> Bool
{
    let isMatch = pattern._domain == value._domain && pattern._code == value._code
    return isMatch
}
