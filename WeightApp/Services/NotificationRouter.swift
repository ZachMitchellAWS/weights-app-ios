//
//  NotificationRouter.swift
//  WeightApp
//
//  Carries a "where should we land" request from `AppDelegate` into the SwiftUI view
//  tree. `AppDelegate` receives notification taps but has no reference to the view
//  hierarchy, so it publishes a destination here and `ContentView` consumes it.
//
//  Same shape as `TutorialPresenter`, which exists for the same reason.
//

import SwiftUI
import Combine

final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()

    /// Equatable so `ContentView` can observe it with `onChange(of:)`.
    enum Destination: Equatable {
        case liftTab
    }

    /// Set by the notification tap handler, cleared by whoever acts on it.
    @Published var pendingDestination: Destination?

    private init() {}
}
