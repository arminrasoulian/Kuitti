import Foundation

/// Resolves how a product / line-item name is shown in the app's display language: the
/// app-language name as `primary`, the original-language name as `secondary` (a caption shown
/// only when it differs). A translation is surfaced only when the name's source language isn't
/// the app language — so English-only products read exactly as before.
nonisolated struct NameDisplay {
    let primary: String
    let secondary: String?

    init(original: String, translated: String, sourceLanguage: String) {
        let trimmedTranslated = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        // Show the translation when we have one and the original isn't already app-language.
        // An unknown source language ("") with a translation present still counts as foreign.
        let showTranslation = !trimmedTranslated.isEmpty && sourceLanguage != AppLanguage.current
        let primary = showTranslation ? trimmedTranslated : original
        self.primary = primary
        self.secondary = primary == original ? nil : original
    }
}

extension Product {
    /// App-language primary name with the original as a secondary caption when it differs.
    var nameDisplay: NameDisplay {
        NameDisplay(original: canonicalName, translated: translatedName, sourceLanguage: sourceLanguage)
    }
}

extension LineItem {
    /// Original = the edited/canonical display name, falling back to the raw receipt text.
    /// Line items carry no language of their own, so the gate borrows the linked product's
    /// source language (empty = treat any present translation as foreign).
    var nameDisplay: NameDisplay {
        let original = displayName.isEmpty ? rawName : displayName
        return NameDisplay(original: original, translated: translatedName, sourceLanguage: product?.sourceLanguage ?? "")
    }
}
