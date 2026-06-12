import Foundation
import SwiftData

/// The single choke point for all transaction/line-item mutations. Views never mutate
/// models ad hoc — every save path runs through here so the denormalized invariants hold:
///   1. LineItem.purchaseDate mirrors transaction.date (price history sorts on it)
///   2. LineItem.unitPrice rederives from lineTotalMinor/quantity
///   3. transaction.amountMinor = Σ line totals when itemized (unless user-overridden)
///   4. Product.last* stats recompute for every touched product
struct TransactionEditor {
    let context: ModelContext

    // MARK: - Receipt save (the review screen's Save button)

    @discardableResult
    func saveReceipt(draft: ReceiptDraft, account: Account?) throws -> Transaction {
        let matcher = ProductMatcher(context: context)
        let store = matcher.findOrCreateStore(named: draft.storeNormalizedName.isEmpty ? draft.storeRawName : draft.storeNormalizedName)

        let transaction = Transaction(
            kind: .expense,
            date: draft.date,
            amountMinor: max(draft.totalMinor ?? draft.lineSumMinor, 0),
            payee: store?.name ?? draft.storeRawName,
            source: .receiptScan
        )
        transaction.paymentMethod = draft.paymentMethod
        transaction.subtotalMinor = draft.subtotalMinor
        transaction.vatLines = draft.vatLines
        transaction.account = account
        transaction.store = store
        var warnings = draft.warnings
        if let mismatch = draft.totalMismatchMinor {
            warnings.append("Saved with a totals mismatch of \(Money.euros(mismatch)) between line items and the printed total.")
        }
        transaction.importWarnings = warnings
        context.insert(transaction)

        var touchedProducts: Set<PersistentIdentifier> = []
        var touched: [Product] = []

        for draftLine in draft.lines {
            let item = LineItem(
                rawName: draftLine.rawName,
                displayName: draftLine.canonicalName,
                quantity: draftLine.quantity,
                unit: draftLine.unit,
                lineTotalMinor: draftLine.lineTotalMinor,
                sortOrder: draftLine.sortOrder
            )
            item.purchaseDate = draft.date
            item.isDiscountOrDeposit = draftLine.isDiscountOrDeposit
            item.quantityIsUncertain = draftLine.uncertain
            if let reason = draftLine.uncertaintyReason, !reason.isEmpty {
                item.notes = reason
            }
            item.transaction = transaction
            item.category = category(withUUID: draftLine.chosenCategoryUUID ?? draftLine.suggestedCategoryUUID)

            // Product linking + the learning step: saving the review screen is implicit
            // confirmation, so even untouched lines mint aliases — the next receipt from
            // this store resolves with zero AI calls.
            switch draftLine.resolution {
            case .notAProduct:
                break
            case .confirmedAlias(let uuid), .fuzzySuggested(let uuid, _):
                if let product = matcher.product(withUUID: uuid) {
                    item.product = product
                    let source: AliasSource = {
                        if case .confirmedAlias = draftLine.resolution { return .user }
                        return .fuzzyAuto
                    }()
                    matcher.upsertAlias(rawName: draftLine.rawName, store: store, product: product, source: source)
                }
            case .newProduct:
                let product = matcher.findOrCreateProduct(canonicalName: draftLine.canonicalName, defaultUnit: draftLine.unit)
                item.product = product
                matcher.upsertAlias(rawName: draftLine.rawName, store: store, product: product, source: .gemini)
            }
            context.insert(item)
            if let product = item.product, touchedProducts.insert(product.persistentModelID).inserted {
                touched.append(product)
            }
        }

        for (index, page) in draft.pages.enumerated() {
            let image = ReceiptImage(imageData: page, pageIndex: index)
            image.transaction = transaction
            context.insert(image)
        }

        for product in touched { recomputeStats(for: product) }
        try save()
        return transaction
    }

    // MARK: - Manual create / edit / delete

    @discardableResult
    func createManual(kind: TransactionKind, date: Date, amountMinor: Int, payee: String,
                      account: Account?, category: Category?, notes: String,
                      paymentMethod: PaymentMethod, source: TransactionSource = .manual) throws -> Transaction {
        let transaction = Transaction(kind: kind, date: date, amountMinor: amountMinor, payee: payee, source: source)
        transaction.account = account
        transaction.category = category
        transaction.notes = notes
        transaction.paymentMethod = paymentMethod
        context.insert(transaction)
        try save()
        return transaction
    }

    /// Call after any in-place edit of a transaction or its line items.
    /// amountOverridden: the user typed the total explicitly — don't recompute from lines.
    func didEdit(_ transaction: Transaction, amountOverridden: Bool = false) throws {
        transaction.updatedAt = Date()
        var touched: [Product] = []
        var seen: Set<PersistentIdentifier> = []

        for item in transaction.lineItems ?? [] {
            item.purchaseDate = transaction.date
            item.unitPrice = item.quantity != 0 ? Double(item.lineTotalMinor) / 100.0 / item.quantity : 0
            if let product = item.product, seen.insert(product.persistentModelID).inserted {
                touched.append(product)
            }
        }
        if !(transaction.lineItems ?? []).isEmpty && !amountOverridden {
            transaction.amountMinor = max(transaction.lineItems!.reduce(0) { $0 + $1.lineTotalMinor }, 0)
        }
        for product in touched { recomputeStats(for: product) }
        try save()
    }

    func delete(_ transaction: Transaction) throws {
        // Collect affected products before the cascade removes the line items.
        var touched: [Product] = []
        var seen: Set<PersistentIdentifier> = []
        for item in transaction.lineItems ?? [] {
            if let product = item.product, seen.insert(product.persistentModelID).inserted {
                touched.append(product)
            }
        }
        context.delete(transaction)
        try save()
        for product in touched { recomputeStats(for: product) }
        try save()
    }

    // MARK: - Denormalized product stats

    /// Full recompute per product on any save/edit/delete — cheap at this scale and
    /// immune to incremental-update bugs.
    func recomputeStats(for product: Product) {
        let items = (product.lineItems ?? []).sorted { $0.purchaseDate < $1.purchaseDate }
        product.purchaseCount = items.count
        if let last = items.last {
            product.lastPurchasedAt = last.purchaseDate
            product.lastUnitPrice = last.unitPrice
            product.lastStoreName = last.transaction?.store?.name ?? last.transaction?.payee
        } else {
            product.lastPurchasedAt = nil
            product.lastUnitPrice = nil
            product.lastStoreName = nil
        }
        product.updatedAt = Date()
    }

    // MARK: - Helpers

    private func category(withUUID uuid: UUID?) -> Category? {
        guard let uuid else { return nil }
        let fetch = FetchDescriptor<Category>(predicate: #Predicate { $0.uuid == uuid })
        return (try? context.fetch(fetch))?.first
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            Log.persistence.error("Save failed: \(String(describing: error))")
            throw AppError.persistence(.saveFailed(description: String(describing: error)))
        }
    }
}
