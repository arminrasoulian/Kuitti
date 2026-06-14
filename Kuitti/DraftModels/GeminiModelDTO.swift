import Foundation

// Wire-format + value types for Google's ListModels REST API
// (GET https://generativelanguage.googleapis.com/v1beta/models). camelCase on the wire, so no
// key-decoding strategy is needed. `nonisolated` so they decode/encode off the main actor.

/// One page of the ListModels response.
nonisolated struct GeminiModelListResponse: Decodable, Sendable {
    struct Model: Decodable, Sendable {
        var name: String                              // "models/gemini-2.5-flash"
        var displayName: String?
        var description: String?
        var inputTokenLimit: Int?
        var outputTokenLimit: Int?
        var supportedGenerationMethods: [String]?
    }
    var models: [Model]?
    var nextPageToken: String?
}

/// A model the user can pick. Doubles as the on-disk cache payload (hence `Codable`), and is
/// `Identifiable`/`Hashable` so a SwiftUI `Picker` can tag rows by it.
nonisolated struct AIModel: Codable, Sendable, Identifiable, Hashable {
    var id: String              // model id with the "models/" prefix stripped, e.g. "gemini-2.5-flash"
    var displayName: String     // falls back to `id` when Google omits it
    var description: String?
    var inputTokenLimit: Int?
    var outputTokenLimit: Int?
}
