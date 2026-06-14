import Foundation
import SwiftData

/// Exports/restores the full data graph (everything except the Keychain API key) as a
/// compressed JSON archive. Restore is **replace-all**: it wipes every model, then rebuilds
/// from the archive, relinking relationships by `uuid`. Runs on the passed context (the
/// caller shows a spinner); SwiftData `@Query` views refresh automatically afterwards.
struct BackupService {
    let context: ModelContext

    // UserDefaults keys (mirror the literals used across the app).
    private static let appearanceKey = "appearancePreference"
    private static let onboardedKey = "hasOnboarded"
    private static let tombstoneKey = "dismissedSeedIdentifiers"   // == SeedDataService.tombstoneKey

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // MARK: - Export

    func export() throws -> BackupArchive {
        BackupArchive(
            formatVersion: BackupArchive.currentFormatVersion,
            schemaVersion: String(describing: SchemaV1.versionIdentifier),
            appVersion: Self.appVersion,
            createdAt: Date(),
            preferences: PreferencesDTO(
                appearancePreference: UserDefaults.standard.string(forKey: Self.appearanceKey) ?? "system",
                hasOnboarded: UserDefaults.standard.bool(forKey: Self.onboardedKey),
                appLockEnabled: AppLockController.isEnabled,
                dismissedSeedIdentifiers: UserDefaults.standard.stringArray(forKey: Self.tombstoneKey) ?? []
            ),
            accounts: try fetch(Account.self).map(Self.dto(from:)),
            categories: try fetch(Category.self).map(Self.dto(from:)),
            stores: try fetch(Store.self).map(Self.dto(from:)),
            products: try fetch(Product.self).map(Self.dto(from:)),
            productAliases: try fetch(ProductAlias.self).map(Self.dto(from:)),
            transactions: try fetch(Transaction.self).map(Self.dto(from:)),
            lineItems: try fetch(LineItem.self).map(Self.dto(from:)),
            receiptImages: try fetch(ReceiptImage.self).map(Self.dto(from:)),
            recurringTemplates: try fetch(RecurringTemplate.self).map(Self.dto(from:)),
            dismissedDuplicatePairs: try fetch(DismissedDuplicatePair.self).map(Self.dto(from:))
        )
    }

    private func fetch<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    // MARK: - Encode / decode (zlib-compressed JSON)

    nonisolated static func encode(_ archive: BackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(archive)
        return try (json as NSData).compressed(using: .zlib) as Data
    }

    nonisolated static func decode(_ data: Data) throws -> BackupArchive {
        // Tolerate a plain (uncompressed) JSON file too.
        let json = (try? (data as NSData).decompressed(using: .zlib) as Data) ?? data
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupArchive.self, from: json)
    }

    // MARK: - Restore (replace-all)

    func restore(_ archive: BackupArchive) throws {
        try wipeAll()

        // Pass 1: insert the entities other things point at, keyed by uuid.
        var accounts: [UUID: Account] = [:]
        for dto in archive.accounts {
            let model = Account(name: dto.name)
            model.uuid = dto.uuid
            model.typeRaw = dto.typeRaw
            model.initialBalanceMinor = dto.initialBalanceMinor
            model.iconName = dto.iconName
            model.colorHex = dto.colorHex
            model.isDefault = dto.isDefault
            model.isArchived = dto.isArchived
            model.sortOrder = dto.sortOrder
            model.seedIdentifier = dto.seedIdentifier
            model.createdAt = dto.createdAt
            model.updatedAt = dto.updatedAt
            context.insert(model)
            accounts[dto.uuid] = model
        }

        var categories: [UUID: Category] = [:]
        for dto in archive.categories {
            let model = Category(name: dto.name)
            model.uuid = dto.uuid
            model.iconName = dto.iconName
            model.colorHex = dto.colorHex
            model.kindRaw = dto.kindRaw
            model.monthlyBudgetMinor = dto.monthlyBudgetMinor
            model.sortOrder = dto.sortOrder
            model.isUserCreated = dto.isUserCreated
            model.seedIdentifier = dto.seedIdentifier
            model.createdAt = dto.createdAt
            model.updatedAt = dto.updatedAt
            context.insert(model)
            categories[dto.uuid] = model
        }

        var stores: [UUID: Store] = [:]
        for dto in archive.stores {
            let model = Store(name: dto.name, normalizedKey: dto.normalizedKey)
            model.uuid = dto.uuid
            model.iconName = dto.iconName
            model.createdAt = dto.createdAt
            context.insert(model)
            stores[dto.uuid] = model
        }

        var products: [UUID: Product] = [:]
        for dto in archive.products {
            let model = Product(canonicalName: dto.canonicalName, normalizedKey: dto.normalizedKey)
            model.uuid = dto.uuid
            model.translatedName = dto.translatedName
            model.sourceLanguage = dto.sourceLanguage
            model.translatedNormalizedKey = dto.translatedNormalizedKey
            model.defaultUnitRaw = dto.defaultUnitRaw
            model.ean = dto.ean
            model.brand = dto.brand
            model.lastPurchasedAt = dto.lastPurchasedAt
            model.lastUnitPrice = dto.lastUnitPrice
            model.lastStoreName = dto.lastStoreName
            model.purchaseCount = dto.purchaseCount
            model.createdAt = dto.createdAt
            model.updatedAt = dto.updatedAt
            context.insert(model)
            products[dto.uuid] = model
        }

        // Pass 2: insert the dependents, wiring relationships from the maps above.
        var transactions: [UUID: Transaction] = [:]
        for dto in archive.transactions {
            let model = Transaction(kind: .expense, date: dto.date, amountMinor: dto.amountMinor)
            model.uuid = dto.uuid
            model.kindRaw = dto.kindRaw
            model.currencyCode = dto.currencyCode
            model.payee = dto.payee
            model.notes = dto.notes
            model.paymentMethodRaw = dto.paymentMethodRaw
            model.sourceRaw = dto.sourceRaw
            model.subtotalMinor = dto.subtotalMinor
            model.vatLinesData = dto.vatLinesData
            model.importWarnings = dto.importWarnings
            model.createdAt = dto.createdAt
            model.updatedAt = dto.updatedAt
            model.account = dto.accountUUID.flatMap { accounts[$0] }
            model.category = dto.categoryUUID.flatMap { categories[$0] }
            model.store = dto.storeUUID.flatMap { stores[$0] }
            context.insert(model)
            transactions[dto.uuid] = model
        }

        for dto in archive.lineItems {
            let model = LineItem(rawName: dto.rawName, displayName: dto.displayName,
                                 quantity: dto.quantity, unit: UnitKind(rawValue: dto.unitRaw) ?? .piece,
                                 lineTotalMinor: dto.lineTotalMinor, sortOrder: dto.sortOrder)
            model.uuid = dto.uuid
            model.translatedName = dto.translatedName
            model.unitRaw = dto.unitRaw
            model.unitPrice = dto.unitPrice
            model.isDiscountOrDeposit = dto.isDiscountOrDeposit
            model.quantityIsUncertain = dto.quantityIsUncertain
            model.purchaseDate = dto.purchaseDate
            model.notes = dto.notes
            model.transaction = dto.transactionUUID.flatMap { transactions[$0] }
            model.category = dto.categoryUUID.flatMap { categories[$0] }
            model.product = dto.productUUID.flatMap { products[$0] }
            context.insert(model)
        }

        for dto in archive.receiptImages {
            let model = ReceiptImage(imageData: dto.imageData ?? Data(), pageIndex: dto.pageIndex)
            model.uuid = dto.uuid
            model.imageData = dto.imageData
            model.capturedAt = dto.capturedAt
            model.transaction = dto.transactionUUID.flatMap { transactions[$0] }
            context.insert(model)
        }

        for dto in archive.productAliases {
            let model = ProductAlias(rawName: dto.rawName, normalizedRawName: dto.normalizedRawName,
                                     source: AliasSource(rawValue: dto.sourceRaw) ?? .user)
            model.uuid = dto.uuid
            model.sourceRaw = dto.sourceRaw
            model.hitCount = dto.hitCount
            model.createdAt = dto.createdAt
            model.lastUsedAt = dto.lastUsedAt
            model.store = dto.storeUUID.flatMap { stores[$0] }
            model.product = dto.productUUID.flatMap { products[$0] }
            context.insert(model)
        }

        for dto in archive.recurringTemplates {
            let model = RecurringTemplate(name: dto.name, kind: .expense, amountMinor: dto.amountMinor,
                                          frequency: .monthly, nextDueDate: dto.nextDueDate)
            model.uuid = dto.uuid
            model.kindRaw = dto.kindRaw
            model.frequencyRaw = dto.frequencyRaw
            model.interval = dto.interval
            model.endDate = dto.endDate
            model.isActive = dto.isActive
            model.notes = dto.notes
            model.createdAt = dto.createdAt
            model.updatedAt = dto.updatedAt
            model.account = dto.accountUUID.flatMap { accounts[$0] }
            model.category = dto.categoryUUID.flatMap { categories[$0] }
            context.insert(model)
        }

        for dto in archive.dismissedDuplicatePairs {
            let model = DismissedDuplicatePair(productA: dto.productAUUID, productB: dto.productBUUID)
            model.uuid = dto.uuid
            model.pairKey = dto.pairKey
            model.createdAt = dto.createdAt
            context.insert(model)
        }

        // Preferences (never the API key — that stays in the Keychain, untouched).
        UserDefaults.standard.set(archive.preferences.appearancePreference, forKey: Self.appearanceKey)
        UserDefaults.standard.set(archive.preferences.hasOnboarded, forKey: Self.onboardedKey)
        AppLockController.isEnabled = archive.preferences.appLockEnabled
        UserDefaults.standard.set(archive.preferences.dismissedSeedIdentifiers, forKey: Self.tombstoneKey)

        try context.save()
    }

    private func wipeAll() throws {
        try context.delete(model: LineItem.self)
        try context.delete(model: ReceiptImage.self)
        try context.delete(model: ProductAlias.self)
        try context.delete(model: Transaction.self)
        try context.delete(model: Product.self)
        try context.delete(model: Store.self)
        try context.delete(model: Category.self)
        try context.delete(model: Account.self)
        try context.delete(model: RecurringTemplate.self)
        try context.delete(model: DismissedDuplicatePair.self)
        try context.save()
    }

    // MARK: - Model → DTO

    private static func dto(from m: Account) -> AccountDTO {
        AccountDTO(uuid: m.uuid, name: m.name, typeRaw: m.typeRaw, initialBalanceMinor: m.initialBalanceMinor,
                   iconName: m.iconName, colorHex: m.colorHex, isDefault: m.isDefault, isArchived: m.isArchived,
                   sortOrder: m.sortOrder, seedIdentifier: m.seedIdentifier, createdAt: m.createdAt, updatedAt: m.updatedAt)
    }

    private static func dto(from m: Category) -> CategoryDTO {
        CategoryDTO(uuid: m.uuid, name: m.name, iconName: m.iconName, colorHex: m.colorHex, kindRaw: m.kindRaw,
                    monthlyBudgetMinor: m.monthlyBudgetMinor, sortOrder: m.sortOrder, isUserCreated: m.isUserCreated,
                    seedIdentifier: m.seedIdentifier, createdAt: m.createdAt, updatedAt: m.updatedAt)
    }

    private static func dto(from m: Store) -> StoreDTO {
        StoreDTO(uuid: m.uuid, name: m.name, normalizedKey: m.normalizedKey, iconName: m.iconName, createdAt: m.createdAt)
    }

    private static func dto(from m: Product) -> ProductDTO {
        ProductDTO(uuid: m.uuid, canonicalName: m.canonicalName, normalizedKey: m.normalizedKey,
                   translatedName: m.translatedName, sourceLanguage: m.sourceLanguage,
                   translatedNormalizedKey: m.translatedNormalizedKey, defaultUnitRaw: m.defaultUnitRaw,
                   ean: m.ean, brand: m.brand, lastPurchasedAt: m.lastPurchasedAt, lastUnitPrice: m.lastUnitPrice,
                   lastStoreName: m.lastStoreName, purchaseCount: m.purchaseCount, createdAt: m.createdAt, updatedAt: m.updatedAt)
    }

    private static func dto(from m: ProductAlias) -> ProductAliasDTO {
        ProductAliasDTO(uuid: m.uuid, rawName: m.rawName, normalizedRawName: m.normalizedRawName, sourceRaw: m.sourceRaw,
                        hitCount: m.hitCount, createdAt: m.createdAt, lastUsedAt: m.lastUsedAt,
                        storeUUID: m.store?.uuid, productUUID: m.product?.uuid)
    }

    private static func dto(from m: Transaction) -> TransactionDTO {
        TransactionDTO(uuid: m.uuid, kindRaw: m.kindRaw, date: m.date, amountMinor: m.amountMinor,
                       currencyCode: m.currencyCode, payee: m.payee, notes: m.notes, paymentMethodRaw: m.paymentMethodRaw,
                       sourceRaw: m.sourceRaw, subtotalMinor: m.subtotalMinor, vatLinesData: m.vatLinesData,
                       importWarnings: m.importWarnings, createdAt: m.createdAt, updatedAt: m.updatedAt,
                       accountUUID: m.account?.uuid, categoryUUID: m.category?.uuid, storeUUID: m.store?.uuid)
    }

    private static func dto(from m: LineItem) -> LineItemDTO {
        LineItemDTO(uuid: m.uuid, rawName: m.rawName, displayName: m.displayName, translatedName: m.translatedName,
                    quantity: m.quantity, unitRaw: m.unitRaw, lineTotalMinor: m.lineTotalMinor, unitPrice: m.unitPrice,
                    isDiscountOrDeposit: m.isDiscountOrDeposit, quantityIsUncertain: m.quantityIsUncertain,
                    purchaseDate: m.purchaseDate, sortOrder: m.sortOrder, notes: m.notes,
                    transactionUUID: m.transaction?.uuid, categoryUUID: m.category?.uuid, productUUID: m.product?.uuid)
    }

    private static func dto(from m: ReceiptImage) -> ReceiptImageDTO {
        ReceiptImageDTO(uuid: m.uuid, imageData: m.imageData, pageIndex: m.pageIndex, capturedAt: m.capturedAt,
                        transactionUUID: m.transaction?.uuid)
    }

    private static func dto(from m: RecurringTemplate) -> RecurringTemplateDTO {
        RecurringTemplateDTO(uuid: m.uuid, name: m.name, kindRaw: m.kindRaw, amountMinor: m.amountMinor,
                             frequencyRaw: m.frequencyRaw, interval: m.interval, nextDueDate: m.nextDueDate,
                             endDate: m.endDate, isActive: m.isActive, notes: m.notes, createdAt: m.createdAt,
                             updatedAt: m.updatedAt, accountUUID: m.account?.uuid, categoryUUID: m.category?.uuid)
    }

    private static func dto(from m: DismissedDuplicatePair) -> DismissedDuplicatePairDTO {
        DismissedDuplicatePairDTO(uuid: m.uuid, productAUUID: m.productAUUID, productBUUID: m.productBUUID,
                                  pairKey: m.pairKey, createdAt: m.createdAt)
    }
}
