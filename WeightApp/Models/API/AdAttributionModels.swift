//
//  AdAttributionModels.swift
//  WeightApp
//
//  Wire type for POST /user/ad-attribution.
//
//  Field names match Apple's AdServices payload exactly, so the shape that arrives from
//  Apple is the shape that reaches our backend with no translation step to get wrong.
//

import Foundation

struct AdAttributionRequest: Encodable {
    /// Whether Apple says this install came from an ad. Always sent — a row that does not
    /// say which kind of install it was is not much use later.
    let attribution: Bool

    // All optional because Apple omits every campaign field for an organic install.
    // Swift's synthesised encoder uses `encodeIfPresent` for optionals, so nil fields are
    // left out of the JSON rather than sent as null — which is what the backend's
    // field-by-field validation expects.
    let orgId: Int?
    let campaignId: Int?
    let conversionType: String?
    let clickDate: String?
    let adGroupId: Int?
    let countryOrRegion: String?
    let keywordId: Int?
    let adId: Int?
}
