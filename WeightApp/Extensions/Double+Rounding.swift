//
//  Double+Rounding.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import Foundation

extension Double {
    func roundedUp(toIncrement inc: Double) -> Double {
        guard inc > 0 else { return self }
        let n = (self / inc).rounded(.up)
        // Avoid -0.0 style results
        let v = n * inc
        return abs(v) < 0.0000001 ? 0 : v
    }

    func rounded1() -> Double {
        (self * 100).rounded() / 100
    }
}
