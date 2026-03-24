//
//  InsightsModels.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/10/26.
//

import Foundation

struct InsightSection: Codable, Equatable {
    let title: String
    let body: String
    let audioUrl: String?
}

struct StarterInsightResponse: Codable, Equatable {
    let body: String?
    let generatedAt: String?
    let audioUrl: String?
    let message: String?
}

struct WeeklyInsightsResponse: Codable, Equatable {
    let weekStartDate: String?
    let weekEndDate: String?
    let generatedAt: String?
    let sections: [InsightSection]?
    let message: String?
    let status: String?
    let error: String?
}
