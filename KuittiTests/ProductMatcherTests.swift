import Foundation
import SwiftData
import Testing
@testable import Kuitti

struct ProductMatcherTests {
    @Test func aliasBeatsFuzzyAndLearns() throws {
        let context = try makeContext()
        let matcher = ProductMatcher(context: context)

        let banana = matcher.findOrCreateProduct(canonicalName: "Banaani", defaultUnit: .kilogram)
        let lidl = matcher.findOrCreateStore(named: "Lidl")
        matcher.upsertAlias(rawName: "BANAANI", store: lidl, product: banana, source: .user)
        try context.save()

        // Same raw name at the same store: exact alias hit, no AI involved.
        let resolution = matcher.resolve(rawName: "BANAANI", proposedCanonical: "Banana", unit: .kilogram, store: lidl)
        #expect(resolution == .confirmedAlias(productUUID: banana.uuid))
    }

    @Test func aliasOverwriteFixesMistakes() throws {
        let context = try makeContext()
        let matcher = ProductMatcher(context: context)
        let wrong = matcher.findOrCreateProduct(canonicalName: "Omena", defaultUnit: .kilogram)
        let right = matcher.findOrCreateProduct(canonicalName: "Banaani", defaultUnit: .kilogram)
        let store = matcher.findOrCreateStore(named: "Prisma")

        matcher.upsertAlias(rawName: "BANAANI", store: store, product: wrong, source: .gemini)
        matcher.upsertAlias(rawName: "BANAANI", store: store, product: right, source: .user)
        try context.save()

        let aliases = try context.fetch(FetchDescriptor<ProductAlias>())
        // One alias per (store, raw name) — repointed, not duplicated.
        #expect(aliases.count == 1)
        #expect(aliases.first?.product?.uuid == right.uuid)
    }

    @Test func translationBridgesCrossLanguageMatches() throws {
        let context = try makeContext()
        let matcher = ProductMatcher(context: context)
        // A Finnish product that already carries an English (app-language) translation.
        _ = matcher.findOrCreateProduct(canonicalName: "Banaani", defaultUnit: .kilogram,
                                        translatedName: "Banana", sourceLanguage: "fi")
        try context.save()

        // A later German line: neither the raw text "BANANE" nor the canonical "Banane"
        // is close enough to "banaani", but the shared English translation bridges them.
        let bridged = matcher.resolve(rawName: "BANANE", proposedCanonical: "Banane",
                                      proposedTranslation: "Banana", unit: .kilogram, store: nil)
        guard case .fuzzySuggested(let uuid, let score) = bridged else {
            Issue.record("expected a fuzzy suggestion via the translation bridge, got \(bridged)")
            return
        }
        let banaani = try context.fetch(FetchDescriptor<Product>()).first { $0.canonicalName == "Banaani" }
        #expect(uuid == banaani?.uuid)
        #expect(score >= ProductMatcher.fuzzyThreshold)

        // Negative control: without the translation, the German name alone must NOT match —
        // the bridge is precisely what makes the cross-language suggestion possible.
        let unbridged = matcher.resolve(rawName: "BANANE", proposedCanonical: "Banane",
                                        proposedTranslation: "", unit: .kilogram, store: nil)
        #expect(unbridged == .newProduct)
    }

    @Test func fuzzySuggestsCloseNames() throws {
        let context = try makeContext()
        let matcher = ProductMatcher(context: context)
        let product = matcher.findOrCreateProduct(canonicalName: "Arla laktoositon maito 1L", defaultUnit: .piece)
        try context.save()

        let resolution = matcher.resolve(
            rawName: "ARLA LAKT MAITO 1L",
            proposedCanonical: "Arla laktoositon maito 1l",
            unit: .piece,
            store: nil
        )
        guard case .fuzzySuggested(let uuid, let score) = resolution else {
            Issue.record("expected fuzzy suggestion, got \(resolution)")
            return
        }
        #expect(uuid == product.uuid)
        #expect(score >= 0.90)
    }

    @Test func incompatibleUnitsDontMatch() throws {
        let context = try makeContext()
        let matcher = ProductMatcher(context: context)
        _ = matcher.findOrCreateProduct(canonicalName: "Banaani", defaultUnit: .kilogram)
        try context.save()

        // Piece-counted vs weight-priced: same-ish name must NOT fuzzy-match.
        let resolution = matcher.resolve(rawName: "BANAANI", proposedCanonical: "Banaani", unit: .piece, store: nil)
        #expect(resolution == .newProduct)
    }

    @Test func findOrCreateIsAnUpsert() throws {
        let context = try makeContext()
        let matcher = ProductMatcher(context: context)
        let first = matcher.findOrCreateProduct(canonicalName: "Banaani", defaultUnit: .kilogram)
        let second = matcher.findOrCreateProduct(canonicalName: "  banaani ", defaultUnit: .kilogram)
        #expect(first.persistentModelID == second.persistentModelID)
    }

    @Test func mergeReassignsHistoryAndAliases() throws {
        let context = try makeContext()
        let matcher = ProductMatcher(context: context)
        let survivor = matcher.findOrCreateProduct(canonicalName: "Banaani", defaultUnit: .kilogram)
        let loser = matcher.findOrCreateProduct(canonicalName: "Banana", defaultUnit: .kilogram)
        loser.ean = "6411300000001"
        let line = LineItem(rawName: "BANANA", displayName: "Banana", quantity: 1, unit: .kilogram, lineTotalMinor: 120)
        line.product = loser
        context.insert(line)
        matcher.upsertAlias(rawName: "BANANA", store: nil, product: loser, source: .gemini)
        try context.save()

        matcher.merge(loser: loser, into: survivor)
        try context.save()

        #expect(line.product?.uuid == survivor.uuid)
        #expect(survivor.ean == "6411300000001")
        let products = try context.fetch(FetchDescriptor<Product>())
        #expect(products.count == 1)
        let aliases = try context.fetch(FetchDescriptor<ProductAlias>())
        #expect(aliases.allSatisfy { $0.product?.uuid == survivor.uuid })
    }

    @Test func offCandidatesBridgeReceiptBornProducts() throws {
        let context = try makeContext()
        let matcher = ProductMatcher(context: context)
        _ = matcher.findOrCreateProduct(canonicalName: "Valio rasvaton maito 1L", defaultUnit: .piece)
        _ = matcher.findOrCreateProduct(canonicalName: "Banaani", defaultUnit: .kilogram)
        try context.save()

        let candidates = matcher.candidates(forOFFName: "Rasvaton maito", brand: "Valio")
        #expect(candidates.first?.product.canonicalName == "Valio rasvaton maito 1L")
    }
}
