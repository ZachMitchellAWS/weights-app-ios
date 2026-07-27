import SwiftUI
import Combine

// Lightweight coordinator so a child view (e.g. CheckInView on the Lift tab)
// can raise the tutorial-popup overlay that lives at the WeightAppApp root.
final class TutorialPresenter: ObservableObject {
    static let shared = TutorialPresenter()
    @Published var showLiftTutorial = false
    private init() {}
}
