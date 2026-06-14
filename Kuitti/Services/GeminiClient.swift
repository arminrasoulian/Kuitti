import Foundation

/// Direct REST client for the Gemini API. The model id is user-selectable — read from
/// `AISettings.modelID` at request time (like the API key), falling back to the provider's
/// default. `listModels` fetches the live catalog so new Google models appear without a code
/// change. Receipt extraction is a low-creativity, high-volume vision task that 2.5 Flash
/// (the default) is positioned for.
actor GeminiClient {
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
            todayISO: today,
            appLanguage: AppLanguage.current
        )
        let schema = GeminiSchemas.receiptResponseSchema(
            categoryNames: context.categories.map(\.name),
            appLanguage: AppLanguage.current
        )
        return try await generate(images: pages, prompt: prompt, schema: schema, as: GeminiReceiptDTO.self)
    }

    func identifyProduct(imageData: Data, knownProducts: [String]) async throws -> ProductIdentification {
        try await generate(
            images: [imageData],
            prompt: GeminiSchemas.productIDPrompt(knownProducts: knownProducts, appLanguage: AppLanguage.current),
            schema: GeminiSchemas.productIDResponseSchema(appLanguage: AppLanguage.current),
            as: ProductIdentification.self
        )
    }

    /// Used by the Settings/onboarding "Test key" button. A successful ListModels both proves
    /// the key is valid and yields the catalog (the caller adopts the result), so key-checking
    /// and catalog-loading share one network path.
    func validate(key: String) async -> Bool {
        (try? await listModels(key: key)) != nil
    }

    /// Live catalog of Google models usable for receipt parsing — those whose
    /// `supportedGenerationMethods` includes `generateContent` (skips embedding / image / video
    /// / TTS models that can't read a receipt). Takes an explicit key so the "Test key" path can
    /// use it before saving; pages over `nextPageToken`. Reuses `sendWithRetry`, inheriting the
    /// 401/403→invalidAPIKey, 429→rateLimited, 5xx→server mapping.
    func listModels(key: String) async throws -> [AIModel] {
        var collected: [GeminiModelListResponse.Model] = []
        var pageToken: String?
        repeat {
            let data = try await sendWithRetry(makeListModelsRequest(key: key, pageToken: pageToken))
            let page: GeminiModelListResponse
            do {
                page = try JSONDecoder().decode(GeminiModelListResponse.self, from: data)
            } catch {
                throw GeminiError.responseSchemaMismatch(description: "models list decode: \(error)")
            }
            collected.append(contentsOf: page.models ?? [])
            pageToken = (page.nextPageToken?.isEmpty == false) ? page.nextPageToken : nil
        } while pageToken != nil
        return Self.mapModels(collected)
    }

    /// Pure transform (filter to generateContent-capable, strip the "models/" prefix, fall back
    /// displayName→id), split out so it's unit-testable without networking.
    nonisolated static func mapModels(_ models: [GeminiModelListResponse.Model]) -> [AIModel] {
        models
            .filter { $0.supportedGenerationMethods?.contains("generateContent") == true }
            .map { m in
                let id = m.name.hasPrefix("models/") ? String(m.name.dropFirst("models/".count)) : m.name
                return AIModel(
                    id: id,
                    displayName: m.displayName ?? id,
                    description: m.description,
                    inputTokenLimit: m.inputTokenLimit,
                    outputTokenLimit: m.outputTokenLimit
                )
            }
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
        let urlRequest = try makeURLRequest(model: AISettings.modelID, body: body, apiKey: apiKey)

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

    private func makeURLRequest(model: String, body: GeminiRequest, apiKey: String) throws -> URLRequest {
        let url = URL(string: "\(AIProvider.google.baseURL)/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: AIProvider.google.keyHeader)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func makeListModelsRequest(key: String, pageToken: String?) -> URLRequest {
        var components = URLComponents(string: "\(AIProvider.google.baseURL)/models")!
        var items = [URLQueryItem(name: "pageSize", value: "1000")]
        if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: AIProvider.google.keyHeader)
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
