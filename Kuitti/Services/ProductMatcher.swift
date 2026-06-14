import Foundation
import SwiftData

nonisolated enum FuzzyMatch {
    /// max(levenshtein ratio, token-set ratio) on normalized keys, 0...1.
    static func score(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        let lev = levenshteinRatio(a, b)
        let tokens = tokenSetRatio(a, b)
        return max(lev, tokens)
    }

    static func levenshteinRatio(_ a: String, _ b: String) -> Double {
        let distance = levenshtein(Array(a), Array(b))
        let maxLength = max(a.count, b.count)
        return maxLength == 0 ? 1 : 1 - Double(distance) / Double(maxLength)
    }

    /// Order-insensitive: compare sorted unique token strings, blended with Jaccard overlap.
    static func tokenSetRatio(_ a: String, _ b: String) -> Double {
        let setA = Set(a.split(separator: " ").map(String.init))
        let setB = Set(b.split(separator: " ").map(String.init))
        guard !setA.isEmpty, !setB.isEmpty else { return 0 }
        let joinedA = setA.sorted().joined(separator: " ")
        let joinedB = setB.sorted().joined(separator: " ")
        let sortedRatio = levenshteinRatio(joinedA, joinedB)
        let jaccard = Double(setA.intersection(setB).count) / Double(setA.union(setB).count)
        return max(sortedRatio, jaccard)
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = Swift.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

/// Resolution order (the plan's §3.4): exact alias (user truth, free, offline) → local
/// fuzzy → Gemini's proposal as a new product. The user is the final authority exactly
/// once per new raw name per store; saving mints aliases so mistakes never recur.
struct ProductMatcher {
    let context: ModelContext

    static let fuzzyThreshold = 0.90

    func resolve(rawName: String, proposedCanonical: String, proposedTranslation: String = "", unit: UnitKind, store: Store?) -> ProductResolution {
        let key = TextNormalizer.key(rawName)
        guard !key.isEmpty else { return .newProduct }

        // STEP 1 — exact alias hit. Fetch by key, then prefer same-store over store-agnostic
        // in memory (relationship predicates are the flakiest part of #Predicate).
        let aliasFetch = FetchDescriptor<ProductAlias>(predicate: #Predicate { $0.normalizedRawName == key })
        if let aliases = try? context.fetch(aliasFetch), !aliases.isEmpty {
            let storeUUID = store?.uuid
            let match = aliases.first { $0.store?.uuid == storeUUID }
                ?? aliases.first { $0.store == nil }
            if let match, let product = match.product {
                match.hitCount += 1
                match.lastUsedAt = Date()
                return .confirmedAlias(productUUID: product.uuid)
            }
        }

        // STEP 2 — local fuzzy match against all canonical products (a few hundred rows).
        // The app-language translation is a SECOND scoring input (the hybrid bridge): the
        // same product scanned later in another language — German "Banane" translated to
        // "Banana" — still suggests the existing Finnish "Banaani" product, whose
        // translatedNormalizedKey is also "banana". Nothing auto-merges; the user confirms.
        let products = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        let proposedKey = TextNormalizer.key(proposedCanonical)
        let translatedKey = TextNormalizer.key(proposedTranslation)
        var best: (product: Product, score: Double)?
        for product in products {
            var score = max(
                FuzzyMatch.score(key, product.normalizedKey),
                FuzzyMatch.score(proposedKey, product.normalizedKey)
            )
            if !translatedKey.isEmpty {
                score = max(
                    score,
                    FuzzyMatch.score(translatedKey, product.translatedNormalizedKey),
                    FuzzyMatch.score(translatedKey, product.normalizedKey)
                )
            }
            if score > (best?.score ?? 0) { best = (product, score) }
        }
        if let best, best.score >= Self.fuzzyThreshold, unitsCompatible(unit, best.product.defaultUnit) {
            return .fuzzySuggested(productUUID: best.product.uuid, score: best.score)
        }

        // STEP 3 — Gemini's proposal becomes a new product on save.
        return .newProduct
    }

    /// Piece-counted and weight/volume-priced things are never the same product.
    private func unitsCompatible(_ a: UnitKind, _ b: UnitKind) -> Bool {
        if a == .other || b == .other { return true }
        let weighty: Set<UnitKind> = [.kilogram, .litre]
        return weighty.contains(a) == weighty.contains(b)
    }

    // MARK: - Upserts (logical uniqueness lives here — CloudKit forbids constraints)

    func findOrCreateProduct(canonicalName: String, defaultUnit: UnitKind,
                             translatedName: String = "", sourceLanguage: String = "") -> Product {
        let key = TextNormalizer.key(canonicalName)
        let trimmedTranslation = translatedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fetch = FetchDescriptor<Product>(predicate: #Predicate { $0.normalizedKey == key })
        if let existing = (try? context.fetch(fetch))?.first {
            // Forward-only enrichment: fill a missing translation when a fresh scan supplies
            // one (not a migration — existing untouched products simply stay untranslated).
            enrichTranslation(existing, translatedName: trimmedTranslation, sourceLanguage: sourceLanguage)
            return existing
        }
        let product = Product(canonicalName: canonicalName.trimmingCharacters(in: .whitespacesAndNewlines),
                              normalizedKey: key, defaultUnit: defaultUnit)
        product.translatedName = trimmedTranslation
        product.translatedNormalizedKey = TextNormalizer.key(trimmedTranslation)
        product.sourceLanguage = sourceLanguage
        context.insert(product)
        return product
    }

    /// Forward-only: fill a product's missing app-language translation from a fresh scan.
    /// No-op when the product already has a translation or the incoming one is empty.
    func enrichTranslation(_ product: Product, translatedName: String, sourceLanguage: String) {
        let trimmed = translatedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard product.translatedName.isEmpty, !trimmed.isEmpty else { return }
        product.translatedName = trimmed
        product.translatedNormalizedKey = TextNormalizer.key(trimmed)
        if product.sourceLanguage.isEmpty { product.sourceLanguage = sourceLanguage }
    }

    func product(withUUID uuid: UUID) -> Product? {
        let fetch = FetchDescriptor<Product>(predicate: #Predicate { $0.uuid == uuid })
        return (try? context.fetch(fetch))?.first
    }

    @discardableResult
    func upsertAlias(rawName: String, store: Store?, product: Product, source: AliasSource) -> ProductAlias {
        let key = TextNormalizer.key(rawName)
        let storeUUID = store?.uuid
        let fetch = FetchDescriptor<ProductAlias>(predicate: #Predicate { $0.normalizedRawName == key })
        if let existing = (try? context.fetch(fetch))?.first(where: { $0.store?.uuid == storeUUID }) {
            // Pointing the alias at the finally-chosen product overwrites a wrong mapping —
            // the same mistake can never recur.
            existing.product = product
            existing.hitCount += 1
            existing.lastUsedAt = Date()
            if source == .user { existing.sourceRaw = AliasSource.user.rawValue }
            return existing
        }
        let alias = ProductAlias(rawName: rawName, normalizedRawName: key, source: source)
        alias.store = store
        alias.product = product
        alias.hitCount = 1
        context.insert(alias)
        return alias
    }

    func findOrCreateStore(named name: String) -> Store? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = TextNormalizer.key(trimmed)
        let fetch = FetchDescriptor<Store>(predicate: #Predicate { $0.normalizedKey == key })
        if let existing = (try? context.fetch(fetch))?.first { return existing }
        let store = Store(name: trimmed, normalizedKey: key)
        context.insert(store)
        return store
    }

    /// A local product that might be the same thing as a scanned barcode's Open Food Facts
    /// record. `sizeMismatch` is true only when BOTH the OFF size and the product name carry a
    /// size signature and they differ (e.g. a single bottle vs a 2-pack) — surfaced so the
    /// user can tell them apart before linking, never used to hide a candidate.
    struct OFFCandidate {
        let product: Product
        let score: Double
        let sizeMismatch: Bool
    }

    /// Barcode flow: candidate local products for an Open Food Facts name/brand/size —
    /// receipt-born products have no EAN, so the first scan needs a fuzzy bridge. Size-aware:
    /// candidates whose printed size matches the scanned one sort first; mismatches are flagged
    /// (so a 0.5 L bottle isn't silently linked to a 2×0.5 L pack) but never dropped — the user
    /// inspects and decides. The 0.62 floor trims the worst fuzzy noise while keeping recall
    /// (cross-language / abbreviated receipt names need the headroom).
    func candidates(forOFFName name: String, brand: String?, offSize: String?) -> [OFFCandidate] {
        let products = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        let nameKey = TextNormalizer.key(name)
        let combinedKey = TextNormalizer.key([brand, name].compactMap(\.self).joined(separator: " "))
        let offSig = offSize.map(ProductSimilarity.sizeSignature) ?? []
        return products
            .map { product -> OFFCandidate in
                let score = max(FuzzyMatch.score(nameKey, product.normalizedKey),
                                FuzzyMatch.score(combinedKey, product.normalizedKey))
                // Read sizes from the un-normalized names so decimals survive ("0,5 l").
                let prodSig = ProductSimilarity.sizeSignature(product.canonicalName)
                    .union(ProductSimilarity.sizeSignature(product.translatedName))
                let sizeMismatch = !offSig.isEmpty && !prodSig.isEmpty && offSig != prodSig
                return OFFCandidate(product: product, score: score, sizeMismatch: sizeMismatch)
            }
            .filter { $0.score >= 0.62 }
            .sorted { a, b in
                if a.sizeMismatch != b.sizeMismatch { return !a.sizeMismatch }  // size-matches first
                return a.score > b.score
            }
            .prefix(5)
            .map { $0 }
    }

    /// User-driven duplicate merge ("Banaani" vs "Banana"): possible precisely because
    /// nothing is @Attribute(.unique). Reassigns the loser's history and identity to the
    /// survivor, then deletes the loser. Stats are recomputed by the caller via
    /// TransactionEditor.mergeProducts (the app-facing choke point).
    func merge(loser: Product, into survivor: Product) {
        guard loser.persistentModelID != survivor.persistentModelID else { return }
        for line in loser.lineItems ?? [] { line.product = survivor }
        for alias in loser.aliases ?? [] { alias.product = survivor }
        if survivor.ean == nil { survivor.ean = loser.ean }
        if survivor.brand == nil { survivor.brand = loser.brand }
        // Keep the loser's app-language translation if the survivor has none, so a merge
        // never silently loses the only translation.
        if survivor.translatedName.isEmpty, !loser.translatedName.isEmpty {
            survivor.translatedName = loser.translatedName
            survivor.translatedNormalizedKey = loser.translatedNormalizedKey
            if survivor.sourceLanguage.isEmpty { survivor.sourceLanguage = loser.sourceLanguage }
        }
        context.delete(loser)
        // Reassignment can leave two aliases with the same (store, normalizedRawName) on the
        // survivor — collapse them so the logical (store, rawName) key stays unique.
        dedupeAliases(of: survivor)
    }

    /// Collapse aliases on a product that share the logical key (store, normalizedRawName),
    /// summing hit counts and preferring a user-confirmed source.
    private func dedupeAliases(of product: Product) {
        var keep: [String: ProductAlias] = [:]
        for alias in product.aliases ?? [] {
            let key = "\(alias.store?.uuid.uuidString ?? "-")|\(alias.normalizedRawName)"
            if let existing = keep[key] {
                existing.hitCount += alias.hitCount
                if alias.source == .user { existing.sourceRaw = AliasSource.user.rawValue }
                existing.lastUsedAt = max(existing.lastUsedAt, alias.lastUsedAt)
                context.delete(alias)
            } else {
                keep[key] = alias
            }
        }
    }
}
