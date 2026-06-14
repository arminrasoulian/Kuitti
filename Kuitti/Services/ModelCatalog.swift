import Foundation
import Observation

/// The live list of AI models the user can pick from, kept fresh by fetching Google's catalog
/// whenever the app opens. Mirrors `DuplicateScanner`: non-throwing, log-on-error (a failed
/// catalog fetch must never disrupt the app), async work then publish on the main actor. The
/// last-known list is cached in UserDefaults so the picker is populated instantly and offline,
/// and survives launches.
@Observable
@MainActor
final class ModelCatalog {
    enum LoadState: Equatable { case idle, loading, loaded, failed }

    private(set) var models: [AIModel]
    private(set) var state: LoadState = .idle

    @ObservationIgnored private let client: GeminiClient
    /// Dedupes the `.task` + `scenePhase .active` double-fire so the app open doesn't fetch twice.
    @ObservationIgnored private var inFlight = false

    private static let cacheKey = "aiModelCatalogCache"

    init(client: GeminiClient) {
        self.client = client
        self.models = Self.loadCache()
    }

    /// (Re)load the catalog. No-ops without a saved key or while a fetch is in flight. On
    /// success replaces `models` and caches it; on empty/error keeps the last-known list so the
    /// picker still works.
    func refresh() {
        guard !inFlight, let key = KeychainStore.readAPIKey() else { return }
        inFlight = true
        state = .loading
        Task {
            defer { inFlight = false }
            do {
                let fetched = try await client.listModels(key: key)
                guard !fetched.isEmpty else { state = .failed; return }
                models = fetched
                state = .loaded
                Self.saveCache(fetched)
            } catch {
                Log.gemini.error("Model catalog refresh failed: \(String(describing: error))")
                state = .failed
            }
        }
    }

    /// Adopt a list already fetched by the Settings/onboarding "Test key" path, avoiding a second
    /// network round-trip.
    func adopt(_ fetched: [AIModel]) {
        guard !fetched.isEmpty else { return }
        models = fetched
        state = .loaded
        Self.saveCache(fetched)
    }

    // MARK: - Cache (transient — never backed up; refresh() rebuilds it)

    private static func loadCache() -> [AIModel] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([AIModel].self, from: data) else { return [] }
        return decoded
    }

    private static func saveCache(_ models: [AIModel]) {
        if let data = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}
