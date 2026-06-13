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

    /// Barcode flow: candidate local products for an Open Food Facts name/brand —
    /// receipt-born products have no EAN, so the first scan needs a fuzzy bridge.
    func candidates(forOFFName name: String, brand: String?) -> [(product: Product, score: Double)] {
        let products = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        let nameKey = TextNormalizer.key(name)
        let combinedKey = TextNormalizer.key([brand, name].compactMap(\.self).joined(separator: " "))
        return products
            .map { product in
                (product, max(FuzzyMatch.score(nameKey, product.normalizedKey),
                              FuzzyMatch.score(combinedKey, product.normalizedKey)))
            }
            .filter { $0.1 >= 0.6 }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { ($0.0, $0.1) }
    }

    /// User-driven duplicate merge ("Banaani" vs "Banana"): possible precisely because
    /// nothing is @Attribute(.unique).
    func merge(loser: Product, into survivor: Product) {
        for line in loser.lineItems ?? [] { line.product = survivor }
        for alias in loser.aliases ?? [] { alias.product = survivor }
        if survivor.ean == nil { survivor.ean = loser.ean }
        if survivor.brand == nil { survivor.brand = loser.brand }
        context.delete(loser)
    }
}
