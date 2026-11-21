//
//  AnisetteManager.swift
//  SideStore
//
//  Created by Joseph Mattiello on 11/16/22.
//  Copyright © 2022 SideStore. All rights reserved.
//
import Foundation

public struct AnisetteManager {
    var menuURL: String {
        var url: String
        url = UserDefaults.standard.menuAnisetteURL
        return url
    }
    static var userURL: String? {
        var urlString: String?
        if UserDefaults.standard.textServer == false {
            urlString = UserDefaults.standard.textInputAnisetteURL
        }
        else {
            urlString = UserDefaults.standard.customAnisetteURL
        }
        if let urlString = urlString {
            guard URL(string: urlString) != nil else {
            ELOG("UserDefaults has invalid `customAnisetteURL`")
            assertionFailure("UserDefaults has invalid `customAnisetteURL`")
            return nil
            }
        }
        return urlString
    }
    static var defaultURL: String {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "ALTAnisetteURL") as? String else {
            assertionFailure("Info.plist has invalid `ALTAnisetteURL`")
            abort()
        }
        return url
    }
    static var currentURLString: String { userURL ?? defaultURL }
    static var currentURL: URL { URL(string: currentURLString)! }
}
