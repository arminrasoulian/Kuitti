import Foundation

/// User's AI provider + model selection, stored in UserDefaults. Mirrors the
/// static-over-UserDefaults idiom of `AppLockController.isEnabled` / `AppLanguage.current`,
/// and is `nonisolated` so the `GeminiClient` actor can read `modelID` at request time the
/// same way it reads `KeychainStore.readAPIKey()`. The API key itself never lives here — it
/// stays in the Keychain.
nonisolated enum AISettings {
    static let providerKey = "aiProvider"
    static let modelKey = "aiModel"

    static var provider: AIProvider {
        get {
            UserDefaults.standard.string(forKey: providerKey).flatMap(AIProvider.init(rawValue:)) ?? .google
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    /// The model id used in the generateContent URL. Falls back to the provider's default
    /// when unset/empty, so installs that predate the model picker keep parsing with 2.5 Flash
    /// and a removed selection never breaks scanning silently.
    static var modelID: String {
        get {
            let stored = UserDefaults.standard.string(forKey: modelKey)
            return (stored?.isEmpty == false ? stored : nil) ?? provider.defaultModel
        }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }
}
