import Foundation

// Wire-format DTOs for the Gemini generateContent REST API. All money fields are decimal
// STRINGS by deliberate schema design: JSONDecoder routes JSON numbers through Double
// (1.20 → 1.2000000000000002) — Decimal(string:) is lossless.

nonisolated struct GeminiReceiptDTO: Codable, Sendable {
    struct StoreDTO: Codable, Sendable {
        var rawName: String?
        var normalizedName: String?
    }

    struct LineDTO: Codable, Sendable {
        var rawName: String
        var canonicalName: String
        var quantity: Double
        var unit: String
        var unitPrice: String?
        var lineTotal: String
        var suggestedCategory: String
        var uncertain: Bool
        var uncertaintyReason: String?
        var isDiscountOrDeposit: Bool
    }

    struct VatDTO: Codable, Sendable {
        var rate: Double
        var amount: String
        var base: String?
    }

    var isReceipt: Bool
    var store: StoreDTO
    var date: String?
    var time: String?
    var paymentMethod: String
    var lineItems: [LineDTO]
    var vatBreakdown: [VatDTO]
    var subtotal: String?
    var total: String?
    var currency: String
    var confidence: String
    var warnings: [String]
}

// MARK: - Request/response envelope

nonisolated struct GeminiRequest: Encodable, Sendable {
    struct Content: Encodable, Sendable {
        var parts: [Part]
    }

    enum Part: Encodable, Sendable {
        case text(String)
        case inlineData(mimeType: String, base64: String)

        private enum CodingKeys: String, CodingKey { case text, inlineData = "inline_data" }
        private enum InlineKeys: String, CodingKey { case mimeType = "mime_type", data }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode(text, forKey: .text)
            case .inlineData(let mimeType, let base64):
                var inline = container.nestedContainer(keyedBy: InlineKeys.self, forKey: .inlineData)
                try inline.encode(mimeType, forKey: .mimeType)
                try inline.encode(base64, forKey: .data)
            }
        }
    }

    struct GenerationConfig: Encodable, Sendable {
        var temperature: Double
        var maxOutputTokens: Int
        var thinkingConfig: ThinkingConfig
        var responseMimeType: String
        // Optional so the key-validation ping can omit it (synthesized Codable skips nil).
        var responseJsonSchema: JSONValue?
    }

    struct ThinkingConfig: Encodable, Sendable {
        var thinkingBudget: Int
    }

    var contents: [Content]
    var generationConfig: GenerationConfig
}

nonisolated struct GeminiResponse: Decodable, Sendable {
    struct Candidate: Decodable, Sendable {
        struct Content: Decodable, Sendable {
            struct Part: Decodable, Sendable {
                var text: String?
            }
            var parts: [Part]?
        }
        var content: Content?
        var finishReason: String?
    }
    var candidates: [Candidate]?

    var firstText: String? {
        candidates?.first?.content?.parts?.compactMap(\.text).joined()
    }

    var finishReason: String? {
        candidates?.first?.finishReason
    }
}
