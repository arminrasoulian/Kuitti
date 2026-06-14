import Foundation
import Observation

/// Service construction lives here; injected once via .environment in KuittiApp.
@Observable
final class AppEnvironment {
    @ObservationIgnored let gemini = GeminiClient()
    @ObservationIgnored let off = OpenFoodFactsClient()
    let appLock = AppLockController()
    /// Proactive duplicate-product suggestions (badge/banner/Settings/post-scan nudge).
    let duplicates = DuplicateScanner()
}
