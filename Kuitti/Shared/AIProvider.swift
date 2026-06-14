import Foundation

/// The AI backends Kuitti can talk to. Only Google (Gemini) ships today, but the user-facing
/// provider picker and the per-provider metadata below are structured so adding another
/// provider later is additive — no call site assumes there's exactly one case. The raw String
/// backing lets it round-trip cleanly through `@AppStorage` / `PreferencesDTO`.
nonisolated enum AIProvider: String, CaseIterable, Codable, Sendable {
    case google

    var displayName: String {
        switch self {
        case .google: "Google Gemini"
        }
    }

    /// Shared REST prefix for both `models/{id}:generateContent` and the `models` list.
    var baseURL: String {
        switch self {
        case .google: "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    /// HTTP header the API key travels in.
    var keyHeader: String {
        switch self {
        case .google: "x-goog-api-key"
        }
    }

    /// Used until the user picks a model (and as the fallback for installs that predate the
    /// model picker) — receipt extraction is a low-creativity, high-volume vision task that
    /// 2.5 Flash is positioned for.
    var defaultModel: String {
        switch self {
        case .google: "gemini-2.5-flash"
        }
    }
}
