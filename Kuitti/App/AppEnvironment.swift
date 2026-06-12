import Foundation
import Observation

/// Service construction lives here; injected once via .environment in KuittiApp.
@Observable
final class AppEnvironment {
    @ObservationIgnored let gemini = GeminiClient()
    @ObservationIgnored let off = OpenFoodFactsClient()
    let appLock = AppLockController()
}
