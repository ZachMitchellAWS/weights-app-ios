//
//  LogExporter.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/20/26.
//

import OSLog

enum LogExporter {
    static func exportRecentLogs() throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let cutoff = store.position(date: Date().addingTimeInterval(-3600))
        let entries = try store.getEntries(at: cutoff, matching: NSPredicate(format: "subsystem == %@", "com.weightapp"))

        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"

        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog else { continue }
            let timestamp = formatter.string(from: logEntry.date)
            let level: String
            switch logEntry.level {
            case .debug: level = "DEBUG"
            case .info: level = "INFO"
            case .error: level = "ERROR"
            case .fault: level = "FAULT"
            default: level = "NOTE"
            }
            lines.append("[\(timestamp)] [\(level)] [\(logEntry.category)] \(logEntry.composedMessage)")
        }

        if lines.isEmpty {
            return "No com.weightapp logs found in the last 60 minutes."
        }

        return lines.joined(separator: "\n")
    }
}
