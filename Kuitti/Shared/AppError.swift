import Foundation

nonisolated protocol UserPresentable {
    var userMessage: String { get }
    var isRetryable: Bool { get }
}

nonisolated enum AppError: Error, UserPresentable {
    case gemini(GeminiError)
    case network(NetworkError)
    case barcode(BarcodeError)
    case persistence(PersistenceError)
    case export(ExportError)
    case keychain(KeychainError)

    init(wrapping error: Error) {
        switch error {
        case let appError as AppError: self = appError
        case let geminiError as GeminiError: self = .gemini(geminiError)
        case let networkError as NetworkError: self = .network(networkError)
        case let barcodeError as BarcodeError: self = .barcode(barcodeError)
        case let urlError as URLError: self = .network(NetworkError(urlError))
        default: self = .persistence(.saveFailed(description: String(describing: error)))
        }
    }

    var userMessage: String {
        switch self {
        case .gemini(let e): e.userMessage
        case .network(let e): e.userMessage
        case .barcode(let e): e.userMessage
        case .persistence(let e): e.userMessage
        case .export(let e): e.userMessage
        case .keychain(let e): e.userMessage
        }
    }

    var isRetryable: Bool {
        switch self {
        case .gemini(let e): e.isRetryable
        case .network(let e): e.isRetryable
        case .barcode(let e): e.isRetryable
        case .persistence, .export, .keychain: false
        }
    }
}

nonisolated enum GeminiError: Error, UserPresentable {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited(retryAfter: TimeInterval?)
    /// The model said this isn't a readable receipt; carries its own explanation.
    case unparseableReceipt(reason: String?)
    case responseSchemaMismatch(description: String)
    case truncatedResponse
    case server(status: Int)

    var userMessage: String {
        switch self {
        case .missingAPIKey: "Add your Gemini API key in Settings to scan receipts."
        case .invalidAPIKey: "The Gemini API key was rejected. Check it in Settings."
        case .rateLimited: "Gemini is busy right now. Try again shortly."
        case .unparseableReceipt(let reason): reason ?? "Couldn't read this receipt. Retake the photo or enter it manually."
        case .responseSchemaMismatch: "Couldn't read this receipt. Retake the photo or enter it manually."
        case .truncatedResponse: "The receipt was too long to parse in one go. Try again or enter it manually."
        case .server: "Gemini had a server problem. Try again."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .missingAPIKey, .invalidAPIKey: false
        case .rateLimited, .unparseableReceipt, .responseSchemaMismatch, .truncatedResponse, .server: true
        }
    }
}

nonisolated enum NetworkError: Error, UserPresentable {
    case offline
    case timeout
    case transport(code: Int)

    init(_ urlError: URLError) {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: self = .offline
        case .timedOut: self = .timeout
        default: self = .transport(code: urlError.code.rawValue)
        }
    }

    var userMessage: String {
        switch self {
        case .offline: "You're offline. Scanning needs a connection — everything else still works."
        case .timeout: "The request timed out. Try again."
        case .transport: "A network error occurred. Try again."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .offline: false
        case .timeout, .transport: true
        }
    }
}

nonisolated enum BarcodeError: Error, UserPresentable {
    /// Not really an error in UX terms — the result screen renders the fallback flow.
    case productNotFound(ean: String)
    case offRateLimited
    case offUnavailable

    var userMessage: String {
        switch self {
        case .productNotFound: "Product not found. Add it manually or photograph the package."
        case .offRateLimited: "Too many lookups in a row — wait a moment and try again."
        case .offUnavailable: "Open Food Facts is unreachable right now."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .productNotFound: false
        case .offRateLimited, .offUnavailable: true
        }
    }
}

nonisolated enum PersistenceError: Error, UserPresentable {
    case saveFailed(description: String)
    case modelNotFound

    var userMessage: String {
        switch self {
        case .saveFailed: "Saving failed. Try again."
        case .modelNotFound: "That item no longer exists."
        }
    }

    var isRetryable: Bool { false }
}

nonisolated enum ExportError: Error, UserPresentable {
    case writeFailed

    var userMessage: String { "Export failed. Try again." }
    var isRetryable: Bool { true }
}

nonisolated enum KeychainError: Error, UserPresentable {
    case readFailed(OSStatus)
    case writeFailed(OSStatus)

    var userMessage: String { "Couldn't access the secure key storage." }
    var isRetryable: Bool { false }
}
