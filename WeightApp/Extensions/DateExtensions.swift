//
//  DateExtensions.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/27/26.
//

import Foundation

extension Date {
    /// Formats the date as ISO 8601 UTC datetime string: 2026-01-27T18:45:32.123
    /// - Returns: UTC datetime string without timezone suffix
    func toUTCDateTimeString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        let isoString = formatter.string(from: self)

        // Remove the Z suffix to get format: 2026-01-27T18:45:32.123
        if isoString.hasSuffix("Z") {
            return String(isoString.dropLast())
        }
        return isoString
    }

    /// Converts UTC datetime string to Date object
    /// - Parameter utcString: UTC datetime string in format 2026-01-27T18:45:32.123
    /// - Returns: Date object or nil if parsing fails
    static func fromUTCDateTimeString(_ utcString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")

        // Add Z suffix if not present for parsing
        let stringToParse = utcString.hasSuffix("Z") ? utcString : utcString + "Z"
        return formatter.date(from: stringToParse)
    }

    /// Formats the date in the original timezone it was created
    /// - Parameters:
    ///   - timezoneIdentifier: Timezone identifier (e.g., "America/New_York")
    ///   - style: DateFormatter style for date and time
    /// - Returns: Formatted date string in the specified timezone
    func toLocalizedString(timezone timezoneIdentifier: String, dateStyle: DateFormatter.Style = .short, timeStyle: DateFormatter.Style = .short) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        formatter.timeZone = TimeZone(identifier: timezoneIdentifier)
        return formatter.string(from: self)
    }
}
