//
//  SyncLogger.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/20/26.
//

import OSLog

enum SyncLogger {
    static let sync = Logger(subsystem: "com.weightapp", category: "sync")
    static let api = Logger(subsystem: "com.weightapp", category: "api")
    static let retry = Logger(subsystem: "com.weightapp", category: "retry")
}
