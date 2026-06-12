import Foundation

/// Direct REST client for the Gemini API. The model ID is a single constant: receipt
/// extraction is a low-creativity, high-volume vision task — exactly what 2.5 Flash is
/// positioned for; swap to a newer Flash here if extraction quality ever disappoints.
actor GeminiClient {
    static let modelID = "gemini-2.5-flash"

    nonisolated struct ReceiptPromptContext: Sendable {
        var knownProducts: [String] = []
        var knownAliases: [KnownAlias] = []
        var categories: [CategoryOption] = []
        var fallbackCategory: String = SeedCatalog.fallbackCategoryName
    }

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: - Public entry points

    /// One inline_data part per page (multi-page long receipts), prompt text after the
    /// images per the docs' guidance.
    func parseReceipt(pages: [Data], context: ReceiptPromptContext) async throws -> GeminiReceiptDTO {
        let today = Date().formatted(.iso8601.year().month().day())
        let prompt = GeminiSchemas.receiptPrompt(
            knownProducts: context.knownProducts,
            knownAliases: context.knownAliases,
            categories: context.categories,
            fallbackCategory: context.fallbackCategory,
            todayISO: today
        )
        let schema = GeminiSchemas.receiptResponseSchema(
            categoryNames: context.categories.map(\.name)
        )
        return try await generate(images: pages, prompt: prompt, schema: schema, as: GeminiReceiptDTO.self)
    }

    func identifyProduct(imageData: Data, knownProducts: [String]) async throws -> ProductIdentification {
        try await generate(
            images: [imageData],
            prompt: GeminiSchemas.productIDPrompt(knownProducts: knownProducts),
            schema: GeminiSchemas.productIDResponseSchema(),
            as: ProductIdentification.self
        )
    }

    /// Cheap probe used by the Settings "Test key" button.
    func validate(key: String) async -> Bool {
        let body = GeminiRequest(
            contents: [.init(parts: [.text("ping")])],
            generationConfig: .init(
                temperature: 0,
                maxOutputTokens: 10,
                thinkingConfig: .init(thinkingBudget: 0),
                responseMimeType: "text/plain",
                responseJsonSchema: nil
            )
        )
        guard let request = try? makeURLRequest(body: body, apiKey: key) else { return false }
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    // MARK: - Core

    private func generate<T: Decodable>(images: [Data], prompt: String, schema: JSONValue, as type: T.Type) async throws -> T {
        guard let apiKey = KeychainStore.readAPIKey() else { throw GeminiError.missingAPIKey }

        var parts: [GeminiRequest.Part] = images.map {
            .inlineData(mimeType: "image/jpeg", base64: $0.base64EncodedString())
        }
        parts.append(.text(prompt))

        let body = GeminiRequest(
            contents: [.init(parts: parts)],
            generationConfig: .init(
                temperature: 0.1,
                maxOutputTokens: 32768,
                thinkingConfig: .init(thinkingBudget: 0),
                responseMimeType: "application/json",
                responseJsonSchema: schema
            )
        )
        let urlRequest = try makeURLRequest(body: body, apiKey: apiKey)

        // Decode failures and truncation get exactly one fresh attempt (the model is
        // non-deterministic); transport-level retries live in sendWithRetry.
        do {
            return try await sendAndDecode(urlRequest, as: type)
        } catch let error as GeminiError {
            switch error {
            case .truncatedResponse, .responseSchemaMismatch:
                Log.gemini.error("Decode-level failure, retrying once: \(String(describing: error))")
                return try await sendAndDecode(urlRequest, as: type)
            default:
                throw error
            }
        }
    }

    private func sendAndDecode<T: Decodable>(_ urlRequest: URLRequest, as type: T.Type) async throws -> T {
        let data = try await sendWithRetry(urlRequest)
        let envelope: GeminiResponse
        do {
            envelope = try JSONDecoder().decode(GeminiResponse.self, from: data)
        } catch {
            throw GeminiError.responseSchemaMismatch(description: "envelope decode: \(error)")
        }
        if envelope.finishReason == "MAX_TOKENS" {
            throw GeminiError.truncatedResponse
        }
        guard let text = envelope.firstText, let payload = text.data(using: .utf8) else {
            throw GeminiError.responseSchemaMismatch(description: "empty candidates, finishReason=\(envelope.finishReason ?? "nil")")
        }
        do {
            return try JSONDecoder().decode(T.self, from: payload)
        } catch {
            Log.gemini.error("Payload decode failed: \(String(describing: error)), size=\(payload.count)B")
            throw GeminiError.responseSchemaMismatch(description: String(describing: error))
        }
    }

    private func makeURLRequest(body: GeminiRequest, apiKey: String) throws -> URLRequest {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.modelID):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func sendWithRetry(_ urlRequest: URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            attempt += 1
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch let urlError as URLError {
                if urlError.code == .timedOut && attempt == 1 {
                    try await Task.sleep(for: .seconds(2))
                    continue
                }
                throw NetworkError(urlError)
            }

            guard let http = response as? HTTPURLResponse else {
                throw NetworkError.transport(code: -1)
            }
            Log.gemini.info("HTTP \(http.statusCode), \(data.count)B, attempt \(attempt)")

            switch http.statusCode {
            case 200:
                return data
            case 401, 403:
                throw GeminiError.invalidAPIKey
            case 400:
                throw GeminiError.responseSchemaMismatch(description: "HTTP 400: \(String(data: data, encoding: .utf8) ?? "")")
            case 429:
                guard attempt <= 2 else { throw GeminiError.rateLimited(retryAfter: nil) }
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 10
                try await Task.sleep(for: .seconds(retryAfter))
            case 500...599:
                guard attempt <= 2 else { throw GeminiError.server(status: http.statusCode) }
                try await Task.sleep(for: .seconds(attempt == 1 ? 2 : 8))
            default:
                throw GeminiError.server(status: http.statusCode)
            }
        }
    }
}
