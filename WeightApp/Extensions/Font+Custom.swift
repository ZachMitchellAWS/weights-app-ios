//
//  Font+Custom.swift
//  WeightApp
//
//  Custom font definitions for Bebas Neue and Inter fonts.
//

import SwiftUI

extension Font {
    // MARK: - Bebas Neue (Display font - good for headers, numbers)

    static func bebasNeue(size: CGFloat) -> Font {
        .custom("BebasNeue-Regular", size: size)
    }

    // MARK: - Inter (Body font)

    static func inter(size: CGFloat) -> Font {
        .custom("Inter-Regular", size: size)
    }

    static func interSemiBold(size: CGFloat) -> Font {
        .custom("Inter-SemiBold", size: size)
    }
}
