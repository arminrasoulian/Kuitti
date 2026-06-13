import Foundation

nonisolated struct KnownAlias: Sendable {
    var raw: String
    var canonical: String
}

nonisolated struct CategoryOption: Sendable {
    var name: String
    /// One-line semantic hint (seed categories have curated hints; user-created ones are name-only).
    var hint: String?
}

/// Builds the responseJsonSchema documents and prompt templates for the Gemini calls.
/// Dialect notes: standard-JSON-Schema subset only — no `pattern`/`minLength`/`const`/
/// `default`/`allOf`; nullability via type arrays; no `propertyOrdering` (that belongs to
/// the legacy OpenAPI responseSchema dialect). All keys are `required` so absent-vs-null
/// is never ambiguous.
nonisolated enum GeminiSchemas {

    /// "en" -> "English" for prompt/schema copy; falls back to the raw code.
    static func languageName(_ code: String) -> String {
        Locale(identifier: "en_US_POSIX").localizedString(forLanguageCode: code) ?? code
    }

    // MARK: - Receipt parsing

    static func receiptResponseSchema(categoryNames: [String], appLanguage: String) -> JSONValue {
        let categoryEnum = JSONValue.array(categoryNames.map { .string($0) })
        let appLanguageName = languageName(appLanguage)
        let moneyString: JSONValue = ["type": "string"]
        let nullableMoneyString: JSONValue = ["type": .array(["string", "null"])]

        let lineItem: JSONValue = [
            "type": "object",
            "properties": [
                "rawName": ["type": "string", "description": "Product text exactly as printed (merge continuation lines)."],
                "canonicalName": ["type": "string", "description": "Clean human-readable product name in the receipt's ORIGINAL language, per the canonicalization rules in the prompt."],
                "sourceLanguage": ["type": "string", "enum": ["fi", "sv", "de", "nl", "it", "es", "en", "unknown"], "description": "Detected language of this line's printed product text."],
                "translatedName": ["type": .array(["string", "null"]), "description": .string("canonicalName translated into \(appLanguageName). Null if canonicalName is already in \(appLanguageName), or is a brand/proper noun that should not be translated.")],
                "quantity": ["type": "number", "description": "Count or weight/volume. 0.652 for '0,652 kg'. 1 if a single line with no quantity."],
                "unit": ["type": "string", "enum": ["pcs", "kg", "g", "l", "unknown"]],
                "unitPrice": ["type": .array(["string", "null"]), "description": "Price per unit as decimal string, '.' separator, 2 decimals, e.g. '2.99'. Compute as lineTotal/quantity if not printed. Null only if not derivable."],
                "lineTotal": ["type": "string", "description": "Line total as decimal string, e.g. '1.95'. Negative for discounts/returns, e.g. '-0.85'."],
                "suggestedCategory": ["type": "string", "enum": categoryEnum],
                "uncertain": ["type": "boolean", "description": "true if quantity, unit, price, or product identity is a guess."],
                "uncertaintyReason": ["type": .array(["string", "null"]), "description": "Short English reason when uncertain=true, else null."],
                "isDiscountOrDeposit": ["type": "boolean", "description": "true for PANTTI deposits, bottle returns, loyalty/campaign discounts, rounding, any negative adjustment."],
            ],
            "required": ["rawName", "canonicalName", "sourceLanguage", "translatedName", "quantity", "unit", "unitPrice", "lineTotal", "suggestedCategory", "uncertain", "uncertaintyReason", "isDiscountOrDeposit"],
        ]

        let vatLine: JSONValue = [
            "type": "object",
            "properties": [
                "rate": ["type": "number", "description": "VAT percent as printed, e.g. 25.5 or 14."],
                "amount": .object(["type": .string("string"), "description": .string("VAT amount (the Vero column, the tax itself) as decimal string.")]),
                "base": ["type": .array(["string", "null"]), "description": "Taxable base (the Veroton column) as decimal string; null if not printed."],
            ],
            "required": ["rate", "amount", "base"],
        ]

        return [
            "type": "object",
            "properties": [
                "isReceipt": ["type": "boolean", "description": "true only if the image shows a purchase receipt. If false, leave lineItems empty and all nullable fields null."],
                "store": [
                    "type": "object",
                    "properties": [
                        "rawName": ["type": .array(["string", "null"]), "description": "Store name exactly as printed, e.g. 'K-Market Munkkivuori'."],
                        "normalizedName": ["type": .array(["string", "null"]), "description": "Chain-level canonical store name, e.g. 'K-Market', 'Lidl', 'Prisma'."],
                    ],
                    "required": ["rawName", "normalizedName"],
                ],
                "date": ["type": .array(["string", "null"]), "format": "date", "description": "Purchase date as YYYY-MM-DD."],
                "time": ["type": .array(["string", "null"]), "description": "Purchase time as HH:MM:SS (seconds 00 if not printed)."],
                "paymentMethod": ["type": "string", "enum": ["card", "cash", "mobile", "other", "unknown"]],
                "lineItems": ["type": "array", "items": lineItem],
                "vatBreakdown": ["type": "array", "items": vatLine],
                "subtotal": .object(["type": .array(["string", "null"]), "description": .string("Printed subtotal as decimal string; null if not printed.")]),
                "total": .object(["type": .array(["string", "null"]), "description": .string("Final charged total ('YHTEENSÄ') as decimal string. Null only if isReceipt is false or unreadable.")]),
                "currency": ["type": "string", "description": "ISO 4217, almost always 'EUR'."],
                "confidence": ["type": "string", "enum": ["high", "medium", "low"]],
                "warnings": ["type": "array", "items": ["type": "string"]],
            ],
            "required": ["isReceipt", "store", "date", "time", "paymentMethod", "lineItems", "vatBreakdown", "subtotal", "total", "currency", "confidence", "warnings"],
        ]
    }

    static func receiptPrompt(
        knownProducts: [String],
        knownAliases: [KnownAlias],
        categories: [CategoryOption],
        fallbackCategory: String,
        todayISO: String,
        appLanguage: String
    ) -> String {
        let productsBlock = knownProducts.isEmpty ? "(none yet)" : knownProducts.joined(separator: "\n")
        let aliasesBlock = knownAliases.isEmpty ? "(none yet)" : knownAliases.map { "\($0.raw) => \($0.canonical)" }.joined(separator: "\n")
        let categoriesBlock = categories.map { option in
            option.hint.map { "\(option.name) — \($0)" } ?? option.name
        }.joined(separator: "\n")
        let appLanguageName = languageName(appLanguage)

        return """
        You are a precise receipt-parsing engine for a household finance app. Analyze the receipt image and return JSON matching the provided schema. Follow these rules exactly.

        LANGUAGE AND NUMBERS
        - Receipts are most often Finnish (sometimes bilingual Finnish/Swedish), but may be in any European language — Swedish, German, Dutch, Italian, Spanish, English, etc. Detect each line's language and report it in sourceLanguage.
        - Vocabulary by concept (recognize equivalents in any of these languages):
          - total: YHTEENSÄ/SUMMA (fi/sv), SUMME/GESAMT (de), TOTAAL (nl), TOTALE (it), TOTAL (es/en).
          - subtotal: VÄLISUMMA (fi), ZWISCHENSUMME (de), SUBTOTAAL (nl), SUBTOTALE (it), SUBTOTAL (es/en).
          - cash: KÄTEINEN (fi), BAR (de), CONTANT (nl), CONTANTI (it), EFECTIVO (es).
          - card: KORTTI/PANKKIKORTTI/LUOTTOKORTTI (fi), KARTE (de), KAART (nl), CARTA (it), TARJETA (es).
          - VAT: ALV/MOMS (fi/sv), MwSt/USt (de), BTW (nl), IVA (it/es), VAT (en).
          - bottle deposit: PANTTI (fi), PANT (sv), PFAND (de), STATIEGELD (nl). Deposit return: PANTIN PALAUTUS (fi).
          - discount: ALENNUS/TARJOUS/ETU (fi), RABATT (de/sv), KORTING (nl), SCONTO (it), DESCUENTO (es).
          - cash rounding: PYÖRISTYS (fi), RUNDUNG (de), AFRONDING (nl), ARROTONDAMENTO (it), REDONDEO (es).
        - Most of these locales use a COMMA decimal separator ("2,99" means 2.99); English uses a dot. ALWAYS output dot-separated strings ("2.99"): exactly 2 decimals, no currency symbol, '-' prefix for negatives.
        - Dates may be DD.MM.YYYY, DD/MM/YYYY, or DD.MM.YY. Convert to YYYY-MM-DD.

        LINE ITEMS
        - An item may span multiple printed lines. A typical weight-priced item:
            KURKKU SUOMI
              0,652 kg x 2,99 EUR/kg        1,95
          Merge into ONE line item: rawName "KURKKU SUOMI", quantity 0.652, unit "kg", unitPrice "2.99", lineTotal "1.95".
        - "3 x 1,25" patterns: quantity 3, unit "pcs", unitPrice "1.25".
        - If a line shows only a name and a price (e.g. "Banaani 1,20"): set quantity 1, unit "pcs", unitPrice equal to lineTotal, BUT if the product is typically sold by weight (fruit, vegetables, bulk candy, meat counter), set uncertain=true and uncertaintyReason "no quantity printed; product may be weight-priced". Never invent a weight that is not printed.
        - If unit price must be computed (lineTotal / quantity), round to 2 decimals.
        - Do NOT include the VAT summary table, subtotal, total, payment, change, or card-terminal lines as line items.

        DEPOSITS, DISCOUNTS, ROUNDING
        - Deposit lines (PANTTI/PANT/PFAND/STATIEGELD, typically 0,10/0,15/0,40 EUR) are separate line items: isDiscountOrDeposit=true, canonicalName in the receipt language ("Pantti", "Pfand"), translatedName "Deposit", positive lineTotal. A deposit return (PANTIN PALAUTUS) likewise with negative lineTotal.
        - Loyalty and campaign discounts (PLUSSA-ETU, S-Etukortti, Bonus, ALENNUS/RABATT/KORTING/SCONTO/DESCUENTO, percentage discounts) are separate line items: isDiscountOrDeposit=true, negative lineTotal, canonicalName describing the discount in the receipt language (e.g. "Plussa-etu"), translatedName the equivalent (e.g. "Loyalty discount"). Use the category of the discounted product if obvious, otherwise the most general category in the list.
        - A cash-rounding line (PYÖRISTYS/RUNDUNG/AFRONDING, max ±0,04) is a line item with isDiscountOrDeposit=true, canonicalName in the receipt language ("Pyöristys"), translatedName "Rounding".

        VAT
        - Finnish VAT rates: 25.5% (general), 14% (food), 10% and 0% (rare), 24% on receipts older than September 2024. Extract every row of the VAT table; "amount" is the tax amount itself (Vero/Moms column) and "base" is the taxable base (Veroton column) when printed, else null.

        STORE NORMALIZATION
        - rawName: exactly as printed. normalizedName: chain name only, dropping location/store-number suffixes. Known chains: Lidl, K-Market, K-Supermarket, K-Citymarket, Prisma, S-market, Alepa, Sale, Food Market Herkku, Tokmanni, Minimani, M-Market, Halpa-Halli, R-kioski, Alko, Motonet, Puuilo, Clas Ohlson, Rusta, IKEA, Apteekki (any pharmacy). Examples: "K-Market Munkkivuori" -> "K-Market", "LIDL HELSINKI-KANNELMÄKI" -> "Lidl". If the chain is not listed, use the printed brand name cleaned of location and legal suffixes (Oy, Ab, Ky).

        CANONICAL PRODUCT NAMES
        - Goal: the SAME real-world product gets the SAME canonicalName regardless of store or abbreviation; genuinely DIFFERENT products stay distinct.
        - Style: clean, concise, human-readable, capitalized like a normal product name, kept in the receipt's ORIGINAL language (do NOT translate canonicalName). Prefer the form already used in the KNOWN PRODUCTS list below.
        - Expand receipt abbreviations: "RUISP." -> "Ruispalat", "LAKT" -> "laktoositon", "TÄYSM" -> "täysmaito".
        - Keep the brand when it distinguishes the product: "ARLA LAKT TÄYSM 1L" -> "Arla laktoositon täysmaito 1L" (NOT "Maito"). Generic produce: "BANAANI" (Lidl) and "BANAANI" (Prisma) both -> "Banaani", but "Banana Chiquita luomu" stays distinct.
        - Keep size/fat-content/variant when printed and meaningful: "MAITO 1L RASVATON" -> "Rasvaton maito 1L", which is DIFFERENT from "Arla laktoositon maito 1L".
        - If a canonical name in KNOWN PRODUCTS clearly refers to the same product, reuse it EXACTLY (character for character). Never force a match to a known product that is actually different.

        TRANSLATION (translatedName)
        - Translate canonicalName into \(appLanguageName) and put it in translatedName. The translation is for display only — it does NOT replace canonicalName.
        - Set translatedName to null when canonicalName is ALREADY in \(appLanguageName), or when it is a brand/proper noun that should not be translated (e.g. "Coca-Cola", "Arla"). Keep brand tokens intact and translate only the descriptive words: "Arla laktoositon täysmaito 1L" -> "Arla lactose-free whole milk 1L".
        - Report the language you detected for the line in sourceLanguage.

        KNOWN PRODUCTS (most frequently purchased first):
        \(productsBlock)

        KNOWN RECEIPT-TEXT ALIASES (raw text as printed => canonical name):
        \(aliasesBlock)

        CATEGORIES
        - Assign each line item exactly one suggestedCategory from this closed list:
        \(categoriesBlock)
        - When unsure, choose "\(fallbackCategory)" and set uncertain=true.

        QUALITY AND HONESTY
        - If the image is not a purchase receipt (or unreadable), set isReceipt=false, confidence="low", add a warning explaining why, and return empty lineItems with null fields.
        - If parts are blurred, cut off, or covered, parse what is readable, set confidence "medium"/"low", add specific warnings.
        - The sum of all lineTotal values (including negatives) should equal total. If your extraction does not add up, re-check; if it still does not, add a warning "line items sum to X but total is Y".
        - Never invent items, prices, or dates. Today's date is \(todayISO) — a future receipt date is wrong.
        """
    }

    // MARK: - Product package identification

    static func productIDResponseSchema(appLanguage: String) -> JSONValue {
        let appLanguageName = languageName(appLanguage)
        return [
            "type": "object",
            "properties": [
                "productName": ["type": "string", "description": "Clean, concise product name in the package's original language, per the canonical naming rules."],
                "sourceLanguage": ["type": "string", "enum": ["fi", "sv", "de", "nl", "it", "es", "en", "unknown"], "description": "Detected language of the product name on the package."],
                "translatedName": ["type": .array(["string", "null"]), "description": .string("productName translated into \(appLanguageName). Null if already in \(appLanguageName) or a brand/proper noun.")],
                "brand": ["type": .array(["string", "null"])],
                "size": ["type": .array(["string", "null"]), "description": "Package size as printed, e.g. '1 l', '400 g'."],
                "confidence": ["type": "string", "enum": ["high", "medium", "low"]],
            ],
            "required": ["productName", "sourceLanguage", "translatedName", "brand", "size", "confidence"],
        ]
    }

    static func productIDPrompt(knownProducts: [String], appLanguage: String) -> String {
        let productsBlock = knownProducts.isEmpty ? "(none yet)" : knownProducts.joined(separator: "\n")
        let appLanguageName = languageName(appLanguage)
        return """
        Identify the grocery/household product shown in this photo of its packaging. Return JSON matching the schema.
        - productName: clean, concise, human-readable, in the package's ORIGINAL language. Keep the brand when it distinguishes the product, and the size/variant when visible (e.g. "Arla laktoositon maito 1L").
        - translatedName: productName translated into \(appLanguageName); null if already in \(appLanguageName) or a brand/proper noun. sourceLanguage: the detected language.
        - If a name in the KNOWN PRODUCTS list below clearly refers to the same product, reuse it EXACTLY.
        - Set confidence "low" and your best guess if the product is unclear.

        KNOWN PRODUCTS:
        \(productsBlock)
        """
    }
}
