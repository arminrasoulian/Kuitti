import Foundation
import Testing
@testable import Kuitti

/// Decode + map of Google's ListModels response: filtering to generateContent-capable models,
/// stripping the "models/" id prefix, and the displayName→id fallback. Also the AIModel cache
/// round-trip used by ModelCatalog.
struct GeminiModelDTOTests {
    static let listJSON = """
    {
      "models": [
        {
          "name": "models/gemini-2.5-flash",
          "displayName": "Gemini 2.5 Flash",
          "description": "Fast multimodal model",
          "inputTokenLimit": 1048576,
          "outputTokenLimit": 65536,
          "supportedGenerationMethods": ["generateContent", "countTokens"]
        },
        {
          "name": "models/text-embedding-004",
          "displayName": "Text Embedding 004",
          "supportedGenerationMethods": ["embedContent"]
        },
        {
          "name": "models/gemini-flash-latest",
          "supportedGenerationMethods": ["generateContent"]
        }
      ],
      "nextPageToken": ""
    }
    """

    @Test func decodesAndMapsOnlyGenerateContentModels() throws {
        let response = try JSONDecoder().decode(GeminiModelListResponse.self, from: Data(Self.listJSON.utf8))
        let models = GeminiClient.mapModels(response.models ?? [])

        // The embedding-only model is filtered out; only the two generateContent ones survive.
        #expect(models.count == 2)
        #expect(!models.contains { $0.id == "text-embedding-004" })

        // "models/" prefix stripped; metadata carried through.
        let flash = try #require(models.first { $0.id == "gemini-2.5-flash" })
        #expect(flash.displayName == "Gemini 2.5 Flash")
        #expect(flash.inputTokenLimit == 1_048_576)
        #expect(flash.outputTokenLimit == 65_536)

        // displayName falls back to the id when Google omits it.
        let latest = try #require(models.first { $0.id == "gemini-flash-latest" })
        #expect(latest.displayName == "gemini-flash-latest")
    }

    @Test func aiModelCacheRoundTrips() throws {
        let models = [
            AIModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash",
                    description: "x", inputTokenLimit: 100, outputTokenLimit: 200)
        ]
        let data = try JSONEncoder().encode(models)
        #expect(try JSONDecoder().decode([AIModel].self, from: data) == models)
    }
}
