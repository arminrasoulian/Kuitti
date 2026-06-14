import Foundation
import Testing
@testable import Kuitti

/// The size-aware, cross-language similarity engine behind duplicate detection.
struct ProductSimilarityTests {

    private func fp(_ name: String, ean: String? = nil, unit: UnitKind = .piece,
                    translated: String = "", lang: String = "", purchases: Int = 1) -> ProductSimilarity.Fingerprint {
        ProductSimilarity.Fingerprint(
            id: UUID(),
            canonicalName: name,
            normalizedKey: TextNormalizer.key(name),
            translatedName: translated,
            translatedNormalizedKey: TextNormalizer.key(translated),
            sourceLanguage: lang,
            ean: ean,
            unit: unit,
            purchaseCount: purchases
        )
    }

    @Test func sizeGuardSeparatesDifferentSizes() {
        // Same descriptive core, different printed size → never the same product.
        #expect(ProductSimilarity.compare(fp("Maito 1L"), fp("Maito 2L")) == nil)
    }

    @Test func sameSizeDifferentFormatIsHigh() {
        // "1L" vs "1 l" is the same size in different formatting → confident duplicate.
        #expect(ProductSimilarity.compare(fp("Maito 1L"), fp("Maito 1 l"))?.confidence == .high)
    }

    @Test func sameBarcodeIsDefinitive() {
        // Same EAN overrides differing names.
        let c = ProductSimilarity.compare(fp("Banaani", ean: "6411300000001"),
                                          fp("Banane", ean: "6411300000001"))
        #expect(c?.confidence == .high)
        #expect(c?.reason == "Same barcode")
    }

    @Test func crossLanguageBridgesViaTranslation() {
        // Finnish product carrying an English translation should pair with the English one,
        // even though the raw names ("banaani" vs "banana") aren't close enough alone.
        let fi = fp("Banaani", unit: .kilogram, translated: "Banana", lang: "fi")
        let en = fp("Banana", unit: .kilogram, lang: "en")
        let c = ProductSimilarity.compare(fi, en)
        #expect(c != nil)
        #expect(c?.confidence == .high)
        #expect(c?.reason == "Same product in two languages")
    }

    @Test func incompatibleUnitsAreNotCandidates() {
        // Piece-counted vs weight-priced are never the same product.
        #expect(ProductSimilarity.compare(fp("Banaani", unit: .piece), fp("Banaani", unit: .kilogram)) == nil)
    }

    @Test func unrelatedProductsAreNotCandidates() {
        #expect(ProductSimilarity.compare(fp("Maito"), fp("Olut")) == nil)
    }

    @Test func nearMatchIsPossibleTier() {
        // ~0.91 similarity, no size → the medium "possible" tier, not high.
        #expect(ProductSimilarity.compare(fp("Maitorahka"), fp("Maitorahkaa"))?.confidence == .medium)
    }

    @Test func sizeSignatureParsesOFFQuantityFormats() {
        // The Open Food Facts `quantity` string feeds the barcode flow's size-mismatch flag.
        #expect(ProductSimilarity.sizeSignature("2 x 0,5 l") == ["2x", "0.5l"])
        #expect(ProductSimilarity.sizeSignature("500 g") == ["500g"])
        #expect(ProductSimilarity.sizeSignature("33 cl") == ["33cl"])
        #expect(ProductSimilarity.sizeSignature("Bottle, no size").isEmpty)
    }

    @Test func catalogScanFindsCrossLanguagePairAndHonorsDismissals() {
        let a = fp("Banaani", unit: .kilogram, translated: "Banana", lang: "fi")
        let b = fp("Banana", unit: .kilogram, lang: "en")
        let c = fp("Maito 1L")   // unrelated — different token bucket
        let all = [a, b, c]

        let found = ProductSimilarity.duplicates(in: all, excluding: [])
        #expect(found.count == 1)
        #expect(found.first?.id == DismissedDuplicatePair.key(a.id, b.id))

        // Dismissing that pair removes it from the results.
        let excluded = ProductSimilarity.duplicates(in: all, excluding: [DismissedDuplicatePair.key(a.id, b.id)])
        #expect(excluded.isEmpty)
    }
}
