//
//  UserInfoValue.swift
//  AltStore
//
//  Created by Riley Testut on 5/2/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//
import Foundation

protocol UserInfoValueProtocol<Value>
{
    associatedtype Value
    var key: String? { get }
    var wrappedValue: Value { get }
}

@propertyWrapper
public struct UserInfoValue<Value>: UserInfoValueProtocol
{
    public let key: String?
    public var wrappedValue: Value
    public init(wrappedValue: Value)
    {
        self.wrappedValue = wrappedValue
        self.key = nil
    }
    public init(wrappedValue: Value, key: String)
    {
        self.wrappedValue = wrappedValue
        self.key = key
    }
}
