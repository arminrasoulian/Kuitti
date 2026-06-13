import Foundation
import SwiftData

/// Orchestrates a receipt parse: builds the prompt context from local data, calls Gemini,
/// maps the wire DTO into a ReceiptDraft (the single Decimal→cents ingestion boundary),
/// resolves products, and validates arithmetic. Pure logic beyond the API call — unit-tested.
struct ReceiptImportService {
    let gemini: GeminiClient

    func parse(pages: [Data], modelContext: ModelContext) async throws -> ReceiptDraft {
        let promptContext = Self.buildPromptContext(modelContext: modelContext)
        let categoryMap = Self.categoryUUIDMap(modelContext: modelContext)
        let dto = try await gemini.parseReceipt(pages: pages, context: promptContext)
        return try Self.draft(from: dto, pages: pages, categoryMap: categoryMap, modelContext: modelContext)
    }

    // MARK: - Prompt context (§8.4 of the plan)

    static func buildPromptContext(modelContext: ModelContext) -> GeminiClient.ReceiptPromptContext {
        var productsFetch = FetchDescriptor<Product>(sortBy: [SortDescriptor(\.purchaseCount, order: .reverse)])
        productsFetch.fetchLimit = 250
        let products = (try? modelContext.fetch(productsFetch)) ?? []

        var aliasFetch = FetchDescriptor<ProductAlias>(sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)])
        aliasFetch.fetchLimit = 150
        let aliases = (try? modelContext.fetch(aliasFetch)) ?? []

        return GeminiClient.ReceiptPromptContext(
            knownProducts: products.map(\.canonicalName),
            knownAliases: aliases.compactMap { alias in
                guard let canonical = alias.product?.canonicalName else { return nil }
                return KnownAlias(raw: alias.rawName, canonical: canonical)
            },
            categories: categoryOptions(modelContext: modelContext),
            // The actual fallback category name on THIS install (Finnish for existing users,
            // English for new ones) so Gemini's enum value matches a real category.
            fallbackCategory: fallbackCategory(modelContext: modelContext)?.name ?? SeedCatalog.fallbackCategoryName
        )
    }

    /// The undeletable "Other expenses" category, resolved by its stable seed identifier so it
    /// works regardless of the row's display-language name (existing installs may be Finnish,
    /// new installs are English).
    static func fallbackCategory(modelContext: ModelContext) -> Category? {
        let seedID: String? = SeedCatalog.fallbackCategorySeedID
        let fetch = FetchDescriptor<Category>(predicate: #Predicate { $0.seedIdentifier == seedID })
        return (try? modelContext.fetch(fetch))?.first
    }

    static func fallbackCategoryUUID(modelContext: ModelContext) -> UUID? {
        fallbackCategory(modelContext: modelContext)?.uuid
    }

    /// Deduplicated, expense-kind only (income categories must not be suggestable for
    /// receipt lines). Seed categories carry curated hints; user-created ones are name-only.
    static func categoryOptions(modelContext: ModelContext) -> [CategoryOption] {
        let expenseRaw = CategoryKind.expense.rawValue
        let fetch = FetchDescriptor<Category>(
            predicate: #Predicate { $0.kindRaw == expenseRaw },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let categories = (try? modelContext.fetch(fetch)) ?? []
        let hintsBySeedID = Dictionary(uniqueKeysWithValues: SeedCatalog.categories.map { ($0.id, $0.hint) })

        var seen = Set<String>()
        var options: [CategoryOption] = []
        for category in categories where seen.insert(category.name).inserted {
            let hint = category.seedIdentifier.flatMap { hintsBySeedID[$0] }
            options.append(CategoryOption(name: category.name, hint: hint))
        }
        return options
    }

    static func categoryUUIDMap(modelContext: ModelContext) -> [String: UUID] {
        let expenseRaw = CategoryKind.expense.rawValue
        let fetch = FetchDescriptor<Category>(
            predicate: #Predicate { $0.kindRaw == expenseRaw },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let categories = (try? modelContext.fetch(fetch)) ?? []
        var map: [String: UUID] = [:]
        for category in categories where map[category.name] == nil {
            map[category.name] = category.uuid
        }
        return map
    }

    // MARK: - DTO → draft mapping (testable; throws on "not a receipt")

    static func draft(from dto: GeminiReceiptDTO, pages: [Data], categoryMap: [String: UUID], modelContext: ModelContext) throws -> ReceiptDraft {
        guard dto.isReceipt, dto.confidence != "low" else {
            throw GeminiError.unparseableReceipt(reason: dto.warnings.first)
        }

        var warnings = dto.warnings
        let date = parseDate(dto.date, time: dto.time) ?? Date()
        let storeRaw = dto.store.rawName ?? ""
        let storeNormalized = dto.store.normalizedName ?? storeRaw
        let matcher = ProductMatcher(context: modelContext)
        // Resolve the store once so alias lookups during resolution are store-scoped.
        let existingStore: Store? = {
            let key = TextNormalizer.key(storeNormalized)
            guard !key.isEmpty else { return nil }
            let fetch = FetchDescriptor<Store>(predicate: #Predicate { $0.normalizedKey == key })
            return (try? modelContext.fetch(fetch))?.first
        }()

        // Resolved by seed ID, so it works even when the fallback category's name is in the
        // user's original language (the constant string would miss it).
        let fallbackCategoryUUID = fallbackCategoryUUID(modelContext: modelContext)

        var lines: [LineDraft] = []
        for (index, lineDTO) in dto.lineItems.enumerated() {
            guard let totalMinor = Money.minorUnits(fromDecimalString: lineDTO.lineTotal) else {
                warnings.append("Dropped unparseable line: \(lineDTO.rawName)")
                continue
            }
            let (unit, quantity) = mapUnit(lineDTO.unit, quantity: lineDTO.quantity)

            var uncertain = lineDTO.uncertain
            var reason = lineDTO.uncertaintyReason
            // Per-line arithmetic check: quantity × unitPrice ≈ lineTotal (±1 cent).
            if let unitPriceString = lineDTO.unitPrice,
               let unitPriceMinor = Money.minorUnits(fromDecimalString: unitPriceString),
               quantity > 0 {
                let expected = Int((Double(unitPriceMinor) * quantity).rounded())
                if abs(expected - totalMinor) > 1 && !uncertain {
                    uncertain = true
                    reason = reason ?? "quantity × unit price doesn't match the line total"
                }
            }

            let resolution: ProductResolution = lineDTO.isDiscountOrDeposit
                ? .notAProduct
                : matcher.resolve(
                    rawName: lineDTO.rawName,
                    proposedCanonical: lineDTO.canonicalName,
                    proposedTranslation: lineDTO.translatedName ?? "",
                    unit: unit,
                    store: existingStore
                )

            lines.append(LineDraft(
                rawName: lineDTO.rawName,
                canonicalName: lineDTO.canonicalName,
                translatedName: lineDTO.translatedName,
                sourceLanguage: lineDTO.sourceLanguage,
                quantity: quantity,
                unit: unit,
                lineTotalMinor: totalMinor,
                isDiscountOrDeposit: lineDTO.isDiscountOrDeposit,
                uncertain: uncertain,
                uncertaintyReason: reason,
                suggestedCategoryUUID: categoryMap[lineDTO.suggestedCategory] ?? fallbackCategoryUUID,
                chosenCategoryUUID: nil,
                resolution: resolution,
                sortOrder: index
            ))
        }

        let vatLines: [VatLine] = dto.vatBreakdown.compactMap { vat in
            guard let tax = Money.minorUnits(fromDecimalString: vat.amount) else { return nil }
            return VatLine(
                ratePercent: vat.rate,
                baseMinor: vat.base.flatMap(Money.minorUnits(fromDecimalString:)),
                taxMinor: tax
            )
        }

        // Date sanity (badged, never blocking).
        if date > Date().addingTimeInterval(86_400) {
            warnings.append("Receipt date is in the future — check it.")
        } else if date < Date().addingTimeInterval(-2 * 365 * 86_400) {
            warnings.append("Receipt date is over two years old — check it.")
        }

        return ReceiptDraft(
            storeRawName: storeRaw,
            storeNormalizedName: storeNormalized,
            date: date,
            paymentMethod: mapPaymentMethod(dto.paymentMethod),
            lines: lines,
            subtotalMinor: dto.subtotal.flatMap(Money.minorUnits(fromDecimalString:)),
            vatLines: vatLines,
            totalMinor: dto.total.flatMap(Money.minorUnits(fromDecimalString:)),
            confidence: ParseConfidence(rawValue: dto.confidence) ?? .medium,
            warnings: warnings,
            pages: pages
        )
    }

    /// Explicit schema→model mapping (plan §8.4): grams convert to kilograms so all
    /// weight-priced history lives in one unit.
    static func mapUnit(_ unit: String, quantity: Double) -> (UnitKind, Double) {
        switch unit {
        case "pcs": (.piece, quantity)
        case "kg": (.kilogram, quantity)
        case "g": (.kilogram, quantity / 1000)
        case "l": (.litre, quantity)
        default: (.other, quantity)
        }
    }

    static func mapPaymentMethod(_ method: String) -> PaymentMethod {
        switch method {
        case "card": .card
        case "cash": .cash
        case "mobile": .mobilePay
        case "other": .other
        default: .unknown
        }
    }

    static func parseDate(_ date: String?, time: String?) -> Date? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = time != nil ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd"
        if let time, let combined = formatter.date(from: "\(date) \(time)") {
            return combined
        }
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }
}
