//
//  SetsWidgetStyle.swift
//  WeightApp
//
//  FEATURE FLAG: selectable style for the Lift-tab "SETS" widget so design
//  variants can be compared and reverted without touching the original code.
//  Persisted via @AppStorage("setsWidgetStyle"). `.original` restores the
//  shipping compact tile row exactly.
//

import Foundation

enum SetsWidgetStyle: String, CaseIterable, Identifiable {
    case original
    case tallTiles
    case verticalRows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .tallTiles: return "Tall Tiles"
        case .verticalRows: return "Vertical Rows"
        }
    }
}
