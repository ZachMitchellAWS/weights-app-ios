import SwiftUI
import Combine

// Lightweight coordinator so a child view (e.g. CheckInView on the Lift tab)
// can raise the tutorial-popup overlay that lives at the WeightAppApp root.
final class TutorialPresenter: ObservableObject {
    static let shared = TutorialPresenter()
    @Published var showLiftTutorial = false
    /// Raised right after the lift-tutorial popup is dismissed (watched or
    /// skipped) to point the user at More → Resources, where the tour lives.
    @Published var showResourcesHint = false
    /// Session-scoped (resets each launch, since this is a singleton): whether the
    /// "Ready to lift?" next-focus popup has already been auto-shown this launch.
    var readyToLiftShownThisLaunch = false
    private init() {}
}
