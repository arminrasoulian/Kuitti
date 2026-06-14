import Foundation
import Testing
@testable import Kuitti

/// AISettings' UserDefaults-backed provider/model, focused on the fallback-default contract:
/// an unset or empty model id must resolve to the provider default so pre-feature installs (and
/// a removed selection) keep parsing with 2.5 Flash.
struct AISettingsTests {
    @Test func providerAndModelFallbackAndRoundTrip() {
        let defaults = UserDefaults.standard
        // Snapshot the (global) keys this test mutates, restore them afterwards.
        let snapProvider = defaults.string(forKey: AISettings.providerKey)
        let snapModel = defaults.string(forKey: AISettings.modelKey)
        defer {
            if let v = snapProvider { defaults.set(v, forKey: AISettings.providerKey) } else { defaults.removeObject(forKey: AISettings.providerKey) }
            if let v = snapModel { defaults.set(v, forKey: AISettings.modelKey) } else { defaults.removeObject(forKey: AISettings.modelKey) }
        }

        // Unset → provider defaults.
        defaults.removeObject(forKey: AISettings.providerKey)
        defaults.removeObject(forKey: AISettings.modelKey)
        #expect(AISettings.provider == .google)
        #expect(AISettings.modelID == AIProvider.google.defaultModel)

        // Empty string → same fallback (a removed selection never breaks scanning).
        defaults.set("", forKey: AISettings.modelKey)
        #expect(AISettings.modelID == AIProvider.google.defaultModel)

        // A real selection round-trips.
        AISettings.modelID = "gemini-3.0-pro"
        #expect(AISettings.modelID == "gemini-3.0-pro")
        #expect(defaults.string(forKey: AISettings.modelKey) == "gemini-3.0-pro")

        AISettings.provider = .google
        #expect(defaults.string(forKey: AISettings.providerKey) == "google")
    }
}
