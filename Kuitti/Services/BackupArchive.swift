import Foundation

/// Portable, logical snapshot of everything Kuitti stores **except the Keychain API key**.
/// One Codable DTO per @Model, with related objects referenced by `uuid` so the whole graph
/// can be rebuilt on restore regardless of SwiftData's internal ids. Enums travel as their
/// raw strings; `Data` fields (receipt images, the VAT-lines blob) ride along as base64 via
/// JSONEncoder. Bump `formatVersion` on any incompatible change.
nonisolated struct BackupArchive: Codable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var schemaVersion: String
    var appVersion: String
    var createdAt: Date

    var preferences: PreferencesDTO
    var accounts: [AccountDTO]
    var categories: [CategoryDTO]
    var stores: [StoreDTO]
    var products: [ProductDTO]
    var productAliases: [ProductAliasDTO]
    var transactions: [TransactionDTO]
    var lineItems: [LineItemDTO]
    var receiptImages: [ReceiptImageDTO]
    var recurringTemplates: [RecurringTemplateDTO]
    var dismissedDuplicatePairs: [DismissedDuplicatePairDTO]
}

/// Backed-up app preferences (all non-secret). The API key in the Keychain is deliberately omitted.
/// `aiProvider`/`aiModel` are optional so archives written before the model picker still decode
/// (additive change — no formatVersion bump).
nonisolated struct PreferencesDTO: Codable {
    var appearancePreference: String
    var hasOnboarded: Bool
    var appLockEnabled: Bool
    var dismissedSeedIdentifiers: [String]
    var aiProvider: String?
    var aiModel: String?
}

nonisolated struct AccountDTO: Codable {
    var uuid: UUID
    var name: String
    var typeRaw: String
    var initialBalanceMinor: Int
    var iconName: String
    var colorHex: String
    var isDefault: Bool
    var isArchived: Bool
    var sortOrder: Int
    var seedIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct CategoryDTO: Codable {
    var uuid: UUID
    var name: String
    var iconName: String
    var colorHex: String
    var kindRaw: String
    var monthlyBudgetMinor: Int?
    var sortOrder: Int
    var isUserCreated: Bool
    var seedIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct StoreDTO: Codable {
    var uuid: UUID
    var name: String
    var normalizedKey: String
    var iconName: String
    var createdAt: Date
}

nonisolated struct ProductDTO: Codable {
    var uuid: UUID
    var canonicalName: String
    var normalizedKey: String
    var translatedName: String
    var sourceLanguage: String
    var translatedNormalizedKey: String
    var defaultUnitRaw: String
    var ean: String?
    var brand: String?
    var lastPurchasedAt: Date?
    var lastUnitPrice: Double?
    var lastStoreName: String?
    var purchaseCount: Int
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct ProductAliasDTO: Codable {
    var uuid: UUID
    var rawName: String
    var normalizedRawName: String
    var sourceRaw: String
    var hitCount: Int
    var createdAt: Date
    var lastUsedAt: Date
    var storeUUID: UUID?
    var productUUID: UUID?
}

nonisolated struct TransactionDTO: Codable {
    var uuid: UUID
    var kindRaw: String
    var date: Date
    var amountMinor: Int
    var currencyCode: String
    var payee: String
    var notes: String
    var paymentMethodRaw: String
    var sourceRaw: String
    var subtotalMinor: Int?
    var vatLinesData: Data
    var importWarnings: [String]
    var createdAt: Date
    var updatedAt: Date
    var accountUUID: UUID?
    var categoryUUID: UUID?
    var storeUUID: UUID?
}

nonisolated struct LineItemDTO: Codable {
    var uuid: UUID
    var rawName: String
    var displayName: String
    var translatedName: String
    var quantity: Double
    var unitRaw: String
    var lineTotalMinor: Int
    var unitPrice: Double
    var isDiscountOrDeposit: Bool
    var quantityIsUncertain: Bool
    var purchaseDate: Date
    var sortOrder: Int
    var notes: String
    var transactionUUID: UUID?
    var categoryUUID: UUID?
    var productUUID: UUID?
}

nonisolated struct ReceiptImageDTO: Codable {
    var uuid: UUID
    var imageData: Data?
    var pageIndex: Int
    var capturedAt: Date
    var transactionUUID: UUID?
}

nonisolated struct RecurringTemplateDTO: Codable {
    var uuid: UUID
    var name: String
    var kindRaw: String
    var amountMinor: Int
    var frequencyRaw: String
    var interval: Int
    var nextDueDate: Date
    var endDate: Date?
    var isActive: Bool
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var accountUUID: UUID?
    var categoryUUID: UUID?
}

nonisolated struct DismissedDuplicatePairDTO: Codable {
    var uuid: UUID
    var productAUUID: UUID
    var productBUUID: UUID
    var pairKey: String
    var createdAt: Date
}
