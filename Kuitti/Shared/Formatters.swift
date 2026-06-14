import Foundation

/// All authoritative money is Int EUR cents. These helpers are the single ingestion and
/// display boundary: decimal strings parse via Decimal (never Double) and round bankers-style
/// exactly once; formatting always goes through FormatStyle.currency.
nonisolated enum Money {
    /// Parse a dot-separated decimal string ("4.95", "-0.85") into cents. Lossless.
    static func minorUnits(fromDecimalString string: String) -> Int? {
        guard let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return minorUnits(from: decimal)
    }

    /// Round to 2 places (bankers) and convert to cents.
    static func minorUnits(from decimal: Decimal) -> Int {
        var value = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .bankers)
        let cents = rounded * 100
        return NSDecimalNumber(decimal: cents).intValue
    }

    static func decimal(fromMinor minor: Int) -> Decimal {
        Decimal(minor) / 100
    }

    /// "12,34 €" in the user's locale (fi_FI shows comma decimals and trailing €).
    static func euros(_ minor: Int) -> String {
        decimal(fromMinor: minor).formatted(.currency(code: "EUR"))
    }

    /// Signed variant for list rows: expenses negative.
    static func signedEuros(_ signedMinor: Int) -> String {
        euros(signedMinor)
    }

    /// Plain "12.34" with dot separator — for CSV (RFC-4180 mode) and Gemini round-trips.
    static func plainDecimalString(_ minor: Int) -> String {
        let d = decimal(fromMinor: minor)
        return d.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX")).grouping(.never))
    }
}

nonisolated enum TextNormalizer {
    /// Matching key for products/stores/aliases: trim, lowercase, collapse whitespace,
    /// strip punctuation. Finnish ä/ö/å are PRESERVED — folding them would merge
    /// genuinely different words.
    static func key(_ input: String) -> String {
        let lowered = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let kept = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                return Character(scalar)
            }
            return " "
        }
        let collapsed = String(kept)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return collapsed
    }
}

/// Human-readable file sizes ("2.5 MB") for the backup list.
nonisolated enum FileSize {
    static func string(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
