//
//  URL+Normalized.swift
//  AltStore
//
//  Created by Riley Testut on 11/2/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//
import Foundation

public extension URL
{
    func normalized() throws -> String
    {

        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { throw URLError(.badURL, userInfo: [NSURLErrorKey: self, NSURLErrorFailingURLErrorKey: self]) }
        if components.scheme == nil && components.host == nil
        {
            guard let updatedComponents = URLComponents(string: "https://" + self.absoluteString) else { throw URLError(.cannotFindHost, userInfo: [NSURLErrorKey: self, NSURLErrorFailingURLErrorKey: self]) }
            components = updatedComponents
        }
        guard let host = components.host else { throw URLError(.cannotFindHost, userInfo: [NSURLErrorKey: self, NSURLErrorFailingURLErrorKey: self]) }
        var normalizedURL = host
        if let port = components.port, port != 80 && port != 443
        {
            normalizedURL += ":" + String(port)
        }
        let path = components.path.replacingOccurrences(of: "//", with: "/") 
        normalizedURL += path 
        normalizedURL = normalizedURL.lowercased()
        if normalizedURL.hasSuffix("/")
        {
            normalizedURL.removeLast()
        }
        if normalizedURL.hasPrefix("www.")
        {
            normalizedURL.removeFirst(4)
        }
        return normalizedURL
    }
}
