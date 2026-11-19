//
//  Date+ServerParsing.swift
//  WeightApp
//
//  One parser for the timestamps the backend sends, because there were three and they disagreed.
//
//  WHAT THE BACKEND ACTUALLY SENDS. `datetime.utcnow().isoformat()`, which produces
//  "2026-03-02T20:18:27.814" — UTC, microsecond-or-millisecond fraction, and critically NO
//  timezone designator. No "Z", no "+00:00". Verified against stored `createdDatetime` values in
//  `WeightApp-backend/snapshots/`.
//
//  WHY THAT BREAKS THE OBVIOUS APPROACHES. `ISO8601DateFormatter` is strict: every option set
//  that includes `.withInternetDateTime` or `.withFullTime` expects a timezone in the string and
//  returns nil without one, and `.withFullDate` alone refuses a string with a time appended. So
//  for this format EVERY `ISO8601DateFormatter` configuration fails, and anything relying on one
//  silently falls through to whatever comes next.
//
//  WHY THE FALLBACK HAD TO PIN UTC. The three parsers this replaces:
//
//    * `MoreView.memberSinceDate` — five ISO8601 option sets (all of which fail, per above) then
//      three `DateFormatter` patterns with NO `timeZone` set, so the UTC timestamp was read as
//      device-local. For a "Member since March 2" line that is at most a day wrong and nobody
//      noticed. For the 72-hour offer window it is up to 14 hours of skew, which is 19% of the
//      window, so it had to be fixed before `IntroOfferService` could depend on it.
//    * `EntitlementsService.parseISO8601` — correctly pins UTC but hardcodes a single
//      ".SSS" pattern, so a six-digit fraction or a trailing "Z" returns nil.
//    * `WeightApp-backend` emits both 3- and 6-digit fractions depending on the call path.
//
//  So: try ISO8601 first (for any endpoint that does send an offset, and for future-proofing if
//  the backend ever starts appending "Z"), then fall back to explicit patterns with `timeZone`
//  pinned to GMT and a POSIX locale.
//

import Foundation

extension Date {
    /// Parses a timestamp as sent by the backend, or nil if it is in no recognised shape.
    ///
    /// Tolerant by design — this is parsing a contract that has drifted (3- vs 6-digit fractional
    /// seconds, with and without a timezone designator), and a stricter parser would return nil
    /// on real data. Callers should still handle nil: a date that fails every pattern here is a
    /// genuine contract break worth noticing rather than papering over.
    static func fromServerString(_ string: String) -> Date? {
        // Handles anything carrying an actual offset or "Z". Fails for the backend's current
        // bare-UTC format, which is what the fallback below is for.
        for options in isoOptions {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: string) { return date }
        }

        // `timeZone` is the load-bearing line. Without it these patterns read a UTC timestamp in
        // the device's zone, which is how the member-since date has been wrong for everyone east
        // or west of London.
        for format in fallbackFormats {
            let parser = DateFormatter()
            parser.dateFormat = format
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = TimeZone(identifier: "UTC")
            if let date = parser.date(from: string) { return date }
        }

        return nil
    }

    private static let isoOptions: [ISO8601DateFormatter.Options] = [
        [.withInternetDateTime, .withFractionalSeconds],
        [.withInternetDateTime],
        [.withFullDate, .withFullTime, .withFractionalSeconds],
        [.withFullDate, .withFullTime],
    ]

    /// Ordered most-specific first. The six-digit variant has to precede the three-digit one:
    /// `DateFormatter` will happily match ".SSS" against ".814623" and silently truncate.
    private static let fallbackFormats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd",
    ]
}
