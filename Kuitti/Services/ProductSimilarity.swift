import Foundation

/// Size-aware, cross-language product-similarity engine — the single source of truth for
/// "are these two products the same thing?". Pure value logic (`nonisolated`) over Sendable
/// snapshots so the whole-catalog scan runs off the main actor and never touches SwiftData.
/// Used by `DuplicateScanner` (the proactive scan) and the post-scan nudge.
nonisolated enum ProductSimilarity {

    // MARK: - Tuning
    /// Balanced sensitivity (owner decision). High = confident duplicate; Medium = "possible".
    static let highThreshold = 0.93
    static let mediumThreshold = 0.85

    // MARK: - Snapshot

    /// Main-actor-built value snapshot of a `Product`, safe to score off-main.
    struct Fingerprint: Sendable, Identifiable {
        let id: UUID
        let canonicalName: String
        let normalizedKey: String
        let translatedNormalizedKey: String
        let sourceLanguage: String
        let ean: String?
        let unit: UnitKind
        let purchaseCount: Int

        /// Canonical size/quantity signature parsed from the names ("1l", "500g", "6x"); a
        /// MISMATCH means different products. Derived from the un-normalized canonical name so
        /// decimals survive ("0,5 l" → "0.5l").
        let sizeSignature: Set<String>
        /// Descriptive core (normalized key minus size/number tokens) used for name fuzzing.
        let coreKey: String
        let translatedCoreKey: String

        init(id: UUID, canonicalName: String, normalizedKey: String,
             translatedName: String, translatedNormalizedKey: String,
             sourceLanguage: String, ean: String?, unit: UnitKind, purchaseCount: Int) {
            self.id = id
            self.canonicalName = canonicalName
            self.normalizedKey = normalizedKey
            self.translatedNormalizedKey = translatedNormalizedKey
            self.sourceLanguage = sourceLanguage
            self.ean = ean
            self.unit = unit
            self.purchaseCount = purchaseCount
            self.sizeSignature = ProductSimilarity.sizeSignature(canonicalName)
                .union(ProductSimilarity.sizeSignature(translatedName))
            self.coreKey = ProductSimilarity.stripSizeTokens(normalizedKey)
            self.translatedCoreKey = ProductSimilarity.stripSizeTokens(translatedNormalizedKey)
        }
    }

    // MARK: - Candidate

    enum Confidence: String, Sendable { case high, medium }

    struct Candidate: Sendable, Identifiable {
        let id: String        // order-independent pair key
        let a: UUID
        let b: UUID
        let score: Double
        let confidence: Confidence
        let reason: String
    }

    // MARK: - Pair scoring

    /// Returns a candidate when the two products look like the same thing, else nil.
    static func compare(_ p1: Fingerprint, _ p2: Fingerprint) -> Candidate? {
        guard p1.id != p2.id else { return nil }
        let pairKey = DismissedDuplicatePair.key(p1.id, p2.id)

        // 1. Same barcode is definitive — overrides the size/unit guards.
        if let e1 = p1.ean, let e2 = p2.ean, !e1.isEmpty, e1 == e2 {
            return Candidate(id: pairKey, a: p1.id, b: p2.id, score: 1, confidence: .high, reason: "Same barcode")
        }

        // 2. Piece-counted vs weight/volume-priced are never the same product.
        guard unitsCompatible(p1.unit, p2.unit) else { return nil }

        // 3. Size guard: different printed sizes (1 L vs 2 L) are different products.
        let bothSized = !p1.sizeSignature.isEmpty && !p2.sizeSignature.isEmpty
        if bothSized && p1.sizeSignature != p2.sizeSignature { return nil }
        let oneSizeMissing = p1.sizeSignature.isEmpty != p2.sizeSignature.isEmpty

        // 4. Name similarity: descriptive core, plus the translation bridge for cross-language.
        let core = FuzzyMatch.score(p1.coreKey, p2.coreKey)
        var cross = 0.0
        if !p1.translatedCoreKey.isEmpty {
            cross = max(cross, FuzzyMatch.score(p1.translatedCoreKey, p2.coreKey))
            if !p2.translatedCoreKey.isEmpty {
                cross = max(cross, FuzzyMatch.score(p1.translatedCoreKey, p2.translatedCoreKey))
            }
        }
        if !p2.translatedCoreKey.isEmpty {
            cross = max(cross, FuzzyMatch.score(p2.translatedCoreKey, p1.coreKey))
        }
        let crossExact =
            (!p1.translatedCoreKey.isEmpty && p1.translatedCoreKey == p2.coreKey) ||
            (!p2.translatedCoreKey.isEmpty && p2.translatedCoreKey == p1.coreKey) ||
            (!p1.translatedCoreKey.isEmpty && p1.translatedCoreKey == p2.translatedCoreKey)
        let name = max(core, cross)
        guard name >= mediumThreshold else { return nil }

        let crossLanguage = cross > core
        let reason: String = crossLanguage ? "Same product in two languages"
            : (name >= 0.97 ? "Nearly identical names" : "Similar names")

        // 5. Tiers. A missing size on one side can't be "high" — could be generic vs specific.
        let isHigh = !oneSizeMissing && (name >= highThreshold || crossExact)
        return Candidate(id: pairKey, a: p1.id, b: p2.id, score: name,
                         confidence: isHigh ? .high : .medium, reason: reason)
    }

    /// Piece-counted and weight/volume-priced things are never the same product.
    /// (Mirrors ProductMatcher's scan-time rule.)
    static func unitsCompatible(_ a: UnitKind, _ b: UnitKind) -> Bool {
        if a == .other || b == .other { return true }
        let weighty: Set<UnitKind> = [.kilogram, .litre]
        return weighty.contains(a) == weighty.contains(b)
    }

    // MARK: - Catalog scan (inverted-index blocking to avoid O(n²))

    static func duplicates(in fingerprints: [Fingerprint], excluding dismissed: Set<String>) -> [Candidate] {
        let n = fingerprints.count
        guard n > 1 else { return [] }

        // Index by descriptive tokens (size tokens already stripped, so "Maito 1L" and
        // "Olut 1L" don't pair on "1l"). A Finnish product contributes its English
        // translated-core tokens too, so cross-language pairs share a token.
        var tokenIndex: [String: [Int]] = [:]
        var eanIndex: [String: [Int]] = [:]
        for (i, fp) in fingerprints.enumerated() {
            let tokens = Set(fp.coreKey.split(separator: " ").map(String.init))
                .union(fp.translatedCoreKey.split(separator: " ").map(String.init))
            for token in tokens { tokenIndex[token, default: []].append(i) }
            if let ean = fp.ean, !ean.isEmpty { eanIndex[ean, default: []].append(i) }
        }

        var seen = Set<Int>()
        var candidates: [Candidate] = []
        func consider(_ i: Int, _ j: Int) {
            let lo = min(i, j), hi = max(i, j)
            guard seen.insert(lo * n + hi).inserted else { return }
            let key = DismissedDuplicatePair.key(fingerprints[lo].id, fingerprints[hi].id)
            guard !dismissed.contains(key) else { return }
            if let candidate = compare(fingerprints[lo], fingerprints[hi]) {
                candidates.append(candidate)
            }
        }
        for bucket in tokenIndex.values where bucket.count > 1 {
            for a in 0..<bucket.count { for b in (a + 1)..<bucket.count { consider(bucket[a], bucket[b]) } }
        }
        for bucket in eanIndex.values where bucket.count > 1 {
            for a in 0..<bucket.count { for b in (a + 1)..<bucket.count { consider(bucket[a], bucket[b]) } }
        }

        return candidates.sorted {
            if $0.confidence != $1.confidence { return $0.confidence == .high }
            return $0.score > $1.score
        }
    }

    // MARK: - Size token parsing

    // NSRegularExpression matching is thread-safe; safe to share across the off-main scan.
    nonisolated(unsafe) private static let sizeRegex = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)\s*(kpl|pkt|prk|kg|ml|cl|dl|ps|l|g|x)\b"#,
        options: [.caseInsensitive]
    )

    /// Canonical size tokens parsed from a display name: "Maito 1L" → ["1l"], "Olut 6x0,33l"
    /// → ["6x", "0.33l"]. Decimal-safe because it reads the un-normalized name.
    static func sizeSignature(_ name: String) -> Set<String> {
        let lower = name.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)
        var result: Set<String> = []
        for match in sizeRegex.matches(in: lower, range: range) {
            guard match.numberOfRanges >= 3,
                  let valueRange = Range(match.range(at: 1), in: lower),
                  let unitRange = Range(match.range(at: 2), in: lower) else { continue }
            let rawValue = lower[valueRange].replacingOccurrences(of: ",", with: ".")
            let unit = String(lower[unitRange])
            let value = Double(rawValue).map(formatNumber) ?? rawValue
            result.insert("\(value)\(unit)")
        }
        return result
    }

    /// Normalized-key tokens with size/number tokens removed — the descriptive core.
    static func stripSizeTokens(_ normalizedKey: String) -> String {
        normalizedKey.split(separator: " ").map(String.init)
            .filter { !isSizeToken($0) }
            .joined(separator: " ")
    }

    private static let unitSuffixes = ["kpl", "pkt", "prk", "kg", "ml", "cl", "dl", "ps", "l", "g", "x"]

    private static func isSizeToken(_ token: String) -> Bool {
        if token.isEmpty { return false }
        if token.allSatisfy(\.isNumber) { return true }                 // "6", "500", "1"
        for suffix in unitSuffixes where token.hasSuffix(suffix) {
            let prefix = String(token.dropLast(suffix.count))
            if prefix.isEmpty { return true }                            // bare unit "l", "kg"
            if prefix.allSatisfy(\.isNumber) { return true }             // "1l", "500g", "33cl"
        }
        return false
    }

    private static func formatNumber(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%g", d)
    }
}
