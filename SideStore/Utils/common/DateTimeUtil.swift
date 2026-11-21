//
//  DateTimeUtil.swift
//  SideStore
//
//  Created by Magesh K on 02/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
import Foundation

public class DateTimeUtil {
    public static func getDateInTimeStamp(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS" 
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
    public static func getTimeStampSuffixedFileName(fileName: String, timestamp: String, extn: String) -> String {
        let fnameWithTimestamp = "\(fileName)-\(timestamp)\(extn)"
        return fnameWithTimestamp
    }
}
