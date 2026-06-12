import Foundation
import SwiftData
import Testing
@testable import Kuitti

/// Fresh in-memory store per test, pre-seeded with the catalog categories/accounts.
func makeContext(seeded: Bool = true) throws -> ModelContext {
    let container = try ModelContainer(
        for: Schema(versionedSchema: SchemaV1.self),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    if seeded {
        try SeedDataService.seedIfNeeded(context: context)
    }
    return context
}

struct MoneyTests {
    @Test func decimalStringParsing() {
        #expect(Money.minorUnits(fromDecimalString: "4.95") == 495)
        #expect(Money.minorUnits(fromDecimalString: "-0.85") == -85)
        #expect(Money.minorUnits(fromDecimalString: "0.00") == 0)
        // The classic Double trap: 1.20 must be exactly 120 cents.
        #expect(Money.minorUnits(fromDecimalString: "1.20") == 120)
        #expect(Money.minorUnits(fromDecimalString: "19.99") == 1999)
        #expect(Money.minorUnits(fromDecimalString: "abc") == nil)
    }

    @Test func bankersRounding() {
        #expect(Money.minorUnits(from: Decimal(string: "1.005")!) == 100)  // rounds to even
        #expect(Money.minorUnits(from: Decimal(string: "1.015")!) == 102)
        #expect(Money.minorUnits(from: Decimal(string: "1.0149")!) == 101)
    }

    @Test func plainDecimalString() {
        #expect(Money.plainDecimalString(495) == "4.95")
        #expect(Money.plainDecimalString(-85) == "-0.85")
        #expect(Money.plainDecimalString(120000) == "1200.00")  // no grouping separator
    }
}

struct TextNormalizerTests {
    @Test func normalization() {
        #expect(TextNormalizer.key("  BANAANI  LUOMU ") == "banaani luomu")
        #expect(TextNormalizer.key("Arla Laktoositon, 1L!") == "arla laktoositon 1l")
        // Finnish letters preserved — folding would merge genuinely different words.
        #expect(TextNormalizer.key("SÄHKÖ") == "sähkö")
        #expect(TextNormalizer.key("PÄÄRYNÄ") != TextNormalizer.key("PAARYNA"))
    }
}

struct FuzzyMatchTests {
    @Test func exactAndNear() {
        #expect(FuzzyMatch.score("banaani", "banaani") == 1)
        #expect(FuzzyMatch.score("banaani", "banaan") > 0.8)
        #expect(FuzzyMatch.score("banaani", "maito rasvaton") < 0.5)
    }

    @Test func tokenOrderInsensitive() {
        #expect(FuzzyMatch.score("maito laktoositon arla", "arla laktoositon maito") > 0.95)
    }
}
