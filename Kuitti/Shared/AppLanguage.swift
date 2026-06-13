import Foundation

/// Single source of truth for the app's display language. Hardcoded to English in this
/// version; becomes a user setting when a language picker lands (only this constant and the
/// UI String Catalog change). Used as the translation TARGET for scanned product names
/// (Gemini), as the gate for the dual-name display helper (show a translation only when the
/// product's original language differs), and to pick the Open Food Facts name variant.
nonisolated enum AppLanguage {
    /// BCP-47 language code, e.g. "en", "fi".
    static let current = "en"
}
